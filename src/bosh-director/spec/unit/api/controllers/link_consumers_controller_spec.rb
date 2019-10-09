require 'spec_helper'
require 'rack/test'

module Bosh::Director
  module Api
    describe Controllers::LinkConsumersController do
      include Rack::Test::Methods

      subject(:app) { described_class.new(config) }
      let(:config) do
        config = Config.load_hash(SpecHelper.spec_get_director_config)
        identity_provider = Support::TestIdentityProvider.new(config.get_uuid_provider)
        allow(config).to receive(:identity_provider).and_return(identity_provider)
        config
      end

      before do
        App.new(config)
        basic_authorize 'admin', 'admin'
      end

      context 'when checking link consumer' do
        let(:deployment) { Models::Deployment.create(:name => 'test_deployment', :manifest => YAML.dump({'foo' => 'bar'})) }

        it 'list consumers endpoint exists' do
          get "/?deployment=#{deployment.name}"
          expect(last_response.status).to eq(200)
        end

        context 'when teams are used' do
          let(:dev_team) { Models::Team.create(:name => 'dev') }
          let(:other_team) { Models::Team.create(:name => 'other') }

          let!(:owned_deployment) { Models::Deployment.create_with_teams(:name => 'owned_deployment', teams: [dev_team], manifest: YAML.dump({'foo' => 'bar'})) }
          let!(:other_deployment) { Models::Deployment.create_with_teams(:name => 'other_deployment', teams: [other_team], manifest: YAML.dump({'foo' => 'bar'})) }

          before do
            basic_authorize 'dev-team-member', 'dev-team-member'
          end

          it 'allows access to owned deployment' do
            expect(get("/?deployment=#{owned_deployment.name}").status).to eq(200)
          end

          it 'denies access to other deployment' do
            expect(get("/?deployment=#{other_deployment.name}").status).to eq(401)
          end
        end

        context 'when user has read access' do
          before do
            basic_authorize 'reader', 'reader'
          end

          it 'returns the links' do
            get "/?deployment=#{deployment.name}"
            expect(last_response.status).to eq(200)
          end
        end

        it 'with invalid link deployment name' do
          get '/?deployment=invalid_deployment_name'
          expect(last_response.status).to eq(404)
          expect(last_response.body).to eq("{\"code\":70000,\"description\":\"Deployment 'invalid_deployment_name' doesn't exist\"}")
        end

        it 'returns 400 if deployment name is not provided' do
          get '/'
          expect(last_response.status).to eq(400)
          expect(last_response.body).to eq('{"code":190024,"description":"Deployment name is required"}')
        end

        context 'and there are consumers in the database' do
          let!(:consumer_1) do
            Models::Links::LinkConsumer.create(
              :deployment => deployment,
              :instance_group => 'instance_group',
              :type => 'job',
              :name => 'job_name_1',
            )
          end

          let!(:consumer_intent_1) do
            Models::Links::LinkConsumerIntent.create(
              :link_consumer => consumer_1,
              :original_name => 'link_1',
              :type => 'link_type_1',
              :name => 'link_alias_1',
              :optional => false,
              :blocked => false
              )
          end

          let!(:consumer_2) do
            Models::Links::LinkConsumer.create(
              :deployment => deployment,
              :instance_group => 'instance_group',
              :type => 'job',
              :name => 'job_name_2',
            )
          end

          let!(:consumer_intent_2) do
            Models::Links::LinkConsumerIntent.create(
              :link_consumer => consumer_1,
              :original_name => 'link_2',
              :type => 'link_type_2',
              :name => 'link_alias_2',
              :optional => false,
              :blocked => false
            )
          end

          it 'should return a list of consumers for specified deployment' do
            get "/?deployment=#{consumer_1.deployment.name}"
            expect(last_response.status).to eq(200)
            expect(JSON.parse(last_response.body)).to eq([generate_consumer_hash(consumer_intent_1), generate_consumer_hash(consumer_intent_2)])
          end
        end

        context 'and there are external consumers in the database' do
          let!(:consumer_1) do
            Models::Links::LinkConsumer.create(
              :deployment => deployment,
              :instance_group => '',
              :type => 'external',
              :name => 'job_name_1',
              )
          end

          let!(:consumer_intent_1) do
            Models::Links::LinkConsumerIntent.create(
              :link_consumer => consumer_1,
              :original_name => 'link_1',
              :type => 'link_type_1',
              :name => 'link_alias_1',
              :optional => false,
              :blocked => false
            )
          end

          it 'should return a list of consumers for specified deployment' do
            get "/?deployment=#{consumer_1.deployment.name}"
            expect(last_response.status).to eq(200)
            expect(JSON.parse(last_response.body)).to eq([generate_consumer_hash(consumer_intent_1)])
          end
        end

      end

      context 'when fetching link consumer by id' do
        context 'when user has read access' do
          before do
            basic_authorize 'reader', 'reader'
          end

          context 'when a link consumer with the specified id exists' do
            let(:deployment) { Models::Deployment.create(name: 'test_deployment', manifest: YAML.dump('foo' => 'bar')) }

            let!(:link_consumer) do
              Models::Links::LinkConsumer.create(
                deployment: deployment,
                instance_group: 'instance_group',
                type: 'job',
                name: 'job_name',
              )
            end
            let!(:link_consumer_intent) do
              Models::Links::LinkConsumerIntent.create(
                name: 'link_name',
                link_consumer: link_consumer,
                type: 'link_type',
                original_name: 'link_original_name',
              )
            end

            it 'returns the link consumer' do
              get '/1'
              expect(last_response.status).to eq(200)
              expect(JSON.parse(last_response.body)).to eq(generate_consumer_hash(link_consumer_intent))
            end
          end

          context 'when no link consumer with the specified id exists' do
            it 'returns a not found error' do
              get '/1'
              expect(last_response.status).to eq(404)
            end
          end
        end

        context 'when the user does not have read access' do
          before do
            basic_authorize 'invalid', 'invalid'
          end

          it 'returns a 401' do
            expect(get('/1').status).to eq(401)
          end
        end
      end

      def generate_consumer_hash(model)
        consumer = model.link_consumer
        result = {
          'id' => model.id.to_s,
          'name' => model.name,
          'optional' => model.optional,
          'deployment' => consumer.deployment.name,
          'owner_object' => {
            'type' => consumer.type,
            'name' => consumer.name,
            'info' => {
              'instance_group' => consumer.instance_group,
            },
          },
          'link_consumer_definition' => {
            'type' => model.type,
            'name' => model.original_name,
          },
        }
        result['owner_object'].delete('info') if consumer.instance_group == ''
        result
      end
    end
  end
end
