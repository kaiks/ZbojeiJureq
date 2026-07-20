require 'spec_helper'
require 'cinch'
require 'sequel'

DB = Sequel.sqlite unless defined?(DB)
unless DB.table_exists?(:weather)
  DB.create_table(:weather) do
    String :nick, primary_key: true
    String :weather_string
  end
end

require_relative '../../plugins/weather_plugin'

RSpec.describe WeatherPlugin do
  let(:plugin) { described_class.allocate }

  describe '#weather' do
    it 'fetches and replies with weather from OpenWeatherMap over HTTPS' do
      request = stub_request(:get, %r{\Ahttps://api\.openweathermap\.org/data/2\.5/weather\?})
        .with do |web_request|
          params = URI.decode_www_form(web_request.uri.query).to_h
          params['q'] == 'Berlin' && params['units'] == 'metric' && !params['APPID'].to_s.empty?
        end
        .to_return(
          status: 200,
          body: JSON.generate(
            'name' => 'Berlin',
            'sys' => { 'country' => 'DE' },
            'weather' => [{ 'description' => 'clear sky' }],
            'main' => { 'temp' => 21.5 },
            'wind' => { 'speed' => 3.2 }
          )
        )
      message = instance_double('message')

      expect(message).to receive(:reply).with('Berlin, DE: clear sky, 21.5°C and 3.2m/s wind speed')

      plugin.weather(message, 'Berlin')

      expect(request).to have_been_requested.once
    end

    it 'replies with a useful error when the weather service rejects the request' do
      stub_request(:get, %r{\Ahttps://api\.openweathermap\.org/data/2\.5/weather\?})
        .to_return(status: 401, body: '{"message":"Invalid API key"}')
      message = instance_double('message')

      expect(message).to receive(:reply).with('Weather lookup failed: service returned HTTP 401')

      plugin.weather(message, 'Berlin')
    end
  end
end
