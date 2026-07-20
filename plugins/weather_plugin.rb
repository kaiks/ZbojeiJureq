# encoding: utf-8
require 'json'
require 'net/http'
require 'uri'

require './config.rb'

class WeatherUser < Sequel::Model(DB[:weather])
  unrestrict_primary_key
end

class WeatherPlugin
  include Cinch::Plugin

  class ApiError < StandardError; end

  self.prefix = '.'
  OPTIONS = { units: "metric", APPID: CONFIG['openweathermap_api_key'] }.freeze
  API_ENDPOINT_URL = "https://api.openweathermap.org/data/2.5/weather".freeze

  match /w register (.*)/i,     method: :register, group: :weathergroup
  match /w help/i,              method: :help, group: :weathergroup
  match /w (.+)/i,              method: :weather, group: :weathergroup
  match /w\z/i,                 method: :registered_weather, group: :weathergroup

  def initialize(*args)
    super
  end

  def weather(m, city)
    reply_with_weather(m, city)
  end

  def register(m, location)
    user = WeatherUser.find(nick: m.user.nick)
    user ||= WeatherUser.create(nick: m.user.nick, weather_string: location)
    user.weather_string = location
    user.save
    m.reply 'Done.'
  end

  def registered_weather(m)
    user_location = WeatherUser[m.user.nick]&.weather_string
    if user_location.nil?
      m.reply "No location registered for #{m.user.nick}"
      return
    end
    reply_with_weather(m, user_location)
  end

  def help(m)
    m.channel.send '.w [city] to get weather for a city. .w register [city] to save your city'
  end

  private

  def weather_for(location)
    query_hash = weather_query(location)
    parse_weather_results(query_hash)
  end

  def reply_with_weather(message, location)
    message.reply weather_for(location)
  rescue ApiError => e
    message.reply "Weather lookup failed: #{e.message}"
  end

  def api_url_for(location)
    query_params = OPTIONS.merge(q: location)
    encoded_params = URI.encode_www_form(query_params)
    API_ENDPOINT_URL + "?" + encoded_params
  end

  def weather_query(location)
    uri = URI(api_url_for(location))
    response = Net::HTTP.start(
      uri.host,
      uri.port,
      use_ssl: uri.scheme == 'https',
      open_timeout: 5,
      read_timeout: 5
    ) { |http| http.get(uri.request_uri) }

    unless response.is_a?(Net::HTTPSuccess)
      raise ApiError, "service returned HTTP #{response.code}"
    end

    JSON.parse(response.body)
  rescue JSON::ParserError
    raise ApiError, 'service returned an invalid response'
  rescue SystemCallError, Timeout::Error, SocketError
    raise ApiError, 'service is unavailable'
  end

  def parse_weather_results(weather_hash)
    city             = weather_hash["name"]
    country          = weather_hash.dig("sys", "country")
    text_description = weather_hash["weather"]&.first["description"].to_s
    temperature      = weather_hash.dig("main", "temp")
    wind             = weather_hash.dig("wind", "speed")
    
    output_string = "#{city}, #{country}: "
    output_string << text_description
    output_string << ", #{temperature}°C" unless temperature.nil?
    output_string << " and #{wind}m/s wind speed" unless wind.nil?

    output_string
  end
end
