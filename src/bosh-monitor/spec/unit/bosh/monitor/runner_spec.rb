require 'spec_helper'

describe Bosh::Monitor::Runner do
  let(:runner) { Bosh::Monitor::Runner.new(sample_config) }

  describe 'connect_to_mbus' do
    it 'should connect using SSL' do
      runner
      expected_nats_connect_options = {
        uri: Bhm.mbus.endpoint,
        autostart: false,
        max_reconnect_attempts: -1,
        tls: {
          ca_file: Bhm.mbus.server_ca_path,
          cert_chain_file: Bhm.mbus.client_certificate_path,
          private_key_file: Bhm.mbus.client_private_key_path,
        },
        ssl: true,
      }
      expect(NATS).to receive(:connect).with(expected_nats_connect_options)

      runner.connect_to_mbus
    end

    context 'when NATS errors' do
      let(:logger) { instance_double(Logger) }
      let(:custom_error) { 'Some error for nats://127.0.0.1:4222. Another error for nats://127.0.0.1:4222.' }

      before do
        allow(logger).to receive(:error)
        allow(Bhm).to receive(:logger).and_return(logger)

        allow(NATS).to receive(:connect)
        allow(NATS).to receive(:on_error) do |&clbk|
          clbk.call(custom_error)
        end
      end

      context 'when NATS calls error handler with a ConnectError' do
        let(:custom_error) { NATS::ConnectError.new('connection error') }

        before do
          allow(logger).to receive(:fatal)
          allow(logger).to receive(:info)
        end

        it 'shuts down the server' do
          expect(runner).to receive(:stop)
          runner.connect_to_mbus
        end
      end

      context 'when an error occurs while connecting' do
        before do
          allow(NATS).to receive(:connect).and_raise('a NATS error has occurred')
        end

        it 'throws the error' do
          expect do
            runner.connect_to_mbus
          end.to raise_error('a NATS error has occurred')
        end
      end
    end
  end
end
