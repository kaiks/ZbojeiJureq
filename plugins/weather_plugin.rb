# encoding: utf-8
require './config.rb'

class WeatherUser < Sequel::Model(DB[:weather])
  unrestrict_primary_key
end

class WeatherPlugin
  include Cinch::Plugin

  self.prefix = '.'
  OPTIONS = { units: "metric", APPID: CONFIG['openweathermap_api_key'] }.freeze
  API_ENDPOINT_URL = "http://api.openweathermap.org/data/2.5/weather".freeze

  match /w register (.*)/i,     method: :register, group: :weathergroup
  match /w help/i,              method: :help, group: :weathergroup
  match /w (.+)/i,              method: :weather, group: :weathergroup
  match /w\z/i,                 method: :registered_weather, group: :weathergroup

  def initialize(*args)
    super
  end

  def weather(m, city)
    weather_string = weather_for(city)
    return unless weather_string.length > 0
    m.reply weather_string
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
    m.reply weather_for(user_location)
  end

  def help(m)
    m.channel.send '.w [city] to get weather for a city. .w register [city] to save your city'
  end

  private

  def weather_for(location)
    query_hash = weather_query(location)
    parse_weather_results(query_hash)
  end

  def api_url_for(location)
    query_params = OPTIONS.merge(q: location)
    encoded_params = URI.encode_www_form(query_params)
    API_ENDPOINT_URL + "?" + encoded_params
  end

  def weather_query(location)
    raw_data = open(api_url_for(location)).read
    JSON.parse(raw_data)
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
