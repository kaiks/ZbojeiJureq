require 'spec_helper'
require 'sequel'
require 'tempfile'
require 'jedna'

# Set up test database
def setup_test_database
  # Create a temporary database file for testing
  @db_file = Tempfile.new(['uno_test', '.db'])
  @db_path = @db_file.path
  
  # Connect to the test database
  db = Sequel.sqlite(@db_path)
  
  # Create schema based on uno.db.template
  db.create_table :uno do
    String :nick, primary_key: true
    Integer :total_score, default: 0
    Integer :games, default: 0
    Integer :wins, default: 0
  end
  
  db.create_table :games do
    primary_key :ID
    String :start
    String :end
    Integer :points
    String :winner
    Integer :players
    String :created_by
    Integer :total_score
    Integer :game
  end
  
  db.create_table :turn do
    primary_key :ID
    Integer :game
    String :card
    String :color
    String :figure
    String :player
    Integer :received
    String :time
  end
  
  db.create_table :player_action do
    primary_key :ID
    Integer :game
    Integer :action
    String :player
    String :subject
  end
  
  db
end

# Clean up test database
def cleanup_test_database
  @db_file.close
  @db_file.unlink if @db_file
end

# Mock notifier that captures notifications
class TestNotifier
  include Jedna::Notifier
  
  attr_reader :game_notifications, :player_notifications, :errors, :debug_messages
  
  def initialize
    @game_notifications = []
    @player_notifications = []
    @errors = []
    @debug_messages = []
  end
  
  def notify_game(message)
    @game_notifications << message
  end
  
  def notify_player(player_id, message)
    @player_notifications << { player: player_id, text: message }
  end
  
  def notify_error(player_id, error)
    @errors << { player: player_id, error: error }
  end
  
  def debug(message)
    @debug_messages << message
  end
end

# Mock IRC game for testing
class TestUnoGame < Jedna::Game
  attr_reader :test_notifier
  
  def initialize(creator, casual = 0)
    @test_notifier = TestNotifier.new
    renderer = Jedna::TextRenderer.new
    repository = Jedna::NullRepository.new
    super(creator, casual, @test_notifier, renderer, repository)
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

# Helper to create a game with players
def create_game_with_players(player_names = ['Alice', 'Bob'])
  game = TestUnoGame.new(player_names.first, 1) # casual mode to skip DB
  player_names.each do |name|
    game.add_player(Jedna::Player.new(name))
  end
  game
end

# Helper to start a game and deal cards
def start_game(game)
  game.start_game
  game
end

# RSpec configuration for UNO tests
module UnoTestHelper
  def self.original_stdout
    @original_stdout ||= $stdout
  end
  
  def self.original_stdout=(value)
    @original_stdout = value
  end
end

RSpec.configure do |config|
  config.before(:suite) do
    # Silence stdout during tests
    UnoTestHelper.original_stdout = $stdout
    $stdout = StringIO.new
  end
  
  config.after(:suite) do
    $stdout = UnoTestHelper.original_stdout
  end
  
  config.before(:each, :db) do
    @test_db = setup_test_database
    # Make the test DB available to UNO models
    stub_const('UNODB', @test_db)
    require_relative '../../../plugins/uno/uno_db'
  end
  
  config.after(:each, :db) do
    cleanup_test_database
  end
end

# Shared contexts
RSpec.shared_context "uno game setup" do
  let(:game) { TestUnoGame.new('TestCreator', 1) }
  let(:alice) { Jedna::Player.new('Alice') }
  let(:bob) { Jedna::Player.new('Bob') }
  
  before do
    game.add_player(alice)
    game.add_player(bob)
  end
end

RSpec.shared_context "uno game started" do
  include_context "uno game setup"
  
  before do
    game.start_game
  end
end

# Matchers for UNO tests
RSpec::Matchers.define :be_playable_after do |card|
  match do |actual|
    actual.plays_after?(card)
  end
  
  failure_message do |actual|
    "expected #{actual} to be playable after #{card}"
  end
end

RSpec::Matchers.define :have_notification do |expected|
  match do |game|
    game.notifications.include?(expected)
  end
  
  failure_message do |game|
    "expected game to have notification '#{expected}', but got: #{game.notifications}"
  end
end