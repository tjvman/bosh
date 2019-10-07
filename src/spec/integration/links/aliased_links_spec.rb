require 'spec_helper'

describe 'aliased links', type: :integration do
  with_reset_sandbox_before_each

  def upload_links_release
    FileUtils.cp_r(LINKS_RELEASE_TEMPLATE, ClientSandbox.links_release_dir, preserve: true)
    bosh_runner.run_in_dir('create-release --force', ClientSandbox.links_release_dir)
    bosh_runner.run_in_dir('upload-release', ClientSandbox.links_release_dir)
  end

  let(:cloud_config) do
    cloud_config_hash = Bosh::Spec::NewDeployments.simple_cloud_config
    cloud_config_hash['azs'] = [{ 'name' => 'z1' }]
    cloud_config_hash['networks'].first['subnets'].first['static'] = [
      '192.168.1.10',
      '192.168.1.11',
      '192.168.1.12',
      '192.168.1.13',
    ]
    cloud_config_hash['networks'].first['subnets'].first['az'] = 'z1'
    cloud_config_hash['compilation']['az'] = 'z1'
    cloud_config_hash['networks'] << {
      'name' => 'dynamic-network',
      'type' => 'dynamic',
      'subnets' => [{ 'az' => 'z1' }],
    }

    cloud_config_hash
  end

  let(:api_instance_group_spec) do
    spec = Bosh::Spec::NewDeployments.simple_instance_group(
      name: 'my_api',
      jobs: [{ 'name' => 'api_server', 'release' => 'bosh-release', 'consumes' => links }],
      instances: 1,
    )
    spec['azs'] = ['z1']
    spec
  end

  let(:aliased_instance_group_spec) do
    spec = Bosh::Spec::NewDeployments.simple_instance_group(
      name: 'aliased_postgres',
      jobs: [
        'name' => 'backup_database',
        'release' => 'bosh-release',
        'provides' => { 'backup_db' => { 'as' => 'link_alias' } },
      ],
      instances: 1,
    )
    spec['azs'] = ['z1']
    spec
  end

  before do
    upload_links_release
    upload_stemcell

    upload_cloud_config(cloud_config_hash: cloud_config)
  end

  context 'properties with aliased links' do
    let(:db3_instance_group) do
      spec = Bosh::Spec::NewDeployments.simple_instance_group(
        name: 'db3',
        jobs: [
          {
            'name' => 'http_server_with_provides',
            'release' => 'bosh-release',
            'provides' => {
              'http_endpoint' => { 'as' => 'http_endpoint2', 'shared' => true },
            },
          },
          {
            'name' => 'kv_http_server',
            'release' => 'bosh-release',
          },
        ],
        instances: 1,
      )
      spec['azs'] = ['z1']
      spec['properties'] = {
        'listen_port' => 8082,
        'kv_http_server' => { 'listen_port' => 8081 },
        'name_space' => { 'prop_a' => 'job_value', 'fibonacci' => 1 },
      }
      spec
    end

    let(:other2_instance_group) do
      spec = Bosh::Spec::NewDeployments.simple_instance_group(
        name: 'other2',
        jobs: [
          {
            'name' => 'http_proxy_with_requires',
            'release' => 'bosh-release',
            'properties' => { 'http_proxy_with_requires.listen_port' => 21 },
            'consumes' => {
              'proxied_http_endpoint' => { 'from' => 'http_endpoint2', 'shared' => true },
              'logs_http_endpoint' => 'nil',
            },
          },
          {
            'name' => 'http_server_with_provides',
            'release' => 'bosh-release',
            'properties' => { 'listen_port' => 8446 },
          },
        ],
        instances: 1,
      )
      spec['azs'] = ['z1']
      spec
    end

    let(:new_instance_group) do
      job_spec = Bosh::Spec::NewDeployments.simple_instance_group(
        name: 'new_job',
        jobs: [
          {
            'name' => 'http_proxy_with_requires',
            'release' => 'bosh-release',
            'consumes' => {
              'proxied_http_endpoint' => { 'from' => 'new_provides', 'shared' => true },
              'logs_http_endpoint' => 'nil',
            },
          },
          {
            'name' => 'http_server_with_provides',
            'release' => 'bosh-release',
            'provides' => {
              'http_endpoint' => { 'as' => 'new_provides' },
            },
          },
        ],
        instances: 1,
      )
      job_spec['azs'] = ['z1']
      job_spec
    end

    let(:manifest) do
      manifest = Bosh::Spec::NetworkingManifest.deployment_manifest
      manifest['instance_groups'] = [db3_instance_group, other2_instance_group, new_instance_group]
      manifest['properties'] = { 'listen_port' => 9999 }
      manifest
    end

    it 'is able to pick the right value for the property from global, job, template and default values' do
      deploy_simple_manifest(manifest_hash: manifest)
      instances = director.instances
      link_instance = director.find_instance(instances, 'other2', '0')
      template = YAML.safe_load(link_instance.read_job_template('http_proxy_with_requires', 'config/config.yml'))
      expect(template['links']).to contain_exactly(
        ['address', /^192.168.1.\d+$/],
        ['properties', { 'listen_port' => 8082, 'name_space' => { 'prop_a' => 'job_value' }, 'fibonacci' => 1 }],
      )

      link_instance = director.find_instance(instances, 'new_job', '0')
      template = YAML.safe_load(link_instance.read_job_template('http_proxy_with_requires', 'config/config.yml'))
      expect(template['links']).to contain_exactly(
        ['address', /^192.168.1.\d+$/],
        ['properties', { 'listen_port' => 9999, 'name_space' => { 'prop_a' => 'default' } }],
      )
    end
  end

  context 'when provide link is aliased using "as", and the consume link references the new alias' do
    let(:manifest) do
      manifest = Bosh::Spec::NetworkingManifest.deployment_manifest
      manifest['instance_groups'] = [api_instance_group_spec, aliased_instance_group_spec]
      manifest
    end

    let(:links) do
      {
        'db' => { 'from' => 'link_alias' },
        'backup_db' => { 'from' => 'link_alias' },
      }
    end

    it 'renders link data in job template' do
      deploy_simple_manifest(manifest_hash: manifest)

      link_instance = director.instance('my_api', '0')
      aliased_postgres_instance = director.instance('aliased_postgres', '0')

      template = YAML.safe_load(link_instance.read_job_template('api_server', 'config.yml'))

      expect(template['databases']['main'].size).to eq(1)
      expect(template['databases']['main']).to contain_exactly(
        'id' => aliased_postgres_instance.id.to_s,
        'name' => 'aliased_postgres',
        'index' => 0,
        'address' => /^192.168.1.\d+$/,
      )
    end

    context 'co-located jobs consume two links with the same name, provided by a different job on the same instance group' do
      let(:manifest) do
        manifest = Bosh::Spec::NetworkingManifest.deployment_manifest
        manifest['instance_groups'] = [provider_instance_group, consumer_instance_group]
        manifest
      end

      let(:provider_instance_group) do
        spec = Bosh::Spec::NewDeployments.simple_instance_group(
          name: 'provider_instance_group',
          jobs: [
            {
              'name' => 'http_server_with_provides',
              'release' => 'bosh-release',
              'properties' => {
                'listen_port' => 11_111,
                'name_space' => {
                  'prop_a' => 'http_provider_some_prop_a',
                },
              },
              'provides' => {
                'http_endpoint' => {
                  'as' => 'link_http_alias',
                },
              },
            },
            {
              'name' => 'tcp_server_with_provides',
              'release' => 'bosh-release',
              'properties' => {
                'listen_port' => 77_777,
                'name_space' => {
                  'prop_a' => 'tcp_provider_some_prop_a',
                },
              },
              'provides' => { 'http_endpoint' => { 'as' => 'link_tcp_alias' } },
            },
          ],
          instances: 1,
        )
        spec['azs'] = ['z1']
        spec
      end

      let(:consumer_instance_group) do
        spec = Bosh::Spec::NewDeployments.simple_instance_group(
          name: 'consumer_instance_group',
          jobs: [
            {
              'name' => 'http_proxy_with_requires',
              'release' => 'bosh-release',
              'consumes' => { 'proxied_http_endpoint' => { 'from' => 'link_http_alias' } },
            },
            {
              'name' => 'tcp_proxy_with_requires',
              'release' => 'bosh-release',
              'consumes' => { 'proxied_http_endpoint' => { 'from' => 'link_tcp_alias' } },
            },
          ],
          instances: 1,
        )
        spec['azs'] = ['z1']
        spec
      end

      it 'each job should get the correct link' do
        deploy_simple_manifest(manifest_hash: manifest)

        consumer_instance_group = director.instance('consumer_instance_group', '0')

        http_template = YAML.safe_load(consumer_instance_group.read_job_template('http_proxy_with_requires', 'config/config.yml'))
        tcp_template = YAML.safe_load(consumer_instance_group.read_job_template('tcp_proxy_with_requires', 'config/config.yml'))

        expect(http_template['links']['properties']['listen_port']).to eq(11_111)
        expect(http_template['links']['properties']['name_space']['prop_a']).to eq('http_provider_some_prop_a')

        expect(tcp_template['links']['properties']['listen_port']).to eq(77_777)
        expect(tcp_template['links']['properties']['name_space']['prop_a']).to eq('tcp_provider_some_prop_a')
      end
    end

    context 'co-located jobs consume two links with the same name, provided by the same job on different instance groups' do
      let(:manifest) do
        manifest = Bosh::Spec::NetworkingManifest.deployment_manifest
        manifest['instance_groups'] = [provider1_http, provider2_http, consumer_instance_group]
        manifest
      end

      let(:provider1_http) do
        spec = Bosh::Spec::NewDeployments.simple_instance_group(
          name: 'provider1_http_instance_group',
          jobs: [{
            'name' => 'http_server_with_provides',
            'release' => 'bosh-release',
            'properties' => {
              'listen_port' => 11_111,
              'name_space' => {
                'prop_a' => '1_some_prop_a',
              },
            },
            'provides' => { 'http_endpoint' => { 'as' => 'link_http_1' } },
          }],
          instances: 1,
        )
        spec['azs'] = ['z1']
        spec
      end

      let(:provider2_http) do
        spec = Bosh::Spec::NewDeployments.simple_instance_group(
          name: 'provider2_http_instance_group',
          jobs: [{
            'name' => 'http_server_with_provides',
            'release' => 'bosh-release',
            'properties' => {
              'listen_port' => 1234,
              'name_space' => {
                'prop_a' => '2_some_prop_a',
              },
            },
            'provides' => { 'http_endpoint' => { 'as' => 'link_http_2' } },
          }],
          instances: 1,
        )
        spec['azs'] = ['z1']
        spec
      end

      let(:consumer_instance_group) do
        spec = Bosh::Spec::NewDeployments.simple_instance_group(
          name: 'consumer_instance_group',
          jobs: [
            {
              'name' => 'http_proxy_with_requires',
              'release' => 'bosh-release',
              'consumes' => { 'proxied_http_endpoint' => { 'from' => 'link_http_1' } },
            },
            {
              'name' => 'tcp_proxy_with_requires',
              'release' => 'bosh-release',
              'consumes' => { 'proxied_http_endpoint' => { 'from' => 'link_http_2' } },
            },
          ],
          instances: 1,
        )
        spec['azs'] = ['z1']
        spec
      end

      it 'each job should get the correct link' do
        deploy_simple_manifest(manifest_hash: manifest)

        consumer_instance_group = director.instance('consumer_instance_group', '0')

        http_template = YAML.safe_load(consumer_instance_group.read_job_template('http_proxy_with_requires', 'config/config.yml'))
        tcp_template = YAML.safe_load(consumer_instance_group.read_job_template('tcp_proxy_with_requires', 'config/config.yml'))

        expect(http_template['links']['properties']['listen_port']).to eq(11_111)
        expect(http_template['links']['properties']['name_space']['prop_a']).to eq('1_some_prop_a')

        expect(tcp_template['links']['properties']['listen_port']).to eq(1234)
        expect(tcp_template['links']['properties']['name_space']['prop_a']).to eq('2_some_prop_a')
      end
    end

    context 'consumes two links of the same type, provided by the same job on different instance groups' do
      let(:manifest) do
        manifest = Bosh::Spec::NetworkingManifest.deployment_manifest
        manifest['instance_groups'] = [provider_1_db, provider_2_db, consumer_instance_group]
        manifest
      end

      let(:provider_1_db) do
        spec = Bosh::Spec::NewDeployments.simple_instance_group(
          name: 'provider_1_db',
          jobs: [{
            'name' => 'backup_database',
            'release' => 'bosh-release',
            'properties' => {
              'foo' => 'wow',
            },
            'provides' => { 'backup_db' => { 'as' => 'db_1' } },
          }],
          instances: 1,
        )
        spec['azs'] = ['z1']
        spec
      end

      let(:provider_2_db) do
        spec = Bosh::Spec::NewDeployments.simple_instance_group(
          name: 'provider_2_db',
          jobs: [{
            'name' => 'backup_database',
            'release' => 'bosh-release',
            'properties' => {
              'foo' => 'omg_no_keyboard',
            },
            'provides' => { 'backup_db' => { 'as' => 'db_2' } },
          }],
          instances: 1,
        )
        spec['azs'] = ['z1']
        spec
      end

      let(:consumer_instance_group) do
        spec = Bosh::Spec::NewDeployments.simple_instance_group(
          name: 'consumer_instance_group',
          jobs: [
            {
              'name' => 'api_server',
              'release' => 'bosh-release',
              'consumes' => { 'db' => { 'from' => 'db_1' }, 'backup_db' => { 'from' => 'db_2' } },
            },
          ],
          instances: 1,
        )
        spec['azs'] = ['z1']
        spec
      end

      it 'each job should get the correct link' do
        deploy_simple_manifest(manifest_hash: manifest)

        consumer_instance_group = director.instance('consumer_instance_group', '0')

        api_template = YAML.safe_load(consumer_instance_group.read_job_template('api_server', 'config.yml'))

        expect(api_template['databases']['main_properties']).to eq('wow')
        expect(api_template['databases']['backup_properties']).to eq('omg_no_keyboard')
      end
    end
  end

  context 'when provide link is aliased using "as", and the consume link references the old name' do
    let(:manifest) do
      manifest = Bosh::Spec::NetworkingManifest.deployment_manifest
      manifest['instance_groups'] = [api_instance_group_spec, aliased_instance_group_spec]
      manifest
    end

    let(:links) do
      {
        'db' => { 'from' => 'backup_db' },
        'backup_db' => { 'from' => 'backup_db' },
      }
    end

    it 'throws an error before deploying vms' do
      _, exit_code = deploy_simple_manifest(manifest_hash: manifest, failure_expected: true, return_exit_code: true)
      expect(exit_code).not_to eq(0)
      expect(director.instances).to be_empty
    end
  end
end
