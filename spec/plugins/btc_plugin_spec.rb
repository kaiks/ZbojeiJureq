require 'spec_helper'
require 'cinch'
require 'stringio'
require_relative '../../extensions/text'
require_relative '../../plugins/btc_plugin'

# Ensure open-uri is loaded before WebMock patches it
require 'open-uri'

RSpec.describe BtcPlugin do
  # For simple helper method tests, we'll use a minimal plugin instance
  describe '#round_to_500' do
    let(:plugin) { described_class.allocate }
    
    before do
      # Initialize just enough to test the method
      plugin.instance_variable_set(:@bot, double('bot'))
    end
    it 'rounds down to nearest 500 when below midpoint' do
      expect(plugin.round_to_500(9749)).to eq(9500)
    end

    it 'rounds up to nearest 500 when at or above midpoint' do
      expect(plugin.round_to_500(9750)).to eq(10000)
      expect(plugin.round_to_500(9751)).to eq(10000)
    end

    it 'handles exact 500 multiples' do
      expect(plugin.round_to_500(10000)).to eq(10000)
      expect(plugin.round_to_500(10500)).to eq(10500)
    end

    it 'handles small numbers' do
      expect(plugin.round_to_500(249)).to eq(0)
      expect(plugin.round_to_500(250)).to eq(500)
      expect(plugin.round_to_500(751)).to eq(1000)
    end
  end

  describe '#btc_price_update?' do
    let(:plugin) { described_class.allocate }
    
    before do
      plugin.instance_variable_set(:@bot, double('bot'))
    end

    context 'when price increases' do
      before do
        plugin.instance_variable_set(:@btc_price_checkpoint, 10000)
      end

      it 'returns true when price increases by 500 or more' do
        expect(plugin.btc_price_update?(10500)).to be true
        expect(plugin.btc_price_update?(10501)).to be true
      end

      it 'returns false when price increases by less than 500' do
        expect(plugin.btc_price_update?(10499)).to be false
        expect(plugin.btc_price_update?(10250)).to be false
      end
    end

    context 'when price decreases' do
      before do
        plugin.instance_variable_set(:@btc_price_checkpoint, 10000)
      end

      it 'returns true when price decreases by 500 or more' do
        expect(plugin.btc_price_update?(9500)).to be true
        expect(plugin.btc_price_update?(9499)).to be true
      end

      it 'returns false when price decreases by less than 500' do
        expect(plugin.btc_price_update?(9501)).to be false
        expect(plugin.btc_price_update?(9750)).to be false
      end
    end
  end

  describe '#cryptocompare_parse' do
    let(:plugin) { described_class.allocate }

    it 'formats single currency response' do
      response = '{"USD": 45000}'
      expect(plugin.cryptocompare_parse(response)).to eq('USD: 45000')
    end

    it 'formats multiple currency response' do
      response = '{"USD": 45000, "PLN": 180000}'
      expect(plugin.cryptocompare_parse(response)).to eq('USD: 45000, PLN: 180000')
    end

    it 'handles empty response' do
      response = '{}'
      expect(plugin.cryptocompare_parse(response)).to eq('')
    end
  end

  describe 'IRC commands' do
    let(:plugin) { described_class.allocate }
    let(:message) { double('message') }
    let(:user) { double('user') }

    before do
      # Mock bot and set instance variables
      plugin.instance_variable_set(:@bot, double('bot'))
      plugin.instance_variable_set(:@coin_list, ['BTC', 'ETH', 'XRP', 'DOGE'])
      
      allow(message).to receive(:user).and_return(user)
    end

    describe '.btc command' do
      before do
        # Mock both the open call and btc_price_in_usd method
        allow(plugin).to receive(:open).with("https://blockchain.info/tobtc?currency=USD&value=1")
          .and_return(StringIO.new("0.0000222222"))
        allow(plugin).to receive(:btc_price_in_usd).and_return(45000.0)
      end

      it 'replies with BTC price in USD' do
        expect(message).to receive(:reply).with("45000.0 USD")
        plugin.btc(message)
      end
    end

    describe '.eth command' do
      before do
        # Mock the open method in get_coin_cryptocompare
        allow(plugin).to receive(:open)
          .with("https://min-api.cryptocompare.com/data/price?fsym=ETH&tsyms=USD,PLN")
          .and_return(StringIO.new('{"USD": 3000, "PLN": 12000}'))
      end

      it 'replies with ETH prices in USD and PLN' do
        expect(message).to receive(:reply).with("USD: 3000, PLN: 12000")
        plugin.eth(message)
      end
    end

    describe '.crypto command' do
      context 'with valid coin' do
        before do
          allow(plugin).to receive(:open)
            .with("https://min-api.cryptocompare.com/data/price?fsym=DOGE&tsyms=USD,PLN")
            .and_return(StringIO.new('{"USD": 0.08, "PLN": 0.32}'))
        end

        it 'replies with coin prices' do
          expect(message).to receive(:reply).with("USD: 0.08, PLN: 0.32")
          plugin.crypto(message, 'doge')
        end
      end

      context 'with invalid coin' do
        it 'replies with error message' do
          expect(message).to receive(:reply).with("Coin unknown (INVALID).")
          plugin.crypto(message, 'invalid')
        end
      end
    end

    describe '.cryptoupdate command' do
      context 'with admin user' do
        before do
          allow(user).to receive(:has_admin_access?).and_return(true)
          # Mock URI.open for the update_cryptocompare_coin_list method
          allow(URI).to receive(:open)
            .with("https://www.cryptocompare.com/api/data/coinlist/")
            .and_return(StringIO.new('{"Data": {"BTC": {}, "ETH": {}, "NEW": {}}}'))
        end

        it 'updates coin list and confirms' do
          expect(message).to receive(:reply).with('Cryptocurrency list updated.')
          plugin.update(message)
        end
      end

      context 'without admin user' do
        before do
          allow(user).to receive(:has_admin_access?).and_return(false)
        end

        it 'does nothing' do
          expect(message).not_to receive(:reply)
          plugin.update(message)
        end
      end
    end
  end

  describe 'price monitoring' do
    let(:plugin) { described_class.allocate }
    let(:channel) { double('channel') }

    before do
      plugin.instance_variable_set(:@bot, double('bot'))
      allow(plugin).to receive(:Channel).with('#kx').and_return(channel)
      
      # Stub the btc_price_in_usd method
      allow(plugin).to receive(:btc_price_in_usd).and_return(10000)
    end

    describe '#btc_price_check' do
      context 'when price increases significantly' do
        before do
          plugin.instance_variable_set(:@btc_price_checkpoint, 9500)
          allow(plugin).to receive(:btc_price_in_usd).and_return(10100)
        end

        it 'sends a green-colored price update to channel' do
          expect(channel).to receive(:send) do |msg|
            expect(msg).to include('BTC price update:')
            expect(msg).to include('10100')
            expect(msg).to include('was 9500')
            expect(msg).to include(Text::GREEN)
          end
          
          plugin.btc_price_check
        end

        it 'updates the checkpoint' do
          allow(channel).to receive(:send)
          plugin.btc_price_check
          expect(plugin.instance_variable_get(:@btc_price_checkpoint)).to eq(10000)
        end
      end

      context 'when price decreases significantly' do
        before do
          plugin.instance_variable_set(:@btc_price_checkpoint, 10500)
          allow(plugin).to receive(:btc_price_in_usd).and_return(9900)
        end

        it 'sends a red-colored price update to channel' do
          expect(channel).to receive(:send) do |msg|
            expect(msg).to include('BTC price update:')
            expect(msg).to include('9900')
            expect(msg).to include('was 10500')
            expect(msg).to include(Text::RED)
          end
          
          plugin.btc_price_check
        end
      end

      context 'when price change is not significant' do
        before do
          plugin.instance_variable_set(:@btc_price_checkpoint, 10000)
          allow(plugin).to receive(:btc_price_in_usd).and_return(10200)
        end

        it 'does not send any message' do
          expect(channel).not_to receive(:send)
          plugin.btc_price_check
        end
      end

      context 'on first run' do
        before do
          plugin.instance_variable_set(:@btc_price_checkpoint, nil)
          allow(plugin).to receive(:btc_price_in_usd).and_return(10250)
        end

        it 'initializes checkpoint without sending message' do
          expect(channel).not_to receive(:send)
          plugin.btc_price_check
          expect(plugin.instance_variable_get(:@btc_price_checkpoint)).to eq(10500)
        end
      end
    end
  end

  describe 'error handling' do
    let(:plugin) { described_class.allocate }

    before do
      plugin.instance_variable_set(:@bot, double('bot'))
    end

    describe '#cryptocompare_parse' do
      it 'handles malformed JSON gracefully' do
        expect { plugin.cryptocompare_parse('invalid json') }.to raise_error(JSON::ParserError)
      end

      it 'handles nil response' do
        expect { plugin.cryptocompare_parse(nil) }.to raise_error(TypeError)
      end
    end

    describe '#btc_price_update?' do
      it 'raises error when checkpoint is nil' do
        plugin.instance_variable_set(:@btc_price_checkpoint, nil)
        # The current implementation doesn't handle nil checkpoint
        expect { plugin.btc_price_update?(10000) }.to raise_error(ArgumentError)
      end
    end

    describe '#update_cryptocompare_coin_list' do
      it 'handles API response with missing Data key' do
        allow(URI).to receive(:open).and_return(StringIO.new('{"error": "API limit reached"}'))
        expect { plugin.update_cryptocompare_coin_list }.to raise_error(NoMethodError)
      end
    end
  end
end