require 'spec_helper'
require 'fileutils'

describe 'when a release job modifies a global property in the ERB script', type: :integration do
  with_reset_sandbox_before_each

  include Bosh::Spec::CreateReleaseOutputParsers

  let(:deployment_manifest) do
    minimal_manifest = Bosh::Common::DeepCopy.copy(Bosh::Spec::Deployments.manifest_with_release)

    minimal_manifest['properties'] = { 'some_namespace' => { 'test_property' => 'initial value' } }
    minimal_manifest['instance_groups'] = [
      {
        'name' => 'test_group',
        'instances' => 1,
        'jobs' => [
          { 'name' => 'job_that_modifies_properties', 'release' => 'bosh-release' },
        ],
        'networks' => [{ 'name' => 'a' }],
        'vm_type' => 'a',
        'stemcell' => 'default',
      },
    ]

    yaml_file('minimal', minimal_manifest)
  end

  let!(:release_file) { Tempfile.new('release.tgz') }
  after { release_file.delete }

  before do
    Dir.chdir(ClientSandbox.test_release_dir) do
      FileUtils.rm_rf('dev_releases')
      bosh_runner.run_in_current_dir("create-release --tarball=#{release_file.path}")
    end

    cloud_config = Bosh::Spec::Deployments.simple_cloud_config
    cloud_config_manifest = yaml_file('cloud_manifest', cloud_config)

    bosh_runner.run("upload-release #{release_file.path}")
    bosh_runner.run("update-cloud-config #{cloud_config_manifest.path}")
    bosh_runner.run("upload-stemcell #{spec_asset('valid_stemcell.tgz')}")
  end

  it 'does not modify the property for other templates' do
    deployment_name = Bosh::Spec::Deployments::DEFAULT_DEPLOYMENT_NAME
    bosh_runner.run("deploy -d #{deployment_name} #{deployment_manifest.path}")

    target_instance = director.instance('test_group', '0')

    ctl_script = target_instance.read_job_template('job_that_modifies_properties', 'bin/job_that_modifies_properties_ctl')

    expect(ctl_script).to include('test_property initially was initial value')

    other_script = target_instance.read_job_template('job_that_modifies_properties', 'bin/another_script')

    expect(other_script).to include('test_property initially was initial value')
  end
end
