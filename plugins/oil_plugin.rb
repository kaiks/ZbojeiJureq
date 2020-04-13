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
    delay = oil_hash["quoteDelay"]

    recent_data = oil_hash["quotes"]&.first
    return "Failed to fetch oil data" unless recent_data

    [
      "Crude oil price:", recent_data["quotes"],
      "(#{recent_data["change"]})",
      "-",
      "daily low:", price_data["low"],
      "-",
      "daily high:", price_data["high"],
      "-",
      "(delayed by: #{delay})"
    ].join(" ")
  end
end
