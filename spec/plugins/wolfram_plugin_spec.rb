require 'spec_helper'
require 'cinch'
require_relative '../../config'
require_relative '../../plugins/wolfram_plugin'

RSpec.describe WolframPlugin do
  let(:plugin) { described_class.allocate }

  describe '#message' do
    it 'fetches and replies with a Wolfram|Alpha result over HTTPS' do
      request = stub_request(:get, %r{\Ahttps://api\.wolframalpha\.com/v2/result\?})
        .with do |web_request|
          params = URI.decode_www_form(web_request.uri.query).to_h
          params['i'] == '2 + 2' && !params['appid'].to_s.empty?
        end
        .to_return(status: 200, body: '4')
      message = instance_double('message')

      expect(message).to receive(:safe_reply).with('4')

      plugin.message(message, '2 + 2')

      expect(request).to have_been_requested.once
    end

    it 'replies with a useful error when Wolfram|Alpha rejects the request' do
      stub_request(:get, %r{\Ahttps://api\.wolframalpha\.com/v2/result\?})
        .to_return(status: 403, body: 'Invalid appid')
      message = instance_double('message')

      expect(message).to receive(:safe_reply).with('Wolfram|Alpha query failed: service returned HTTP 403')

      plugin.message(message, '2 + 2')
    end
  end
end
