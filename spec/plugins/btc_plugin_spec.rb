require 'spec_helper'
require 'cinch'
require_relative '../../extensions/text'
require_relative '../../plugins/btc_plugin'

RSpec.describe CryptoApiClient do
  let(:client) { described_class.new(timeout: 1) }

  describe '#btc_price_in_usd' do
    it 'returns the USD price of Bitcoin' do
      stub_request(:get, "https://blockchain.info/tobtc?currency=USD&value=1")
        .to_return(status: 200, body: "0.0000222222")
      
      expect(client.btc_price_in_usd).to be_within(0.1).of(45000.0)
    end

    it 'caches the result for subsequent calls' do
      stub_request(:get, "https://blockchain.info/tobtc?currency=USD&value=1")
        .to_return(status: 200, body: "0.0000222222")
        .times(1) # Should only be called once
      
      2.times { expect(client.btc_price_in_usd).to be_within(0.1).of(45000.0) }
    end

    it 'raises ApiError on HTTP failure' do
      stub_request(:get, "https://blockchain.info/tobtc?currency=USD&value=1")
        .to_return(status: 500, body: "Server Error")
      
      expect { client.btc_price_in_usd }.to raise_error(CryptoApiClient::ApiError, /HTTP 500/)
    end

    it 'raises ApiError on timeout' do
      stub_request(:get, "https://blockchain.info/tobtc?currency=USD&value=1")
        .to_timeout
      
      expect { client.btc_price_in_usd }.to raise_error(CryptoApiClient::ApiError, /timeout/)
    end
  end

  describe '#get_coin_prices' do
    it 'fetches prices for a given coin' do
      stub_request(:get, "https://min-api.cryptocompare.com/data/price?fsym=ETH&tsyms=USD,PLN")
        .to_return(status: 200, body: '{"USD": 3000, "PLN": 12000}')
      
      expect(client.get_coin_prices('ETH')).to eq({ 'USD' => 3000, 'PLN' => 12000 })
    end

    it 'handles custom currency lists' do
      stub_request(:get, "https://min-api.cryptocompare.com/data/price?fsym=BTC&tsyms=EUR,GBP")
        .to_return(status: 200, body: '{"EUR": 40000, "GBP": 35000}')
      
      expect(client.get_coin_prices('BTC', ['EUR', 'GBP'])).to eq({ 'EUR' => 40000, 'GBP' => 35000 })
    end
  end

  describe '#coin_list' do
    it 'fetches and caches the coin list' do
      stub_request(:get, "https://www.cryptocompare.com/api/data/coinlist/")
        .to_return(status: 200, body: '{"Data": {"BTC": {}, "ETH": {}, "XRP": {}}}')
        .times(1)
      
      2.times { expect(client.coin_list).to eq(['BTC', 'ETH', 'XRP']) }
    end
  end
end

RSpec.describe PriceMonitor do
  let(:monitor) { described_class.new(rounding_factor: 500) }

  describe '#round_to_increment' do
    it 'rounds prices to the nearest increment' do
      expect(monitor.round_to_increment(9749)).to eq(9500)
      expect(monitor.round_to_increment(9750)).to eq(10000)
      expect(monitor.round_to_increment(10000)).to eq(10000)
    end
  end

  describe '#significant_change?' do
    context 'with no checkpoint' do
      it 'returns false' do
        expect(monitor.significant_change?(10000)).to be false
      end
    end

    context 'with checkpoint set' do
      before { monitor.update_checkpoint(10000) }

      it 'detects significant increases' do
        expect(monitor.significant_change?(10499)).to be false
        expect(monitor.significant_change?(10500)).to be true
        expect(monitor.significant_change?(10501)).to be true
      end

      it 'detects significant decreases' do
        expect(monitor.significant_change?(9501)).to be false
        expect(monitor.significant_change?(9500)).to be true
        expect(monitor.significant_change?(9499)).to be true
      end
    end
  end

  describe '#format_price_update' do
    it 'formats price increase with green color' do
      message = monitor.format_price_update(10500, 10000)
      expect(message).to include('10500')
      expect(message).to include('was 10000')
      expect(message).to include(Text::GREEN)
    end

    it 'formats price decrease with red color' do
      message = monitor.format_price_update(9500, 10000)
      expect(message).to include('9500')
      expect(message).to include('was 10000')
      expect(message).to include(Text::RED)
    end
  end
end

