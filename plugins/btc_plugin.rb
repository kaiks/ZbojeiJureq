require 'open-uri'
require 'json'

class BtcPlugin
  include Cinch::Plugin

  self.prefix = '.'

  match /btc/,         method: :btc
  match /eth/,         method: :eth

  def initialize(*args)
    super
  end

  def btc(m)
    m.reply (1.0/(open('https://blockchain.info/tobtc?currency=USD&value=1').read).to_f).to_s + ' USD'
  end

  def eth(m)
    api_response = open('https://min-api.cryptocompare.com/data/price?fsym=ETH&tsyms=USD,PLN').read
    m.reply  JSON.parse(api_response).map{|k,v| "#{k}: #{v}"}.join(', ')
  end

end