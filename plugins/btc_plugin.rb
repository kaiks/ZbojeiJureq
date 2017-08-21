require 'open-uri'
require 'json'

#TODO: extract api from user interface

class BtcPlugin
  CRYPTOCOMPARE_DOMAIN = 'https://min-api.cryptocompare.com'.freeze
  BCINFO_DOMAIN = 'https://blockchain.info'.freeze
  include Cinch::Plugin

  self.prefix = '.'

  match /btc/i,                         method: :btc
  match /eth/i,                         method: :eth
  match /bch/i,                         method: :bch
  match /crypto ([a-z0-9]+)/i,          method: :crypto
  match /cryptoupdate/i,                method: :update

  def initialize(*args)
    update_cryptocompare_coin_list
    super
  end

  def btc(m)
    api_response = open("#{BCINFO_DOMAIN}/tobtc?currency=USD&value=1").read
    m.reply (1.0/api_response.to_f).to_s + ' USD'
  end

  def get_coin_cryptocompare(coin, currencies = %w[USD PLN])
    curr_string = currencies.map(&:upcase).join(',')
    open(
      "#{CRYPTOCOMPARE_DOMAIN}/data/price?fsym=#{coin}&tsyms=#{curr_string}"
    ).read
  end

  def cryptocompare_parse(api_response)
    JSON.parse(api_response).map{|k,v| "#{k}: #{v}"}.join(', ')
  end

  def eth(m)
    api_response = get_coin_cryptocompare('ETH')
    m.reply cryptocompare_parse(api_response)
  end

  def bch(m)
    api_response = get_coin_cryptocompare('BCH')
    m.reply cryptocompare_parse(api_response)
  end

  def update_cryptocompare_coin_list
    api_response = open('https://www.cryptocompare.com/api/data/coinlist/').read
    @coin_list = JSON.parse(api_response)['Data'].keys
  end

  def crypto(m, coin)
    coin = coin.upcase
    if @coin_list.include?(coin)
      api_response = get_coin_cryptocompare(coin)
      m.reply cryptocompare_parse(api_response)
    else
      m.reply "Coin unknown (#{coin})."
    end
  end

  def update(m)
    return unless m.user.has_admin_access?
    update_cryptocompare_coin_list
    m.reply 'Cryptocurrency list updated.'
  end

end