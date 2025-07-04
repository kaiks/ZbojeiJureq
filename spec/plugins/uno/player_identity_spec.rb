require 'spec_helper'
require_relative '../../../plugins/uno/interfaces/player_identity'

RSpec.describe "Uno::PlayerIdentity" do
  describe Uno::IrcIdentity do
    let(:identity) { Uno::IrcIdentity.new('Alice') }
    
    describe '#id' do
      it 'returns the nick as id' do
        expect(identity.id).to eq('Alice')
      end
    end
    
    describe '#display_name' do
      it 'returns the nick as display name' do
        expect(identity.display_name).to eq('Alice')
      end
    end
    
    describe '#matches?' do
      it 'matches another IrcIdentity with same nick' do
        other = Uno::IrcIdentity.new('Alice')
        expect(identity.matches?(other)).to be true
      end
      
      it 'does not match IrcIdentity with different nick' do
        other = Uno::IrcIdentity.new('Bob')
        expect(identity.matches?(other)).to be false
      end
      
      it 'matches a string with same value' do
        expect(identity.matches?('Alice')).to be true
      end
      
      it 'does not match a different string' do
        expect(identity.matches?('Bob')).to be false
      end
      
      it 'does not match other types' do
        expect(identity.matches?(123)).to be false
      end
    end
    
    describe '#update_display_name' do
      it 'updates the display name' do
        identity.update_display_name('Alice2')
        expect(identity.display_name).to eq('Alice2')
        expect(identity.nick).to eq('Alice2')
        expect(identity.id).to eq('Alice2')
      end
    end
  end
  
  describe Uno::SimpleIdentity do
    let(:identity) { Uno::SimpleIdentity.new('Player1') }
    
    describe '#id' do
      it 'returns the name as id' do
        expect(identity.id).to eq('Player1')
      end
    end
    
    describe '#display_name' do
      it 'returns the name as display name' do
        expect(identity.display_name).to eq('Player1')
      end
    end
    
    describe '#matches?' do
      it 'matches another SimpleIdentity with same name' do
        other = Uno::SimpleIdentity.new('Player1')
        expect(identity.matches?(other)).to be true
      end
      
      it 'matches a string with same value' do
        expect(identity.matches?('Player1')).to be true
      end
    end
    
    describe '#update_display_name' do
      it 'does nothing (SimpleIdentity is immutable)' do
        identity.update_display_name('NewName')
        expect(identity.display_name).to eq('Player1')  # Unchanged
      end
    end
  end
  
  describe Uno::UuidIdentity do
    let(:uuid) { '123e4567-e89b-12d3-a456-426614174000' }
    let(:identity) { Uno::UuidIdentity.new(uuid, 'Alice') }
    
    describe '#id' do
      it 'returns the UUID as id' do
        expect(identity.id).to eq(uuid)
      end
    end
    
    describe '#display_name' do
      it 'returns the provided name' do
        expect(identity.display_name).to eq('Alice')
      end
      
      it 'generates a name if none provided' do
        identity_no_name = Uno::UuidIdentity.new(uuid)
        expect(identity_no_name.display_name).to eq('Player-123e4567')
      end
    end
    
    describe '#matches?' do
      it 'matches another UuidIdentity with same UUID' do
        other = Uno::UuidIdentity.new(uuid, 'Bob')
        expect(identity.matches?(other)).to be true
      end
      
      it 'does not match UuidIdentity with different UUID' do
        other = Uno::UuidIdentity.new('different-uuid')
        expect(identity.matches?(other)).to be false
      end
      
      it 'matches a string with the UUID value' do
        expect(identity.matches?(uuid)).to be true
      end
    end
    
    describe '#update_display_name' do
      it 'updates the display name' do
        identity.update_display_name('Alice2')
        expect(identity.display_name).to eq('Alice2')
        expect(identity.name).to eq('Alice2')
        expect(identity.id).to eq(uuid) # ID should not change
      end
    end
  end
end