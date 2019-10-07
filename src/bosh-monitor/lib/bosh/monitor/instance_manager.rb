module Bosh::Monitor
  class InstanceManager
    attr_reader :heartbeats_received
    attr_reader :alerts_received
    attr_reader :alerts_processed

    attr_accessor :processor

    def initialize(event_processor)
      # hash of agent_id to agent for all rogue agents
      @rogue_agents = {}
      # hash of deployment_name to deployment for all managed deployments
      @deployment_name_to_deployments = {}

      @logger = Bhm.logger
      @intervals = Bhm.intervals
      @heartbeats_received = 0
      @alerts_received = 0
      @alerts_processed = 0

      @processor = event_processor
    end

    # Get a hash of agent id -> agent object for all agents associated with the deployment
    def get_agents_for_deployment(deployment_name)
      deployment = @deployment_name_to_deployments[deployment_name]
      deployment ? deployment.agent_id_to_agent : {}
    end

    def get_deleted_agents_for_deployment(deployment_name)
      deployment = @deployment_name_to_deployments[deployment_name]
      deployment ? deployment.instance_id_to_agent : {}
    end

    def setup_events
      @processor.enable_pruning(Bhm.intervals.prune_events)
      Bhm.plugins.each do |plugin|
        @processor.add_plugin(lookup_plugin(plugin['name'], plugin['options']), plugin['events'])
      end

      EM.schedule do
        Bhm.nats.subscribe('hm.agent.heartbeat.*') do |message, _reply, subject|
          process_event(:heartbeat, subject, message)
        end

        Bhm.nats.subscribe('hm.agent.alert.*') do |message, _reply, subject|
          process_event(:alert, subject, message)
        end

        Bhm.nats.subscribe('hm.agent.shutdown.*') do |message, _reply, subject|
          process_event(:shutdown, subject, message)
        end
      end
    end

    def agents_count
      agents = Set.new(@rogue_agents.keys)
      agents.merge(all_managed_agent_ids)
      agents.size + all_managed_deleted_agents.size
    end

    def deployments_count
      @deployment_name_to_deployments.size
    end

    # Syncs deployments list received from director
    # with HM deployments.
    # @param deployments Array list of deployments returned by director
    def sync_deployments(deployments)
      active_deployment_names = sync_active_deployments(deployments)
      remove_inactive_deployments(active_deployment_names)
    end

    def sync_deployment_state(deployment, instances_data)
      deployment_name = deployment['name']
      sync_teams(deployment)
      sync_instances(deployment_name, instances_data)
      sync_agents(deployment_name, get_instances_for_deployment(deployment_name))
    end

    def get_instances_for_deployment(deployment_name)
      @deployment_name_to_deployments[deployment_name].instances
    end

    def analyze_agents
      @logger.info('Analyzing agents...')
      started = Time.now
      count = analyze_deployment_agents + analyze_rogue_agents
      @logger.info(format('Analyzed %s, took %s seconds', pluralize(count, 'agent'), Time.now - started))
      count
    end

    def analyze_agent(agent)
      ts = Time.now.to_i

      if agent.timed_out? && agent.rogue?
        # Agent has timed out but it was never
        # actually a proper member of the deployment,
        # so we don't really care about it
        remove_agent(agent.id)
        return
      end

      if agent.timed_out? && !@rogue_agents.key?(agent.id)
        @processor.process(:alert,
                           severity: 2,
                           category: Events::Alert::CATEGORY_VM_HEALTH,
                           source: agent.name,
                           title: "#{agent.id} has timed out",
                           created_at: ts,
                           deployment: agent.deployment,
                           job: agent.job,
                           instance_id: agent.instance_id)
      end

      if agent.rogue?
        @processor.process(:alert,
                           severity: 2,
                           source: agent.name,
                           title: "#{agent.id} is not a part of any deployment",
                           created_at: ts)
      end

      true
    end

    def analyze_instances
      @logger.info('Analyzing instances...')
      started = Time.now
      count = 0

      @deployment_name_to_deployments.values.each do |deployment|
        jobs_to_instances = Hash.new { |hash, job| hash[job] = [] }
        deployment.instances.each do |instance|
          if alert_needed?(instance)
            alert_single_instance(instance)
            jobs_to_instances[instance.job] << instance.id
          end
          count += 1
        end
        alert_aggregated_instances_if_needed(
          deployment.name,
          jobs_to_instances,
          "#{deployment.name} has instances which do not have VMs",
        )
      end

      @logger.info(format('Analyzed %s, took %s seconds', pluralize(count, 'instance'), Time.now - started))
      count
    end

    def alert_single_instance(instance)
      @processor.process(:alert,
                         severity: 2,
                         category: Events::Alert::CATEGORY_VM_HEALTH,
                         source: instance.name,
                         title: "#{instance.id} has no VM",
                         created_at: Time.now.to_i,
                         deployment: instance.deployment,
                         job: instance.job,
                         instance_id: instance.id)
    end

    def alert_needed?(instance)
      instance.expects_vm? && !instance.has_vm?
    end

    def process_event(kind, subject, payload = {})
      kind = kind.to_s
      agent_id = subject.split('.', 4).last
      agent = find_managed_agent_by_id(agent_id)

      if agent.nil? && @rogue_agents[agent_id]
        @logger.warn("Received #{kind} from unmanaged agent: #{agent_id}")
        agent = @rogue_agents[agent_id]
      elsif agent.nil?
        # There might be more than a single shutdown event,
        # we are only interested in processing it if agent
        # is still managed
        return if kind == 'shutdown'

        @logger.warn("Received #{kind} from unmanaged agent: #{agent_id}")
        agent = Agent.new(agent_id)
        @rogue_agents[agent_id] = agent
      else
        @logger.debug("Received #{kind} from #{agent_id}: #{payload}")
      end

      case payload
      when String
        message = JSON.parse(payload)
      when Hash
        message = payload
      end

      deployment = @deployment_name_to_deployments[agent.deployment]
      case kind.to_s
      when 'alert'
        on_alert(agent, message)
      when 'heartbeat'
        on_heartbeat(agent, deployment, message)
      when 'shutdown'
        on_shutdown(agent)
      else
        @logger.warn("No handler found for '#{kind}' event")
      end
    rescue JSON::ParserError => e
      @logger.error("Cannot parse incoming event: #{e}")
    rescue Bhm::InvalidEvent => e
      @logger.error("Invalid event: #{e}")
    end

    def instances_count
      @deployment_name_to_deployments.values.inject(0) { |count, deployment| count + deployment.instances.size }
    end

    private

    def alert_aggregated_instances_if_needed(deployment_name, jobs_to_instances, title)
      return if jobs_to_instances.empty?

      @processor.process(:alert,
                         severity: 2,
                         category: Events::Alert::CATEGORY_DEPLOYMENT_HEALTH,
                         source: deployment_name,
                         title: title,
                         created_at: Time.now.to_i,
                         deployment: deployment_name,
                         jobs_to_instance_ids: jobs_to_instances)
    end

    def lookup_plugin(name, options = {})
      plugin_class = nil
      begin
        class_name = name.to_s.split('_').map(&:capitalize).join
        plugin_class = Bosh::Monitor::Plugins.const_get(class_name)
      rescue NameError => e
        raise PluginError, "Cannot find '#{name}' plugin"
      end

      plugin_class.new(options)
    end

    def remove_agent(agent_id)
      @logger.info("Removing agent #{agent_id} from all deployments...")
      @rogue_agents.delete(agent_id)
      @deployment_name_to_deployments.values.each { |deployment| deployment.remove_agent(agent_id) }
    end

    def remove_deployment(name)
      deployment = @deployment_name_to_deployments[name]
      deployment.agent_ids.each { |agent_id| @rogue_agents.delete(agent_id) }
      @deployment_name_to_deployments.delete(name)
    end

    def on_alert(agent, message)
      if message.is_a?(Hash) && !message.key?('source')
        message['source'] = agent.name
        message['deployment'] = agent.deployment
        message['job'] = agent.job
        message['instance_id'] = agent.instance_id
      end

      @processor.process(:alert, message)
      @alerts_processed += 1
    end

    def on_shutdown(agent)
      @logger.info("Agent '#{agent.id}' shutting down...")
      remove_agent(agent.id)
    end

    def on_heartbeat(agent, deployment, message)
      agent.updated_at = Time.now

      if message.is_a?(Hash)
        message['timestamp'] = Time.now.to_i if message['timestamp'].nil?
        message['agent_id'] = agent.id
        message['deployment'] = agent.deployment
        message['job'] = agent.job
        message['instance_id'] = agent.instance_id
        message['teams'] = deployment ? deployment.teams : []

        return if message['instance_id'].nil? || message['job'].nil? || message['deployment'].nil?
      end

      @processor.process(:heartbeat, message)
      @heartbeats_received += 1
    end

    def analyze_rogue_agents
      count = 0
      @rogue_agents.keys.each do |agent_id|
        @logger.warn("Agent #{agent_id} is not a part of any deployment")
        analyze_agent(@rogue_agents[agent_id])
        count += 1
      end
      count
    end

    def analyze_deployment_agents
      count = 0
      @deployment_name_to_deployments.values.each do |deployment|
        jobs_to_instances = Hash.new { |hash, job| hash[job] = [] }
        deployment.agents.each do |agent|
          instance = deployment.instance(agent.instance_id)
          vm_created_at = instance.vm_created_at # created_at is nil if recreating VM, wait for VM to boot
          if !vm_created_at.nil? && ((DateTime.now - vm_created_at) * 24 * 60 * 60).to_i > @intervals.vm_start_timeout
            analyze_agent(agent)
            jobs_to_instances[agent.job] << agent.instance_id if agent.timed_out?
          end
          count += 1
        end
        alert_aggregated_instances_if_needed(
          deployment.name,
          jobs_to_instances,
          "#{deployment.name} has instances with timed out agents",
        )
      end
      count
    end

    def all_managed_agent_ids
      agent_ids = Set.new
      @deployment_name_to_deployments.values.each do |deployment|
        agent_ids.merge(deployment.agent_ids)
      end
      agent_ids
    end

    def all_managed_deleted_agents
      agents = Set.new
      @deployment_name_to_deployments.values.each do |deployment|
        agents.merge(deployment.instance_id_to_agent.values)
      end
      agents
    end

    def find_managed_agent_by_id(agent_id)
      @deployment_name_to_deployments.values.each do |deployment|
        return deployment.agent(agent_id) if deployment.agent(agent_id)
      end
      nil
    end

    def remove_inactive_deployments(active_deployment_names)
      all = Set.new(@deployment_name_to_deployments.keys)
      (all - active_deployment_names).each do |stale_deployment|
        @logger.warn("Found stale deployment #{stale_deployment}, removing...")
        remove_deployment(stale_deployment)
      end
    end

    def sync_active_deployments(deployments)
      active_deployment_names = Set.new
      deployments.each do |deployment_data|
        deployment = Deployment.create(deployment_data)
        @deployment_name_to_deployments[deployment.name] = deployment unless @deployment_name_to_deployments[deployment.name]
        active_deployment_names << deployment.name
      end
      active_deployment_names
    end

    def remove_inactive_instances(active_instances_ids, deployment)
      (deployment.instance_ids - active_instances_ids).each do |instance_id|
        deployment.remove_instance(instance_id)
      end
    end

    def sync_active_instances(deployment, instances_data)
      active_instances_ids = Set.new
      instances_data.each do |instance_data|
        instance = Bhm::Instance.create(instance_data)
        active_instances_ids << instance.id if deployment.add_instance(instance)
      end
      active_instances_ids
    end

    def remove_inactive_agents(active_agent_ids, deployment)
      (deployment.agent_ids - active_agent_ids).each do |agent_id|
        remove_agent(agent_id)
      end
    end

    def sync_active_agents(deployment, instances)
      active_agent_ids = Set.new
      instances.each do |instance|
        active_agent_ids << instance.agent_id if deployment.upsert_agent(instance)
      end
      active_agent_ids
    end

    def update_rogue_agents(deployment_agents)
      deployment_agents.each { |agent_id| @rogue_agents.delete(agent_id) }
    end

    def sync_teams(deployment)
      deployment_name = deployment['name']
      deployment_model = @deployment_name_to_deployments[deployment_name]
      deployment_model.update_teams(deployment['teams'])
      @deployment_name_to_deployments[deployment_name] = deployment_model
    end

    def sync_instances(deployment_name, instances_data)
      deployment = @deployment_name_to_deployments[deployment_name]
      active_instance_ids = sync_active_instances(deployment, instances_data)
      remove_inactive_instances(active_instance_ids, deployment)
    end

    def sync_agents(deployment_name, instances)
      deployment = @deployment_name_to_deployments[deployment_name]
      active_agent_ids = sync_active_agents(deployment, instances)
      remove_inactive_agents(active_agent_ids, deployment)
      update_rogue_agents(active_agent_ids)
    end
  end
end
