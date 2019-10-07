require 'spec_helper'

include Bosh::Monitor::Plugins::HttpRequestHelper

describe Bosh::Monitor::Plugins::HttpRequestHelper do
  before do
    Bhm.logger = logger
  end

  describe '#send_http_put_request' do
    let(:http_request) { instance_double(EM::HttpRequest) }
    let(:http_response) { instance_double(EM::Completion) }

    it 'sends a put request' do
      expect(EM::HttpRequest).to receive(:new).with('some-uri').and_return(http_request)

      expect(http_request).to receive(:send).with(:put, 'some-request').and_return(http_response)
      expect(http_response).to receive(:callback)
      expect(http_response).to receive(:errback)
      expect(logger).not_to receive(:error)

      send_http_put_request('some-uri', 'some-request')
    end
  end

  describe '#send_http_post_request' do
    let(:http_request) { instance_double(EM::HttpRequest) }
    let(:http_response) { instance_double(EM::Completion) }

    it 'sends a post request' do
      expect(EM::HttpRequest).to receive(:new).with('some-uri').and_return(http_request)

      expect(http_request).to receive(:send).with(:post, 'some-request').and_return(http_response)
      expect(http_response).to receive(:callback)
      expect(http_response).to receive(:errback)
      expect(logger).not_to receive(:error)

      send_http_post_request('some-uri', 'some-request')
    end
  end

  describe '#send_http_get_request' do
    it 'sends a get request' do
      expect(logger).to receive(:debug).with('Sending GET request to some-uri')

      ssl_config = instance_double(HTTPClient::SSLConfig)

      httpclient = instance_double(HTTPClient)
      expect(HTTPClient).to receive(:new).and_return(httpclient)
      expect(httpclient).to receive(:ssl_config).and_return(ssl_config)
      expect(ssl_config).to receive(:verify_mode=).with(OpenSSL::SSL::VERIFY_NONE)
      expect(httpclient).to receive(:get).with('some-uri')
      send_http_get_request('some-uri')
    end
  end

  describe '#send_http_post_sync_request' do
    let(:request) do
      { body: 'some-request-body', proxy: nil }
    end

    it 'sends a sync post request' do
      ssl_config = instance_double(HTTPClient::SSLConfig)
      httpclient = instance_double(HTTPClient)

      expect(HTTPClient).to receive(:new).and_return(httpclient)
      expect(httpclient).to receive(:ssl_config).and_return(ssl_config)
      expect(ssl_config).to receive(:verify_mode=).with(OpenSSL::SSL::VERIFY_PEER)
      expect(httpclient).to receive(:post).with('some-uri', 'some-request-body')

      send_http_post_sync_request('some-uri', request)
    end
  end
end
