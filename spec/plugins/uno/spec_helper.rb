require 'spec_helper'
require_relative '../../../plugins/uno/interfaces/notifier'

# Mock IRC game for testing
class TestUnoGame < UnoGame
  attr_reader :test_notifier
  
  def initialize(creator, casual = 0)
    @test_notifier = Uno::NullNotifier.new
    super(creator, casual, @test_notifier)
  end
  
  def notifications
    @test_notifier.game_notifications
  end
  
  def player_notifications
    @test_notifier.player_notifications
  end
  
  def clean_up_end_game
    # No-op for tests
  end
end