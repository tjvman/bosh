require 'common/deep_copy'

module Bosh::Director
  module DeploymentPlan
    class CloudManifestParser
      include ValidationHelper

      def initialize(deployment, logger)
        @deployment = deployment
        @logger = logger
      end

      def parse(cloud_manifest)
        @cloud_manifest = cloud_manifest

        parse_availability_zones
        parse_networks
        parse_compilation
        parse_resource_pools
        parse_disk_pools

        @deployment
      end

      private

      def parse_availability_zones
        availability_zones = safe_property(@cloud_manifest, 'availability_zones', :class => Array, :optional => true)
        if availability_zones
          availability_zones.each do |availability_zone|
            @deployment.add_availability_zone(AvailabilityZone.new(availability_zone))
          end
        end
      end

      def parse_networks
        networks = safe_property(@cloud_manifest, 'networks', :class => Array)
        global_network_resolver = GlobalNetworkResolver.new(@deployment)

        networks.each do |network_spec|
          type = safe_property(network_spec, 'type', :class => String,
            :default => 'manual')

          case type
            when 'manual'
              ip_provider_factory = IpProviderFactory.new(@deployment.model, @logger, global_networking: @deployment.using_global_networking?)
              network = ManualNetwork.new(network_spec, global_network_resolver, ip_provider_factory, @logger)
            when 'dynamic'
              network = DynamicNetwork.new(network_spec, @logger)
            when 'vip'
              network = VipNetwork.new(network_spec, @logger)
            else
              raise DeploymentInvalidNetworkType,
                "Invalid network type `#{type}'"
          end

          @deployment.add_network(network)
        end

        if @deployment.networks.empty?
          raise DeploymentNoNetworks, 'No networks specified'
        end
      end

      def parse_compilation
        compilation_spec = safe_property(@cloud_manifest, 'compilation', :class => Hash)
        config = CompilationConfig.new(compilation_spec)
        unless @deployment.network(config.network_name)
            raise CompilationConfigUnknownNetwork,
              "Compilation config references an unknown " +
                "network `#{config.network_name}'"
        end
        @deployment.compilation = config
      end

      def parse_resource_pools
        resource_pools = safe_property(@cloud_manifest, 'resource_pools', :class => Array)
        resource_pools.each do |rp_spec|
          @deployment.add_resource_pool(ResourcePool.new(rp_spec, @logger))
        end

        if @deployment.resource_pools.empty?
          raise DeploymentNoResourcePools, 'No resource_pools specified'
        end
      end

      def parse_disk_pools
        disk_pools = safe_property(@cloud_manifest, 'disk_pools', :class => Array, :optional => true)
        return if disk_pools.nil?
        disk_pools.each do |dp_spec|
          @deployment.add_disk_pool(DiskPool.parse(dp_spec))
        end
      end
    end
  end
end
