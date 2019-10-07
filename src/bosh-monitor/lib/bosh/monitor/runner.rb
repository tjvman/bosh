module Bosh::Monitor
  class Runner
    include YamlHelper

    def self.run(config_file)
      new(config_file).run
    end

    def initialize(config_file)
      Bhm.config = load_yaml_file(config_file)

      @logger        = Bhm.logger
      @director      = Bhm.director
      @intervals     = Bhm.intervals
      @mbus          = Bhm.mbus
      @instance_manager = Bhm.instance_manager
      @resurrection_manager = Bhm.resurrection_manager
      EM.threadpool_size = Bhm.em_threadpool_size
    end

    def run
      @logger.info('HealthMonitor starting...')
      EM.kqueue if EM.kqueue?
      EM.epoll if EM.epoll?

      EM.error_handler { |e| handle_em_error(e) }

      EM.run do
        connect_to_mbus
        @director_monitor = DirectorMonitor.new(Bhm)
        @director_monitor.subscribe
        @instance_manager.setup_events
        setup_timers
        start_http_server
        update_resurrection_config
        @logger.info("BOSH HealthMonitor #{Bhm::VERSION} is running...")
      end
    end

    def stop
      @logger.info('HealthMonitor shutting down...')
      @http_server&.stop!
    end

    def setup_timers
      EM.schedule do
        poll_director
        EM.add_periodic_timer(@intervals.poll_director) { poll_director }
        EM.add_periodic_timer(@intervals.log_stats) { log_stats }
        EM.add_periodic_timer(@intervals.resurrection_config) { update_resurrection_config }
        EM.add_timer(@intervals.poll_grace_period) do
          EM.add_periodic_timer(@intervals.analyze_agents) { analyze_agents }
          EM.add_periodic_timer(@intervals.analyze_instances) { analyze_instances }
        end
      end
    end

    def log_stats
      n_deployments = pluralize(@instance_manager.deployments_count, 'deployment')
      n_agents = pluralize(@instance_manager.agents_count, 'agent')
      @logger.info("Managing #{n_deployments}, #{n_agents}")
      @logger.info(format('Agent heartbeats received = %<heartbeats>s', heartbeats: @instance_manager.heartbeats_received))
    end

    def update_resurrection_config
      @logger.debug('Getting resurrection config from director...')
      Fiber.new { fetch_resurrection_config }.resume
    end

    def connect_to_mbus
      NATS.on_error do |e|
        unless @shutting_down
          redacted_msg = @mbus.password.nil? ? "NATS client error: #{e}" : "NATS client error: #{e}".gsub(@mbus.password, '*****')
          if e.is_a?(NATS::ConnectError)
            handle_em_error(redacted_msg)
          else
            log_exception(redacted_msg)
          end
        end
      end

      nats_client_options = {
        uri: @mbus.endpoint,
        autostart: false,
        max_reconnect_attempts: -1,
        tls: {
          ca_file: @mbus.server_ca_path,
          private_key_file: @mbus.client_private_key_path,
          cert_chain_file: @mbus.client_certificate_path,
        },
        ssl: true,
      }

      Bhm.nats = NATS.connect(nats_client_options) do
        @logger.info("Connected to NATS at '#{@mbus.endpoint}'")
      end
    end

    def start_http_server
      @logger.info("HTTP server is starting on port #{Bhm.http_port}...")
      @http_server = Thin::Server.new('127.0.0.1', Bhm.http_port, signals: false) do
        Thin::Logging.silent = true
        map '/' do
          run Bhm::ApiController.new
        end
      end
      @http_server.start!
    end

    def poll_director
      @logger.debug('Getting deployments from director...')
      Fiber.new { fetch_deployments }.resume
    end

    def analyze_agents
      # N.B. Yes, this will block event loop,
      # possibly consider deferring
      @instance_manager.analyze_agents
    end

    def analyze_instances
      @instance_manager.analyze_instances
    end

    private

    # This is somewhat controversial approach: instead of swallowing some exceptions
    # and letting event loop run further we force our server to stop. The rationale
    # behind that is to avoid the situation when swallowed exception actually breaks
    # things:
    # 1. Periodic timer will get canceled unless we manually reschedule it
    #    in a rescue clause even if we swallow the exception.
    # 2. If we want to perform an operation on next tick AND schedule some operation
    #    to be run periodically AND there is an exception swallowed somewhere during the
    #    event processing, then on the next tick we don't really process events that follow the buggy one.
    # These things can be pretty painful for HM as we might think it runs fine
    # when it actually just swallows some exception and effectively does nothing.
    # We might revisit that later
    def handle_em_error(err)
      @shutting_down = true
      log_exception(err, :fatal)
      stop
    end

    def log_exception(err, level = :error)
      level = :error unless level == :fatal
      @logger.send(level, err.to_s)
      @logger.send(level, err.backtrace.join("\n")) if err.respond_to?(:backtrace) && err.backtrace.respond_to?(:join)
    end

    def alert_director_error(message)
      Bhm.event_processor.process(
        :alert,
        id: SecureRandom.uuid,
        severity: 3,
        title: 'Health monitor failed to connect to director',
        summary: message,
        created_at: Time.now.to_i,
        source: 'hm',
      )
    end

    def fetch_deployments
      deployments = @director.deployments

      @instance_manager.sync_deployments(deployments)

      deployments.each do |deployment|
        deployment_name = deployment['name']

        @logger.info("Found deployment '#{deployment_name}'")

        @logger.debug("Fetching instances information for '#{deployment_name}'...")
        instances_data = @director.get_deployment_instances(deployment_name)
        @instance_manager.sync_deployment_state(deployment, instances_data)
      end
    rescue Bhm::DirectorError => e
      log_exception(e)
      alert_director_error(e.message)
    end

    def fetch_resurrection_config
      @logger.debug('Fetching resurrection config information...')

      resurrection_config = @director.resurrection_config
      @resurrection_manager.update_rules(resurrection_config)
    rescue Bhm::DirectorError => e
      log_exception(e)
      alert_director_error(e.message)
    end
  end
end
