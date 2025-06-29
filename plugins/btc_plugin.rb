require 'uri'
require 'json'
require 'time'
require 'net/http'

# HTTP Client for cryptocurrency APIs
class CryptoApiClient
  CRYPTOCOMPARE_DOMAIN = 'https://min-api.cryptocompare.com'.freeze
  BCINFO_DOMAIN = 'https://blockchain.info'.freeze
  DEFAULT_TIMEOUT = 10

  class ApiError < StandardError; end

  def initialize(timeout: DEFAULT_TIMEOUT)
    @timeout = timeout
    @cache = {}
    @cache_ttl = 60 # 1 minute cache
  end

  def btc_price_in_usd
    with_cache('btc_usd') do
      response = fetch_json("#{BCINFO_DOMAIN}/tobtc?currency=USD&value=1")
      1.0 / response.to_f
    end
  end

  def get_coin_prices(coin, currencies = %w[USD PLN])
    cache_key = "#{coin}_#{currencies.join('_')}"
    with_cache(cache_key) do
      curr_string = currencies.map(&:upcase).join(',')
      fetch_json("#{CRYPTOCOMPARE_DOMAIN}/data/price?fsym=#{coin}&tsyms=#{curr_string}")
    end
  end

  def coin_list
    with_cache('coin_list', ttl: 3600) do # 1 hour cache for coin list
      response = fetch_json('https://www.cryptocompare.com/api/data/coinlist/')
      response['Data'].keys
    end
  end

  private

  def with_cache(key, ttl: @cache_ttl)
    if @cache[key] && @cache[key][:expires_at] > Time.now
      return @cache[key][:value]
    end

    value = yield
    @cache[key] = { value: value, expires_at: Time.now + ttl }
    value
  end

  def fetch_json(url)
    uri = URI(url)
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https', 
                               open_timeout: @timeout, read_timeout: @timeout) do |http|
      http.get(uri.request_uri)
    end

    raise ApiError, "HTTP #{response.code}: #{response.message}" unless response.is_a?(Net::HTTPSuccess)
    
    JSON.parse(response.body)
  rescue Net::OpenTimeout, Net::ReadTimeout => e
    raise ApiError, "Request timeout: #{e.message}"
  rescue JSON::ParserError => e
    raise ApiError, "Invalid JSON response: #{e.message}"
  rescue => e
    raise ApiError, "Request failed: #{e.message}"
  end
end

# Price monitoring and formatting logic
class PriceMonitor
  attr_reader :checkpoint

  def initialize(rounding_factor: 500)
    @rounding_factor = rounding_factor
    @checkpoint = nil
  end

  def round_to_increment(price)
    factor = @rounding_factor.to_f
    ((price / factor).round * factor).to_f
  end

  def significant_change?(current_price)
    return false unless @checkpoint
    
    current_rounded = round_to_increment(current_price)
    (current_rounded > @checkpoint && current_price >= (@checkpoint + @rounding_factor)) ||
      (current_rounded < @checkpoint && current_price <= (@checkpoint - @rounding_factor))
  end

  def update_checkpoint(price)
    @checkpoint = round_to_increment(price)
  end

  def format_price_update(current_price, previous_checkpoint)
    current_rounded = round_to_increment(current_price)
    color = current_rounded > previous_checkpoint ? Text::GREEN : Text::RED
    "BTC price update: #{Text.color(Text.bold(current_price), color)}, was #{previous_checkpoint}"
  end
end

class BtcPlugin
  include Cinch::Plugin

  self.prefix = '.'

  match /btc/i,                         method: :btc
  match /eth/i,                         method: :eth
  match /bch/i,                         method: :bch
  match /crypto ([a-z0-9]+)/i,          method: :crypto
  match /cryptoupdate/i,                method: :update

  timer 600, method: :btc_price_check

  def initialize(*args)
    super
    @api_client = CryptoApiClient.new
    @price_monitor = PriceMonitor.new
    @msg_channel = config[:btc_channel] || '#kx'
    
    # Initialize coin list in background
    Thread.new { safe_update_coin_list }
  end

  def btc(m)
    price = @api_client.btc_price_in_usd
    m.reply "#{price} USD"
  rescue CryptoApiClient::ApiError => e
    m.reply "Error fetching BTC price: #{e.message}"
  end

  def eth(m)
    handle_crypto_command(m, 'ETH')
  end

  def bch(m)
    handle_crypto_command(m, 'BCH')
  end

  def crypto(m, coin)
    coin = coin.upcase
    unless coin_valid?(coin)
      m.reply "Coin unknown (#{coin})."
      return
    end
    
    handle_crypto_command(m, coin)
  end

  def update(m)
    return unless m.user.has_admin_access?
    
    if safe_update_coin_list
      m.reply 'Cryptocurrency list updated.'
    else
      m.reply 'Failed to update cryptocurrency list.'
    end
  end

  def btc_price_check
    current_price = @api_client.btc_price_in_usd
    
    # Initialize checkpoint on first run
    unless @price_monitor.checkpoint
      @price_monitor.update_checkpoint(current_price)
      return
    end
    
    if @price_monitor.significant_change?(current_price)
      previous = @price_monitor.checkpoint
      message = @price_monitor.format_price_update(current_price, previous)
      Channel(@msg_channel).send(message)
      @price_monitor.update_checkpoint(current_price)
    end
  rescue CryptoApiClient::ApiError => e
    bot.loggers.error "BTC price check failed: #{e.message}"
  end

  private

  def handle_crypto_command(m, coin)
    prices = @api_client.get_coin_prices(coin)
    formatted = format_prices(prices)
    m.reply formatted
  rescue CryptoApiClient::ApiError => e
    m.reply "Error fetching #{coin} price: #{e.message}"
  end

  def format_prices(prices_hash)
    prices_hash.map { |currency, price| "#{currency}: #{price}" }.join(', ')
  end

  def coin_valid?(coin)
    @coin_list ||= []
    @coin_list.include?(coin)
  end

  def safe_update_coin_list
    @coin_list = @api_client.coin_list
    true
  rescue CryptoApiClient::ApiError => e
    bot.loggers.error "Failed to update coin list: #{e.message}" if defined?(bot)
    false
  end
end