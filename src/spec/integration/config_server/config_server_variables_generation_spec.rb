require_relative '../../spec_helper'

describe 'variable generation with config server', type: :integration do
  with_reset_sandbox_before_each(config_server_enabled: true, user_authentication: 'uaa')

  def prepend_namespace(key)
    "/#{director_name}/#{deployment_name}/#{key}"
  end

  let(:manifest_hash) do
    Bosh::Spec::Deployments.manifest_with_release.merge(
      'instance_groups' => [Bosh::Spec::Deployments.instance_group_with_many_jobs(
        name: 'our_instance_group',
        jobs: [
          {
            'name' => 'job_1_with_many_properties',
            'release' => 'bosh-release',
            'properties' => job_properties,
          },
        ],
        instances: 1,
      )],
    )
  end
  let(:deployment_name) { manifest_hash['name'] }
  let(:director_name) { current_sandbox.director_name }
  let(:cloud_config)  { Bosh::Spec::Deployments.simple_cloud_config }
  let(:config_server_helper) { Bosh::Spec::ConfigServerHelper.new(current_sandbox, logger)}
  let(:client_env) do
    { 'BOSH_CLIENT' => 'test', 'BOSH_CLIENT_SECRET' => 'secret', 'BOSH_CA_CERT' => current_sandbox.certificate_path.to_s }
  end
  let(:job_properties) do
    {
      'gargamel' => {
        'color' => 'red'
      },
      'smurfs' => {
        'color' => 'blue'
      }
    }
  end

  before do
    manifest_hash['variables'] = variables
  end

  context 'when variables are defined in manifest' do
    context 'when variables syntax is valid' do
      let(:variables) do
        [
          {
            'name' => 'var_a',
            'type' => 'password'
          },
          {
            'name' => '/var_b',
            'type' => 'password'
          },
        ]
      end

      it 'should generate the variables and record them in events' do
        deploy_from_scratch(no_login: true, manifest_hash: manifest_hash, cloud_config_hash: cloud_config, include_credentials: false, env: client_env)

        var_a = config_server_helper.get_value(prepend_namespace('var_a'))
        var_b = config_server_helper.get_value('/var_b')

        expect(var_a).to_not be_empty
        expect(var_b).to_not be_empty

        events_output = bosh_runner.run('events', no_login: true, json: true, include_credentials: false, env: client_env)
        scrubbed_events = scrub_event_time(scrub_random_cids(scrub_random_ids(table(events_output))))
        scrubbed_variables_events = scrubbed_events.select{ | event | event['object_type'] == 'variable'}

        expect(scrubbed_variables_events.size).to eq(2)
        expect(scrubbed_variables_events).to include(
           {'id' => /[0-9]{1,3}/, 'time' => 'xxx xxx xx xx:xx:xx UTC xxxx', 'user' => 'test', 'action' => 'create', 'object_type' => 'variable', 'task_id' => /[0-9]{1,3}/, 'object_name' => '/TestDirector/simple/var_a', 'deployment' => 'simple', 'instance' => '', 'context' => /id: \"[0-9]{1,3}\"\nname: \/TestDirector\/simple\/var_a/, 'error' => ''},
           {'id' => /[0-9]{1,3}/, 'time' => 'xxx xxx xx xx:xx:xx UTC xxxx', 'user' => 'test', 'action' => 'create', 'object_type' => 'variable', 'task_id' => /[0-9]{1,3}/, 'object_name' => '/var_b', 'deployment' => 'simple', 'instance' => '', 'context' => /id: \"[0-9]{1,3}\"\nname: \/var_b/, 'error' => ''},
         )
      end

      context 'when a certificate needs to be generated' do
        let(:variables) do
          [
            {
              'name' => 'var_c',
              'type' => 'certificate',
              'options' => {
                  'is_ca' => true,
                  'common_name' => 'smurfs.io CA',
              }
            },
            {
              'name' => 'var_d',
              'type' => 'certificate',
              'options' => {
                  'common_name' => 'bosh.io',
                  'alternative_names' => ['a.bosh.io', 'b.bosh.io'],
                  'ca' => 'var_c'
              }
            }
          ]
        end

        it 'should generate a CA or reference a generated CA' do
          deploy_from_scratch(no_login: true, manifest_hash: manifest_hash, cloud_config_hash: cloud_config, include_credentials: false, env: client_env)

          var_c = config_server_helper.get_value(prepend_namespace('var_c'))
          var_d = config_server_helper.get_value(prepend_namespace('var_d'))
          expect(var_c).to_not be_empty
          expect(var_d).to_not be_empty

          expect(var_c['private_key']).to_not be_empty
          expect(var_d['private_key']).to_not be_empty
          expect(var_d['ca']).to_not be_empty

          ca_cert = OpenSSL::X509::Certificate.new(var_c['certificate'])
          expect(ca_cert.subject.to_s).to include('CN=smurfs.io CA')
          signed_cert = OpenSSL::X509::Certificate.new(var_d['certificate'])
          expect(signed_cert.subject.to_s).to include('CN=bosh.io')

          expect(signed_cert.issuer).to eq(ca_cert.subject)

          subject_alt_name_d = signed_cert.extensions.find {|e| e.oid == 'subjectAltName'}
          expect(subject_alt_name_d.to_s.scan(/a.bosh.io/).count).to eq(1)
          expect(subject_alt_name_d.to_s.scan(/b.bosh.io/).count).to eq(1)
        end

        context "when the root CA reference doesn't exist" do
          let(:variables) do
            [
              {
                  'name' => 'var_d',
                  'type' => 'certificate',
                  'options' => {
                      'common_name' => 'bosh.io',
                      'alternative_names' => ['a.bosh.io', 'b.bosh.io'],
                      'ca' => 'ca_that_doesnt_exist'
                  }
              }
            ]
          end
          it 'should throw an error' do
            output, exit_code =  deploy_from_scratch(no_login: true,
               manifest_hash: manifest_hash,
               cloud_config_hash: cloud_config,
               include_credentials: false,
               env: client_env,
               failure_expected: true,
               return_exit_code: true)

            expect(exit_code).to_not eq(0)
            expect(output).to include("Config Server failed to generate value for '/TestDirector/simple/var_d' with type 'certificate'. HTTP Code '400', Error: 'Loading certificates: No certificate found'")
          end
        end
      end

      context 'when a variable already exists in config server' do
        context 'when the coverge variables feature is enabled' do
          before do
            manifest_hash['features'] = {
              'converge_variables' => true,
            }
          end

          context 'when the variable options change' do
            it 'regenerates variables' do
              deploy_from_scratch(
                no_login: true,
                manifest_hash: manifest_hash,
                cloud_config_hash: cloud_config,
                include_credentials: false,
                env: client_env,
              )

              var_a1 = config_server_helper.get_value(prepend_namespace('var_a'))

              variables[0]['options'] = { 'gargamel' => 'sleeping' }
              manifest_hash['variables'] = variables
              deploy_from_scratch(
                no_login: true,
                manifest_hash: manifest_hash,
                cloud_config_hash: cloud_config,
                include_credentials: false,
                env: client_env,
              )

              var_a2 = config_server_helper.get_value(prepend_namespace('var_a'))
              expect(var_a2).to_not eq(var_a1)
            end
          end

          it 'does NOT re-generate it' do
            deploy_from_scratch(
              no_login: true,
              manifest_hash: manifest_hash,
              cloud_config_hash: cloud_config,
              include_credentials: false,
              env: client_env,
            )
            var_a1 = config_server_helper.get_value(prepend_namespace('var_a'))

            deploy_from_scratch(
              no_login: true,
              manifest_hash: manifest_hash,
              cloud_config_hash: cloud_config,
              include_credentials: false,
              env: client_env,
            )

            var_a2 = config_server_helper.get_value(prepend_namespace('var_a'))
            expect(var_a2).to eq(var_a1)
          end
        end

        context 'and the variable update_mode has been specified to overwrite' do
          let(:variables) do
            [
              {
                'name' => 'var_a',
                'type' => 'password',
              },
              {
                'name' => 'var_b',
                'type' => 'password',
                'update_mode' => 'converge',
              },
            ]
          end

          it 'always regenerates the credential' do
            deploy_from_scratch(
              no_login: true,
              manifest_hash: manifest_hash,
              cloud_config_hash: cloud_config,
              include_credentials: false,
              env: client_env,
            )

            var_a1 = config_server_helper.get_value(prepend_namespace('var_a'))
            var_b1 = config_server_helper.get_value(prepend_namespace('var_b'))

            variables[1]['options'] = { 'length' => 30 }
            manifest_hash['variables'] = variables
            deploy_from_scratch(
              no_login: true,
              manifest_hash: manifest_hash,
              cloud_config_hash: cloud_config,
              include_credentials: false,
              env: client_env,
            )

            var_a2 = config_server_helper.get_value(prepend_namespace('var_a'))
            expect(var_a2).to eq(var_a1)
            var_b2 = config_server_helper.get_value(prepend_namespace('var_b'))
            expect(var_b2).to_not eq(var_b1)
          end
        end

        it 'does NOT re-generate it' do
          config_server_helper.put_value(prepend_namespace('var_a'), 'password_a')

          deploy_from_scratch(
            no_login: true,
            manifest_hash: manifest_hash,
            cloud_config_hash: cloud_config,
            include_credentials: false,
            env: client_env,
          )

          var_a = config_server_helper.get_value(prepend_namespace('var_a'))
          expect(var_a).to eq('password_a')
        end
      end

      context 'when a variable type is not known by the config server' do
        before do
          variables << {'name' => 'var_e', 'type' => 'meow'}
        end

        it 'throws an error' do
          output, exit_code = deploy_from_scratch(
            no_login: true,
            manifest_hash: manifest_hash,
            cloud_config_hash: cloud_config,
            include_credentials: false,
            env: client_env,
            failure_expected: true,
            return_exit_code: true
          )

          expect(exit_code).to_not eq(0)
          expect(output).to include ("Error: Config Server failed to generate value for '/TestDirector/simple/var_e' with type 'meow'. HTTP Code '400', Error: 'Unsupported value type: meow'")
        end
      end

      context 'when variable is referenced by the manifest' do
        let(:job_properties) do
          {
            'gargamel' => {
              'color' => '((var_a))'
            },
            'smurfs' => {
              'color' => '((/var_b))'
            }
          }
        end

        it 'should use the variable generated value' do
          deploy_from_scratch(no_login: true, manifest_hash: manifest_hash, cloud_config_hash: cloud_config, include_credentials: false, env: client_env)

          var_a = config_server_helper.get_value(prepend_namespace('var_a'))
          var_b = config_server_helper.get_value('/var_b')

          instance = director.instance('our_instance_group', '0', deployment_name: 'simple', include_credentials: false,  env: client_env)

          template_hash = YAML.load(instance.read_job_template('job_1_with_many_properties', 'properties_displayer.yml'))
          expect(template_hash['properties_list']['gargamel_color']).to eq(var_a)
          expect(template_hash['properties_list']['smurfs_color']).to eq(var_b)
        end

        it 'should show changed variables in the diff lines under instance groups' do
          deploy_from_scratch(no_login: true, manifest_hash: manifest_hash, cloud_config_hash: cloud_config, include_credentials: false, env: client_env)

          manifest_hash['instance_groups'][0]['instances'] = 2
          manifest_hash['variables'][2] = {'name' => 'var_c', 'type' => 'password'}
          manifest_hash['instance_groups'][0]['jobs'][0]['properties']['gargamel']['color'] = "((var_c))"

          deploy_output = deploy(manifest_hash: manifest_hash, failure_expected: false, redact_diff: true, include_credentials: false, env: client_env)

          expect(deploy_output).to match(/variables:/)
          expect(deploy_output).to match(/gargamel:/)
          expect(deploy_output).to match(/- name: var_c/)
          expect(deploy_output).to match(/type: password/)
        end

        it 'should not regenerate values when calling restart/stop/start/recreate' do
          max_variables_events_count = 2

          deploy_from_scratch(no_login: true, manifest_hash: manifest_hash, cloud_config_hash: cloud_config, include_credentials: false, env: client_env)
          deploy_events = table(bosh_runner.run('events', no_login: true, json: true, include_credentials: false, env: client_env))
          expect(deploy_events.count{ | event | event['object_type'] == 'variable'}).to eq(max_variables_events_count)

          var_a = config_server_helper.get_value(prepend_namespace('var_a'))
          var_b = config_server_helper.get_value('/var_b')

          ['stop', 'start', 'restart', 'recreate'].each do |command|
            bosh_runner.run(command, deployment_name: 'simple', no_login: true, include_credentials: false, env: client_env)
            events = table(bosh_runner.run('events', no_login: true, json: true, include_credentials: false, env: client_env))
            expect(events.count{ | event | event['object_type'] == 'variable'}).to eq(max_variables_events_count)

            instance = director.instance('our_instance_group', '0', deployment_name: 'simple', include_credentials: false,  env: client_env)

            template_hash = YAML.load(instance.read_job_template('job_1_with_many_properties', 'properties_displayer.yml'))
            expect(template_hash['properties_list']['gargamel_color']).to eq(var_a)
            expect(template_hash['properties_list']['smurfs_color']).to eq(var_b)
          end
        end

        context 'when an addon section references a variable to be generated' do
          let(:variables) do
            [
                {
                    'name' => 'var_a',
                    'type' => 'password'
                },
                {
                    'name' => '/var_b',
                    'type' => 'password'
                },
                {
                    'name' => 'var_c',
                    'type' => 'password'
                },
                {
                    'name' => '/var_d',
                    'type' => 'password'
                },
            ]
          end

          shared_examples_for 'a deployment manifest that has addons section with variables' do
            it 'should deploy successfully' do
              deploy_from_scratch(no_login: true, manifest_hash: manifest_hash, cloud_config_hash: cloud_config, include_credentials: false, env: client_env)

              var_a = config_server_helper.get_value(prepend_namespace('var_a'))
              var_b = config_server_helper.get_value('/var_b')
              var_c = config_server_helper.get_value(prepend_namespace('var_c'))
              var_d = config_server_helper.get_value('/var_d')

              instance = director.instance('our_instance_group', '0', deployment_name: 'simple', include_credentials: false,  env: client_env)

              job_1template_hash = YAML.load(instance.read_job_template('job_1_with_many_properties', 'properties_displayer.yml'))
              expect(job_1template_hash['properties_list']['gargamel_color']).to eq(var_a)
              expect(job_1template_hash['properties_list']['smurfs_color']).to eq(var_b)

              job_2_template_hash = YAML.load(instance.read_job_template('job_2_with_many_properties', 'properties_displayer.yml'))
              expect(job_2_template_hash['properties_list']['gargamel_color']).to eq(var_c)
              expect(job_2_template_hash['properties_list']['smurfs_color']).to eq(var_d)
            end
          end

          context 'when addon properties reference the variables' do
            before do
              manifest_hash['addons'] = [
                {
                  'name' => 'addon1',
                  'jobs' => [
                    {
                      'name' => 'job_2_with_many_properties',
                      'release' => 'bosh-release',
                      'properties' => {
                        'gargamel' => { 'color' => '((var_c))' },
                        'smurfs' => { 'color' => '((/var_d))' },
                      },
                    },
                  ],
                },
              ]
            end

            it_behaves_like 'a deployment manifest that has addons section with variables'
          end

          context 'when addon JOB properties reference the variables' do
            before do
              manifest_hash['addons'] = [{
                'name' => 'addon1',
                'jobs' => [
                  {
                    'name' => 'job_2_with_many_properties',
                    'release' => 'bosh-release',
                    'properties' => { 'gargamel' => { 'color' => '((var_c))' }, 'smurfs' => { 'color' => '((/var_d))' } },
                  },
                  {
                    'name' => 'foobar',
                    'release' => 'bosh-release',
                    'properties' => {},
                  },
                ],
              }]
            end

            it_behaves_like 'a deployment manifest that has addons section with variables'
          end

          context 'when runtime config exists as well on the director' do
            let(:runtime_config) do
              {
                'releases' => [{ 'name' => 'bosh-release', 'version' => '0.1-dev' }],
                'addons' => [
                  {
                    'name' => 'foobar_addon',
                    'jobs' => [
                      {
                        'name' => 'foobar',
                        'release' => 'bosh-release',
                        'properties' => {
                          'test_property' => '((var_e))',
                        },
                      },
                    ],
                  },
                ],
                'variables' => [
                  {
                    'name' => 'var_e',
                    'type' => 'password',
                  },
                ],
              }
            end

            before do
              manifest_hash['addons'] = [{
                'name' => 'addon1',
                'jobs' => [
                  {
                    'name' => 'job_2_with_many_properties',
                    'release' => 'bosh-release',
                    'properties' => { 'gargamel' => { 'color' => '((var_c))' }, 'smurfs' => { 'color' => '((/var_d))' } },
                  },
                ],
              }]
            end

            it 'should deploy successfully with deployment addons and runtime-config addons' do
              upload_runtime_config(runtime_config_hash: runtime_config, include_credentials: false,  env: client_env)

              deploy_from_scratch(no_login: true, manifest_hash: manifest_hash, cloud_config_hash: cloud_config, include_credentials: false, env: client_env)

              var_a = config_server_helper.get_value(prepend_namespace('var_a'))
              var_b = config_server_helper.get_value('/var_b')
              var_c = config_server_helper.get_value(prepend_namespace('var_c'))
              var_d = config_server_helper.get_value('/var_d')
              var_e = config_server_helper.get_value(prepend_namespace('var_e'))

              instance = director.instance('our_instance_group', '0', deployment_name: 'simple', include_credentials: false,  env: client_env)

              job_1_template_hash = YAML.load(instance.read_job_template('job_1_with_many_properties', 'properties_displayer.yml'))
              expect(job_1_template_hash['properties_list']['gargamel_color']).to eq(var_a)
              expect(job_1_template_hash['properties_list']['smurfs_color']).to eq(var_b)

              job_2_template_hash = YAML.load(instance.read_job_template('job_2_with_many_properties', 'properties_displayer.yml'))
              expect(job_2_template_hash['properties_list']['gargamel_color']).to eq(var_c)
              expect(job_2_template_hash['properties_list']['smurfs_color']).to eq(var_d)

              foobar_job_template = instance.read_job_template('foobar', 'bin/foobar_ctl')
              expect(foobar_job_template).to include("test_property=#{var_e}")
            end
          end
        end
      end
    end
  end
end
