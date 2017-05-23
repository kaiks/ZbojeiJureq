# encoding: utf-8
require 'wunderground'
require './config.rb'

class WeatherUser < Sequel::Model(DB[:weather])
  unrestrict_primary_key
end

class WeatherPlugin
  include Cinch::Plugin

  self.prefix = '.'


  match /w register (.*)/,      method: :register, group: :weathergroup
  match /w (.*)/,               method: :weather, group: :weathergroup
  match /w/,                    method: :registered_weather, group: :weathergroup

  match /template(\s[^\s].*)/, method: :help




  def initialize(*args)
    @w_api = Wunderground.new(CONFIG['wunderground_api_key'])
    super
  end

  def weather(m, city)
    query_results = weather_query(city)
    if query_results['response']['results']
      m.reply parse_weather_results query_results['response']
    else
      m.reply parse_weather_simple query_results
    end
  end

  def register m, location
    user = WeatherUser.find(:nick => m.user.nick)
    user ||= WeatherUser.create(:nick => m.user.nick, :weather_string => location)
    user.weather_string = location
    user.save
    m.reply "Done."
  end

  def registered_weather(m)
    user_location = WeatherUser[m.user.nick]
    if user_location.nil?
      m.reply "No location registered for #{m.user.nick}"
      return
    end
    m.reply parse_weather_simple weather_query(user_location[:weather_string])
  end

  def weather_query(q)
    query = @w_api.conditions_for(q).to_s
    h = eval(query)
  end

  def parse_weather_simple h
    location = h["current_observation"]["display_location"]["full"].to_s
    conditions = h["current_observation"]["weather"].to_s
    temp = h["current_observation"]["temp_c"].to_s
    "#{h["current_observation"]["display_location"]["full"].to_s}: #{conditions} and #{temp}°C"
  end

  def result_to_string result_hash
    "#{result_hash['zmw']}: #{result_hash['city']}, #{result_hash['state']}, #{result_hash['country_name']}"
  end

  def parse_weather_results h
    'Multiple locations. Use ".w zmw:[code]".
'+  'Codes: ' + h['results'][0..3].map{|r| result_to_string(r) }.join('   ---   ')
  end



  def help(m)
    m.channel.send '.w [city] to get weather for a city'
  end
end