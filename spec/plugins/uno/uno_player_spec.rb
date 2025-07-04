require_relative 'uno_spec_helper'

RSpec.describe UnoPlayer do
  let(:player) { UnoPlayer.new('Alice') }
  
  describe '#initialize' do
    it 'creates a player with a nick' do
      expect(player.identity.display_name).to eq('Alice')
    end
    
    it 'initializes with empty hand' do
      expect(player.hand).to be_a(Hand)
      expect(player.hand).to be_empty
    end
    
    it 'sets joined time' do
      # Player should have a @joined timestamp
      expect(player.instance_variable_get(:@joined)).to be_a(Time)
    end
  end
  
  describe 'identity' do
    it 'has a display name that is read-only from outside' do
      expect { player.identity.display_name = 'Bob' }.to raise_error(NoMethodError)
    end
    
    it 'returns the player display name' do
      expect(player.identity.display_name).to eq('Alice')
    end
  end
  
  describe '#hand' do
    it 'is accessible for reading and writing' do
      new_hand = Hand.new
      player.hand = new_hand
      expect(player.hand).to eq(new_hand)
    end
    
    it 'can have cards added' do
      card = UnoCard.new(:red, 5)
      player.hand << card
      expect(player.hand.size).to eq(1)
      expect(player.hand.first).to eq(card)
    end
  end
  
  describe '#to_s' do
    it 'returns the nick as string representation' do
      expect(player.to_s).to eq('Alice')
    end
  end
  
  describe 'nick changes through identity' do
    it 'changes the player display name' do
      player.identity.update_display_name('Bob')
      expect(player.identity.display_name).to eq('Bob')
    end
    
    it 'updates string representation' do
      player.identity.update_display_name('Charlie')
      expect(player.to_s).to eq('Charlie')
    end
  end
  
  describe '#==' do
    let(:alice1) { UnoPlayer.new('Alice') }
    let(:alice2) { UnoPlayer.new('Alice') }
    let(:bob) { UnoPlayer.new('Bob') }
    
    it 'considers players with same nick equal' do
      expect(alice1).to eq(alice2)
    end
    
    it 'considers players with different nicks not equal' do
      expect(alice1).not_to eq(bob)
    end
    
    it 'is not affected by hand contents' do
      alice1.hand << UnoCard.new(:red, 5)
      alice2.hand << UnoCard.new(:blue, 3)
      expect(alice1).to eq(alice2)
    end
    
    it 'is not affected by nick changes' do
      alice_changed = UnoPlayer.new('Alice')
      alice_changed.identity.update_display_name('NotAlice')
      expect(alice1).not_to eq(alice_changed)
    end
  end
  
  describe 'integration with Hand' do
    it 'can manage a full hand of cards' do
      7.times do |i|
        player.hand << UnoCard.new(:red, i)
      end
      
      expect(player.hand.size).to eq(7)
      expect(player.hand.value).to eq(0 + 1 + 2 + 3 + 4 + 5 + 6)
    end
    
    it 'supports hand operations' do
      player.hand << [
        UnoCard.new(:red, 5),
        UnoCard.new(:blue, 5),
        UnoCard.new(:green, 3)
      ]
      
      # Find card
      expect(player.hand.find_card('r5')).not_to be_nil
      
      # Playable cards
      top_card = UnoCard.new(:red, 3)
      playable = player.hand.playable_after(top_card)
      expect(playable.size).to eq(2) # red 5 and green 3
    end
  end
  
  describe 'usage patterns' do
    it 'can be stored in arrays' do
      players = []
      players << UnoPlayer.new('Alice')
      players << UnoPlayer.new('Bob')
      
      expect(players.map { |p| p.identity.display_name }).to eq(['Alice', 'Bob'])
      expect(players.map(&:to_s)).to eq(['Alice', 'Bob'])
    end
    
    it 'can be found in arrays by nick' do
      players = [
        UnoPlayer.new('Alice'),
        UnoPlayer.new('Bob'),
        UnoPlayer.new('Charlie')
      ]
      
      bob = players.find { |p| p.identity.display_name == 'Bob' }
      expect(bob).not_to be_nil
      expect(bob.identity.display_name).to eq('Bob')
    end
    
    it 'supports nick-based comparison in arrays' do
      players = [UnoPlayer.new('Alice'), UnoPlayer.new('Bob')]
      alice_duplicate = UnoPlayer.new('Alice')
      
      expect(players).to include(alice_duplicate)
    end
  end
  
  describe '@joined timestamp' do
    it 'is set on creation' do
      before_time = Time.now
      new_player = UnoPlayer.new('TestPlayer')
      after_time = Time.now
      
      joined_time = new_player.instance_variable_get(:@joined)
      expect(joined_time).to be >= before_time
      expect(joined_time).to be <= after_time
    end
    
    it 'is not exposed as public method' do
      expect(player).not_to respond_to(:joined)
    end
  end
end