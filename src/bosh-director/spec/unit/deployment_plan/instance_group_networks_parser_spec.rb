require 'spec_helper'

module Bosh::Director::DeploymentPlan
  describe InstanceGroupNetworksParser do
    include Bosh::Director::IpUtil

    let(:instance_group_networks_parser) { InstanceGroupNetworksParser.new(Network::REQUIRED_DEFAULTS, Network::OPTIONAL_DEFAULTS) }
    let(:instance_group_spec) do
      instance_group = Bosh::Spec::Deployments.simple_manifest_with_instance_groups['instance_groups'].first
      instance_group_network = instance_group['networks'].first
      instance_group_network['static_ips'] = ['192.168.1.1', '192.168.1.2']
      instance_group
    end
    let(:manifest_networks) { [ManualNetwork.new('a', [], logger)] }

    context 'when instance group references a network not mentioned in the networks spec' do
      let(:manifest_networks) { [ManualNetwork.new('my-network', [], logger)] }

      it 'raises JobUnknownNetwork' do
        expect do
          instance_group_networks_parser.parse(instance_group_spec, 'instance-group-name', manifest_networks)
        end.to raise_error BD::JobUnknownNetwork, "Instance group 'instance-group-name' references an unknown network 'a'"
      end
    end

    context 'when instance group spec is missing network information' do
      let(:instance_group_spec) do
        instance_group = Bosh::Spec::Deployments.simple_manifest_with_instance_groups['instance_groups'].first
        instance_group['networks'] = []
        instance_group
      end

      it 'raises JobMissingNetwork' do
        expect do
          instance_group_networks_parser.parse(instance_group_spec, 'instance-group-name', manifest_networks)
        end.to raise_error BD::JobMissingNetwork, "Instance group 'instance-group-name' must specify at least one network"
      end
    end

    context 'when instance group network spec references dynamic network with static IPs' do
      let(:dynamic_network) { BD::DeploymentPlan::DynamicNetwork.new('a', [], logger) }
      let(:instance_group_spec) do
        instance_group = Bosh::Spec::Deployments.simple_manifest_with_instance_groups['instance_groups'].first
        instance_group['networks'] = [{
          'name' => 'a',
          'static_ips' => ['10.0.0.2'],
        }]
        instance_group
      end

      it 'raises JobStaticIPNotSupportedOnDynamicNetwork' do
        expect do
          instance_group_networks_parser.parse(instance_group_spec, 'instance-group-name', [dynamic_network])
        end.to raise_error BD::JobStaticIPNotSupportedOnDynamicNetwork, "Instance group 'instance-group-name' using dynamic network 'a' cannot specify static IP(s)"
      end
    end

    context 'when instance group uses the same static IP more than once' do
      let(:instance_group_spec) do
        instance_group = Bosh::Spec::Deployments.simple_manifest_with_instance_groups['instance_groups'].first
        instance_group_network = instance_group['networks'].first
        instance_group_network['static_ips'] = ['192.168.1.2', '192.168.1.2']
        instance_group
      end

      it 'raises an error' do
        expect do
          instance_group_networks_parser.parse(instance_group_spec, 'instance-group-name', manifest_networks)
        end.to raise_error BD::JobInvalidStaticIPs, "Instance group 'instance-group-name' specifies static IP '192.168.1.2' more than once"
      end
    end

    context 'when called with a valid instance group spec' do
      it 'adds static ips to instance group networks in order as they are in manifest' do
        networks = instance_group_networks_parser.parse(instance_group_spec, 'instance-group-name', manifest_networks)

        expect(networks.count).to eq(1)
        expect(networks.first).to be_an_instance_group_network(
          JobNetwork.make(
            name: 'a',
            static_ips: ['192.168.1.1', '192.168.1.2'],
            default_for: %w[dns gateway],
            deployment_network: manifest_networks.first,
          ),
        )
        expect(networks.first.static_ips).to eq([ip_to_i('192.168.1.1'), ip_to_i('192.168.1.2')])
      end
    end

    RSpec::Matchers.define :be_an_instance_group_network do |expected|
      match do |actual|
        actual.name == expected.name &&
          actual.static_ips == expected.static_ips.map { |ip_to_i| NetAddr::CIDR.create(ip_to_i) } &&
          actual.deployment_network == expected.deployment_network
      end
    end
  end
end
