require 'bosh/director/deployment_plan/disk_type'
require 'forwardable'
require 'common/deep_copy'

module Bosh::Director
  # Encapsulates essential director data structures retrieved
  # from the deployment manifest and the running environment.
  module DeploymentPlan
    class Planner
      include LockHelper
      include ValidationHelper
      extend Forwardable

      # @return [String] Deployment name
      attr_reader :name

      # @return [String] Deployment canonical name (for DNS)
      attr_reader :canonical_name

      # @return [Models::Deployment] Deployment DB model
      attr_reader :model

      # @return [Bosh::Director::DeploymentPlan::UpdateConfig]
      #   Default job update configuration
      attr_accessor :update

      # @return [Array<Bosh::Director::DeploymentPlan::Job>]
      #   All instance_groups in the deployment
      attr_reader :instance_groups

      # Stemcells in deployment by alias
      attr_reader :stemcells

      # Tags in deployment by alias
      attr_reader :tags

      # Job instances from the old manifest that are not in the new manifest
      attr_reader :instance_plans_for_obsolete_instance_groups

      # @return [Boolean] Indicates whether VMs should be recreated
      attr_reader :recreate

      # @return [Boolean] Indicates whether persistent disks should be recreated
      attr_reader :recreate_persistent_disks

      attr_writer :cloud_planner

      # @return [DeploymentPlan::SkipDrain] Indicates whether VMs should be drained
      attr_reader :skip_drain

      # Hash with resolved aliases for stemcells and releases
      attr_reader :uninterpolated_manifest_hash

      # Text with raw manifest content
      attr_reader :raw_manifest_text

      # @return [DeploymentPlan::Variables] Returns the variables object of deployment
      attr_reader :variables

      # @return [DeploymentPlan::DeploymentFeatures] Returns the features object of deployment
      attr_reader :features

      attr_reader :template_blob_cache
      attr_reader :vm_resources_cache

      attr_accessor :addons

      attr_reader :cloud_configs
      attr_reader :runtime_configs

      attr_reader :links_manager

      def initialize(deployment_name,
                     uninterpolated_manifest_hash,
                     raw_manifest_text,
                     cloud_configs,
                     runtime_configs,
                     deployment_model,
                     options = {})
        @name = deployment_name
        @releases = {}

        @uninterpolated_manifest_hash = Bosh::Common::DeepCopy.copy(uninterpolated_manifest_hash)
        @raw_manifest_text = raw_manifest_text
        @cloud_configs = cloud_configs
        @runtime_configs = runtime_configs
        @model = deployment_model

        @stemcells = {}
        @instance_groups = []
        @instance_groups_name_index = {}
        @instance_groups_canonical_name_index = Set.new
        @tags = options.fetch('tags', {})

        @unneeded_vms = []
        @instance_plans_for_obsolete_instance_groups = []

        @is_deploy_action = !!options['is_deploy_action']
        @recreate = !!options['recreate']
        @recreate_persistent_disks = options['recreate_persistent_disks'] == true
        @fix = !!options['fix']

        @skip_drain = SkipDrain.new(options['skip_drain'])

        @variables = Variables.new([])
        @features = DeploymentFeatures.new

        @addons = []
        @logger = Config.logger

        @links_manager = Bosh::Director::Links::LinksManager.new(deployment_model.links_serial_id)

        @template_blob_cache = Bosh::Director::Core::Templates::TemplateBlobCache.new
        @vm_resources_cache = VmResourcesCache.new(AZCloudFactory.create_with_latest_configs(@model), @logger)
      end

      def_delegators :@cloud_planner,
                     :networks,
                     :network,
                     :availability_zone,
                     :availability_zones,
                     :vm_types,
                     :vm_type,
                     :vm_extensions,
                     :vm_extension,
                     :disk_types,
                     :disk_type,
                     :compilation,
                     :ip_provider

      def canonical_name
        Canonicalizer.canonicalize(@name)
      end

      def deployment_wide_options
        {
          fix: @fix,
          tags: @tags,
        }
      end

      # Returns a list of Instances in the deployment (according to DB)
      # @return [Array<Models::Instance>]
      def instance_models
        @model.instances
      end

      def existing_instances
        instance_models
      end

      def candidate_existing_instances
        desired_job_names = instance_groups.map(&:name)
        migrating_job_names = instance_groups.map(&:migrated_from).flatten.map(&:name)

        existing_instances.select do |instance|
          desired_job_names.include?(instance.job) ||
            migrating_job_names.include?(instance.job)
        end
      end

      def skip_drain_for_job?(name)
        @skip_drain.nil? ? false : @skip_drain.for_job(name)
      end

      def add_stemcell(stemcell)
        @stemcells[stemcell.alias] = stemcell
      end

      def stemcell(name)
        @stemcells[name]
      end

      # Adds a release by name
      # @param [Bosh::Director::DeploymentPlan::ReleaseVersion] release
      def add_release(release)
        if @releases.key?(release.name)
          raise DeploymentDuplicateReleaseName,
                "Duplicate release name '#{release.name}'"
        end
        @releases[release.name] = release
      end

      # Adds variables and gives error if there is a duplicate variable already.
      # @param [Bosh::Director::DeploymentPlan::Variables] variables
      def add_variables(variables)
        variables.spec.each do |variable|
          if @variables.contains_variable?(variable['name'])
            raise DeploymentDuplicateVariableName,
                  "Duplicate variable name '#{variable['name']}'"
          end
        end
        @variables.add(variables)
      end

      # Returns all releases in a deployment plan
      # @return [Array<Bosh::Director::DeploymentPlan::ReleaseVersion>]
      def releases
        @releases.values
      end

      # Returns a named release
      # @return [Bosh::Director::DeploymentPlan::ReleaseVersion]
      def release(name)
        @releases[name]
      end

      def instance_plans_with_missing_vms
        instance_groups_starting_on_deploy.collect_concat(&:instance_plans_with_missing_vms)
      end

      def instance_plans_with_create_swap_delete_and_needs_duplicate_vm
        instance_plans = instance_groups_starting_on_deploy.collect_concat do |instance_group|
          next unless instance_group.should_create_swap_delete?
          instance_group.unignored_instance_plans_needing_duplicate_vm
        end
        instance_plans.compact
      end

      def skipped_instance_plans_with_create_swap_delete_and_needs_duplicate_vm
        skipped_instance_plans = instance_groups_starting_on_deploy.collect_concat do |instance_group|
          next if instance_group.create_swap_delete? == instance_group.should_create_swap_delete?
          instance_group.unignored_instance_plans_needing_duplicate_vm
        end
        skipped_instance_plans.compact
      end

      def mark_instance_plans_for_deletion(instance_plans)
        @instance_plans_for_obsolete_instance_groups = instance_plans
      end

      # Adds a instance_group by name
      # @param [Bosh::Director::DeploymentPlan::InstanceGroup] instance_group
      def add_instance_group(instance_group)
        if @instance_groups_canonical_name_index.include?(instance_group.canonical_name)
          raise DeploymentCanonicalJobNameTaken,
                "Invalid instance group name '#{instance_group.name}', canonical name already taken"
        end

        @instance_groups << instance_group
        @instance_groups_name_index[instance_group.name] = instance_group
        @instance_groups_canonical_name_index << instance_group.canonical_name
      end

      # Returns a named instance_group
      # @param [String] name Instance group name
      # @return [Bosh::Director::DeploymentPlan::InstanceGroup] Instance group
      def instance_group(name)
        @instance_groups_name_index[name]
      end

      def instance_groups_starting_on_deploy
        instance_groups = []

        @instance_groups.each do |instance_group|
          if instance_group.service?
            instance_groups << instance_group
          elsif instance_group.errand?
            if instance_group.instances.any?(&:vm_created?) || instance_group.instances.any? { |i| i.model.state == 'detached' }
              instance_groups << instance_group
            end
          end
        end

        instance_groups
      end

      # @return [Array<Bosh::Director::DeploymentPlan::InstanceGroup>] InstanceGroups with errand lifecycle
      def errand_instance_groups
        @instance_groups.select(&:errand?)
      end

      def set_variables(variables_obj)
        @variables = variables_obj
      end

      def set_features(features_obj)
        @features = features_obj
      end

      def use_dns_addresses?
        @features.use_dns_addresses.nil? ? Config.local_dns_use_dns_addresses? : @features.use_dns_addresses
      end

      def use_short_dns_addresses?
        @features.use_short_dns_addresses.nil? ? false : @features.use_short_dns_addresses
      end

      def use_link_dns_names?
        @features.use_link_dns_names
      end

      def randomize_az_placement?
        @features.randomize_az_placement.nil? ? false : @features.randomize_az_placement
      end

      def use_tmpfs_config
        @features.use_tmpfs_config
      end

      def recreate_persistent_disks?
        @recreate_persistent_disks
      end

      def availability_zone_names
        @cloud_planner.availability_zone_names
      end

      def team_names
        @model.teams.map(&:name)
      end

      def is_deploy?
        @is_deploy_action
      end

      def link_provider_intents
        model.link_providers.flat_map(&:intents)
      end
    end
  end
end
