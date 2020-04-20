# encoding: utf-8
require './config.rb'
require 'json'
require 'http'

class OilPlugin
  include Cinch::Plugin

  self.prefix = '.'
  API_ENDPOINT_URL = "https://www.cmegroup.com/CmeWS/mvc/Quotes/Future/425/G".freeze
  OPTIONS = { quoteCodes: nil }.freeze

  match /oil\z/i,                 method: :oil

  def initialize(*args)
    super
  end

  def oil(m)
    m.reply oil_report(oil_data)
  end

  private

  def api_url
    query_params = OPTIONS.merge(_: Time.now.to_i*1000, quoteCodes: nil)
    encoded_params = URI.encode_www_form(query_params)
    API_ENDPOINT_URL + "?" + encoded_params
  end

  def oil_data
    response = HTTP.get(api_url).to_s
    JSON.parse(response)
  end

  def oil_report(oil_hash)
    recent_data = oil_hash["quotes"]&.first
    return "Failed to fetch oil data" unless recent_data

    delay = oil_hash["quoteDelay"]
    change = change_text(recent_data["change"], recent_data["open"])

    [
      "Crude oil price:", recent_data["last"],
      "(#{change})",
      "-",
      "daily low:", recent_data["low"],
      "-",
      "daily high:", recent_data["high"],
      "-",
      "(delayed by: #{delay})"
    ].join(" ")
  end

  def change_text(change, open)
    percentage_change = (100.0 * change.to_f / open.to_f).round(2)
    percentage_text = ""
    percentage_text << "+" if percentage_change.positive?
    percentage_text << percentage_change.to_s
    percentage_text << "%"

    Text.color(percentage_text, change_color(percentage_change))
  end

  def change_color(value)
    if value.positive?
      Text::GREEN
    elsif value.negative?
      Text::RED
    else
      Text::BLACK
    end
  end
end
