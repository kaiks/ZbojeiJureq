require 'spec_helper'
require_relative '../../../plugins/uno/game_rules'

RSpec.describe UnoRules do
  describe '.two_player_reverse_acts_as_skip?' do
    it 'defaults to disabled' do
      expect(described_class.two_player_reverse_acts_as_skip?(config: {}, env: {})).to be(false)
    end

    it 'uses the configured value' do
      config = { 'uno_two_player_reverse_acts_as_skip' => false }

      expect(described_class.two_player_reverse_acts_as_skip?(config: config, env: {})).to be(false)
    end

    it 'lets the environment override the application config' do
      config = { 'uno_two_player_reverse_acts_as_skip' => true }
      env = { 'UNO_TWO_PLAYER_REVERSE_ACTS_AS_SKIP' => 'off' }

      expect(described_class.two_player_reverse_acts_as_skip?(config: config, env: env)).to be(false)
    end

    it 'rejects ambiguous values' do
      config = { 'uno_two_player_reverse_acts_as_skip' => 'sometimes' }

      expect do
        described_class.two_player_reverse_acts_as_skip?(config: config, env: {})
      end.to raise_error(ArgumentError, /must be true or false/)
    end
  end
end
