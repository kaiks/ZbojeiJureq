require 'spec_helper'
require_relative '../../../plugins/uno/interfaces/notifier'
require_relative '../../../plugins/uno/interfaces/renderer'
require_relative '../../../plugins/uno/interfaces/repository'

# Mock IRC game for testing
class TestUnoGame < UnoGame
  attr_reader :test_notifier, :test_repository
  
  def initialize(creator, casual = 0)
    @test_notifier = Uno::NullNotifier.new
    @test_repository = Uno::NullRepository.new
    super(creator, casual, @test_notifier, nil, @test_repository)
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