RSpec.describe BtcPlugin do
  let(:bot) { instance_double(Cinch::Bot) }
  let(:config) { { btc_channel: '#test' } }
  let(:plugin) { described_class.allocate }
  let(:message) { double('message') }
  let(:user) { double('user') }
  let(:api_client) { instance_double(CryptoApiClient) }
  let(:logger) { double('logger') }

  before do
    # Set up plugin without calling initialize
    plugin.instance_variable_set(:@bot, bot)
    plugin.instance_variable_set(:@msg_channel, '#test')
    plugin.instance_variable_set(:@api_client, api_client)
    plugin.instance_variable_set(:@price_monitor, PriceMonitor.new)
    
    allow(bot).to receive(:config).and_return(double(plugins: double(options: { described_class => config })))
    allow(bot).to receive(:loggers).and_return(logger)
    allow(logger).to receive(:error)
    allow(message).to receive(:user).and_return(user)
    allow(Thread).to receive(:new).and_yield # Run thread synchronously in tests
    allow(api_client).to receive(:coin_list).and_return(['BTC', 'ETH', 'XRP'])
  end

  describe '.btc command' do
    it 'replies with current BTC price' do
      allow(api_client).to receive(:btc_price_in_usd).and_return(45000.0)
      expect(message).to receive(:reply).with("45000.0 USD")
      
      plugin.btc(message)
    end

    it 'handles API errors gracefully' do
      allow(api_client).to receive(:btc_price_in_usd)
        .and_raise(CryptoApiClient::ApiError, "Connection failed")
      expect(message).to receive(:reply).with("Error fetching BTC price: Connection failed")
      
      plugin.btc(message)
    end
  end

  describe '.eth command' do
    it 'replies with ETH prices' do
      allow(api_client).to receive(:get_coin_prices).with('ETH')
        .and_return({ 'USD' => 3000, 'PLN' => 12000 })
      expect(message).to receive(:reply).with("USD: 3000, PLN: 12000")
      
      plugin.eth(message)
    end
  end

  describe '.crypto command' do
    context 'with valid coin' do
      it 'replies with coin prices' do
        plugin.instance_variable_set(:@coin_list, ['BTC', 'ETH', 'XRP'])
        allow(api_client).to receive(:get_coin_prices).with('XRP')
          .and_return({ 'USD' => 0.5, 'PLN' => 2.0 })
        expect(message).to receive(:reply).with("USD: 0.5, PLN: 2.0")
        
        plugin.crypto(message, 'xrp')
      end
    end

    context 'with invalid coin' do
      it 'replies with error message' do
        plugin.instance_variable_set(:@coin_list, ['BTC', 'ETH', 'XRP'])
        expect(message).to receive(:reply).with("Coin unknown (INVALID).")
        
        plugin.crypto(message, 'invalid')
      end
    end
  end

  describe '.cryptoupdate command' do
    context 'with admin user' do
      before { allow(user).to receive(:has_admin_access?).and_return(true) }

      it 'updates coin list successfully' do
        # Set up initial coin list
        plugin.instance_variable_set(:@coin_list, ['BTC', 'ETH'])
        # Mock the safe_update_coin_list method
        allow(plugin).to receive(:safe_update_coin_list).and_return(true)
        expect(message).to receive(:reply).with('Cryptocurrency list updated.')
        
        plugin.update(message)
      end

      it 'handles update failures' do
        allow(plugin).to receive(:safe_update_coin_list).and_return(false)
        expect(message).to receive(:reply).with('Failed to update cryptocurrency list.')
        
        plugin.update(message)
      end
    end

    context 'without admin access' do
      before { allow(user).to receive(:has_admin_access?).and_return(false) }

      it 'does nothing' do
        expect(message).not_to receive(:reply)
        plugin.update(message)
      end
    end
  end

  describe '#btc_price_check' do
    let(:channel) { double('channel') }
    let(:price_monitor) { instance_double(PriceMonitor) }

    before do
      plugin.instance_variable_set(:@price_monitor, price_monitor)
      allow(plugin).to receive(:Channel).with('#test').and_return(channel)
    end

    context 'on first run' do
      it 'initializes checkpoint without sending message' do
        allow(price_monitor).to receive(:checkpoint).and_return(nil)
        allow(api_client).to receive(:btc_price_in_usd).and_return(45000.0)
        expect(price_monitor).to receive(:update_checkpoint).with(45000.0)
        expect(channel).not_to receive(:send)
        
        plugin.btc_price_check
      end
    end

    context 'with existing checkpoint' do
      before do
        allow(price_monitor).to receive(:checkpoint).and_return(45000.0)
      end

      it 'sends update on significant change' do
        allow(api_client).to receive(:btc_price_in_usd).and_return(45600.0)
        allow(price_monitor).to receive(:significant_change?).with(45600.0).and_return(true)
        allow(price_monitor).to receive(:format_price_update)
          .with(45600.0, 45000.0).and_return("Price update message")
        
        expect(channel).to receive(:send).with("Price update message")
        expect(price_monitor).to receive(:update_checkpoint).with(45600.0)
        
        plugin.btc_price_check
      end

      it 'does nothing on minor change' do
        allow(api_client).to receive(:btc_price_in_usd).and_return(45200.0)
        allow(price_monitor).to receive(:significant_change?).with(45200.0).and_return(false)
        
        expect(channel).not_to receive(:send)
        expect(price_monitor).not_to receive(:update_checkpoint)
        
        plugin.btc_price_check
      end
    end

    it 'logs errors without crashing' do
      allow(price_monitor).to receive(:checkpoint).and_return(45000.0)
      allow(api_client).to receive(:btc_price_in_usd)
        .and_raise(CryptoApiClient::ApiError, "API down")
      
      expect(logger).to receive(:error).with("BTC price check failed: API down")
      expect { plugin.btc_price_check }.not_to raise_error
    end
  end
end