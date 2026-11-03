require 'net/http'
require 'uri'

class WolframPlugin
  include Cinch::Plugin

  self.prefix = '.'
  WA_ENDPOINT = 'https://api.wolframalpha.com/v2/result'.freeze
  API_KEY = CONFIG['wolframalpha_api_key']

  class ApiError < StandardError; end

  match /wa\z/,         method: :help
  match /wa ([^\s].*)/, method: :message

  def initialize(*args)
    super
  end

  def wa_query_url(query_text)
    query_params = URI.encode_www_form(appid: API_KEY, i: query_text)
    "#{WA_ENDPOINT}?#{query_params}"
  end

  def query_wa(query_text)
    uri = URI(wa_query_url(query_text))
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

    response.body
  rescue SystemCallError, Timeout::Error, SocketError
    raise ApiError, 'service is unavailable'
  end

  def message(m, query_text)
    m.safe_reply query_wa(query_text)
  rescue ApiError => e
    m.safe_reply "Wolfram|Alpha query failed: #{e.message}"
  end

  def help(m)
    m.channel.send '.wa [query] to query Wolfram|Alpha Short Answers API'
  end
end
