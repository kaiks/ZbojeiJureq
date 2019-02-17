require 'cgi'

class WolframPlugin
  include Cinch::Plugin

  self.prefix = '.'
  WA_ENDPOINT = 'http://api.wolframalpha.com/v2/result'.freeze
  API_KEY = CONFIG['wolframalpha_api_key']

  match /wa\z/,         method: :help
  match /wa ([^\s].*)/, method: :message

  def initialize(*args)
    super
  end

  def wa_query_url(query_text)
    escaped_query = CGI.escape(query_text)
    "#{WA_ENDPOINT}?appid=#{API_KEY}&i=#{escaped_query}"
  end

  def query_wa(query_text)
    query_url = wa_query_url(query_text)
    open(query_url).read
  end

  def message(m, query_text)
    m.safe_reply query_wa(query_text)
  end

  def help(m)
    m.channel.send '.wa [query] to query Wolfram|Alpha Short Answers API'
  end
end
