require 'open-uri'
require 'json'
require 'time'

#TODO: extract api from user interface

class BtcPlugin
  CRYPTOCOMPARE_DOMAIN = 'https://min-api.cryptocompare.com'.freeze
  BCINFO_DOMAIN = 'https://blockchain.info'.freeze
  MSG_CHANNEL = '#kx'
  include Cinch::Plugin

  self.prefix = '.'

  match /btc/i,                         method: :btc
  match /eth/i,                         method: :eth
  match /bch/i,                         method: :bch
  match /crypto ([a-z0-9]+)/i,          method: :crypto
  match /cryptoupdate/i,                method: :update

  timer 600, method: :btc_price_check

  def initialize(*args)
    update_cryptocompare_coin_list
    super
  end

  def round_to_500(price)
    ((2.0*price).round(-3))/2.0
  end

  def btc_price_update?(current)
    current_rounded = round_to_500(current)
    (current_rounded > @btc_price_checkpoint && current >= (@btc_price_checkpoint + 500)) ||
      (current_rounded < @btc_price_checkpoint && current <= (@btc_price_checkpoint - 500))
  end

  def btc_price_check
    @btc_price_checkpoint ||= round_to_500(btc_price_in_usd)
    current_price = btc_price_in_usd
    current_rounded_price = round_to_500(current_price)
    if btc_price_update?(current_price)
      color = current_rounded_price > @btc_price_checkpoint ? Text::GREEN : Text::RED
      update_msg = "BTC price update: #{Text.bold(Text.color(current_price, color))}, was #{@btc_price_checkpoint}"

      Channel(MSG_CHANNEL).send(update_msg)
      @btc_price_checkpoint = round_to_500(current_price)
    end
  end

  def btc_price_in_usd
    api_response = open("#{BCINFO_DOMAIN}/tobtc?currency=USD&value=1").read
    1.0/api_response.to_f
  end

  def btc(m)
    api_response = open("#{BCINFO_DOMAIN}/tobtc?currency=USD&value=1").read
    m.reply "#{btc_price_in_usd} USD"
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