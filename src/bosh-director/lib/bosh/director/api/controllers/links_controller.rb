require 'bosh/director/api/controllers/base_controller'

module Bosh::Director
  module Api::Controllers
    class LinksController < BaseController
      register Bosh::Director::Api::Extensions::DeploymentsSecurity

      def initialize(config)
        super(config)
        @deployment_manager = Api::DeploymentManager.new
        @links_api_manager = Api::LinksApiManager.new
      end

      get '/', authorization: :read do
        if params['provider_id'] && params['deployment']
          deployment = @deployment_manager.find_by_name(params['deployment'])
          links_for_consumers = get_consumed_links_for_deployment(deployment)

          provider = get_provider_by_id(params['provider_id'])

          desired_links = links_for_consumers.select do |l|
            l.link_provider_intent.link_provider == provider # TODO: this is `2n` db calls, improve.
          end
        elsif params['provider_id']
          provider = get_provider_by_id(params['provider_id'])

          desired_links = provider.intents.map(&:links).flatten # TODO: could this be more efficient?
        elsif params['deployment']
          deployment = @deployment_manager.find_by_name(params['deployment'])
          desired_links = get_consumed_links_for_deployment(deployment)
        else
          desired_links = Models::Links::Link.all
        end

        result = desired_links.map do |link|
          generate_link_hash(link)
        end

        body(json_encode(result))
      end

      post '/', authorization: :create_link, consumes: :json do
        payload = JSON.parse(request.body.read)
        begin
          link = @links_api_manager.create_link(payload)
          link_hash = generate_link_hash(link)

          body(json_encode(link_hash))
        rescue RuntimeError => e
          raise LinkCreateError, e
        end
      end

      delete '/:linkid', authorization: :delete_link do
        begin
          @links_api_manager.delete_link(params[:linkid])
        rescue RuntimeError => e
          raise LinkDeleteError, e
        end
        status(204)
        body(nil)
      end

      private

      def get_provider_by_id(provider_id)
        provider = Models::Links::LinkProvider[provider_id]
        raise LinkLookupError, "Invalid link provider id: #{provider_id}" if provider.nil?

        provider
      end

      def get_consumed_links_for_deployment(deployment_model)
        consumers = Models::Links::LinkConsumer.where(deployment: deployment_model)
        # TODO: this is `2n` db calls (i think), improve.
        links_for_consumers = consumers.map do |c|
          Models::Links::LinkConsumerIntent.where(link_consumer: c).map(&:links)
        end
        links_for_consumers.flatten!
      end

      def generate_link_hash(model)
        {
          id: model.id.to_s,
          name: model.name,
          link_consumer_id: model[:link_consumer_intent_id].to_s,
          link_provider_id: (model[:link_provider_intent_id].nil? ? nil : model[:link_provider_intent_id].to_s),
          created_at: model.created_at,
        }
      end
    end
  end
end
