require 'spec_helper'
require 'cinch'
require_relative '../../plugins/plugin_management'

RSpec.describe Cinch::Plugins::PluginManagement do
  let(:plugin) { described_class.allocate }
  let(:options) { Hash.new { |hash, key| hash[key] = {} } }
  let(:bot) do
    plugin_config = Struct.new(:options).new(options)
    Struct.new(:config).new(Struct.new(:plugins).new(plugin_config))
  end
  let(:message) { instance_double('Message', user: user, reply: nil) }

  before do
    stub_const('Cinch::Plugins::OptionTarget', Class.new)
    plugin.instance_variable_set(:@bot, bot)
  end

  describe '#set_option' do
    context 'without admin access' do
      let(:user) { instance_double('User', has_admin_access?: false) }

      it 'does not evaluate or change the option' do
        expect do
          plugin.set_option(message, 'OptionTarget', 'limit', "raise 'must not run'")
        end.not_to raise_error
        expect(options[Cinch::Plugins::OptionTarget]).to be_empty
      end
    end

    context 'with admin access' do
      let(:user) { instance_double('User', has_admin_access?: true) }

      it 'keeps the existing runtime option behavior' do
        plugin.set_option(message, 'OptionTarget', 'limit', '123')
        expect(options[Cinch::Plugins::OptionTarget][:limit]).to eq(123)
      end
    end
  end
end
