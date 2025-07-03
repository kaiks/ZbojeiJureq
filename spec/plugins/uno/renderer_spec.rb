require 'spec_helper'
require_relative '../../../plugins/uno/misc'
require_relative '../../../plugins/uno/uno'
require_relative '../../../plugins/uno/uno_card'
require_relative '../../../plugins/uno/uno_hand'
require_relative '../../../plugins/uno/interfaces/renderer'

RSpec.describe "Uno::Renderer" do
  let(:red_5) { UnoCard.new(:red, 5) }
  let(:blue_skip) { UnoCard.new(:blue, 'skip') }
  let(:wild_card) { UnoCard.new(:wild, 'wild') }
  let(:wild_draw_4) { UnoCard.new(:wild, 'wild+4') }
  let(:hand) { Hand.new([red_5, blue_skip, wild_card]) }
  
  describe Uno::TextRenderer do
    let(:renderer) { Uno::TextRenderer.new }
    
    describe '#render_card' do
      it 'renders regular cards as color+figure' do
        expect(renderer.render_card(red_5)).to eq('r5')
      end
      
      it 'renders action cards with short codes' do
        expect(renderer.render_card(blue_skip)).to eq('bs')
      end
      
      it 'renders wild cards correctly' do
        expect(renderer.render_card(wild_card)).to eq('w')
        expect(renderer.render_card(wild_draw_4)).to eq('wd4')
      end
    end
    
    describe '#render_hand' do
      it 'renders multiple cards separated by spaces' do
        expect(renderer.render_hand(hand)).to eq('r5 bs w')
      end
      
      it 'handles empty hands' do
        expect(renderer.render_hand(Hand.new)).to eq('')
      end
    end
    
    describe '#render_game_state' do
      it 'renders basic game state' do
        state = {
          status: 'playing',
          top_card: red_5,
          current_player: 'Alice'
        }
        result = renderer.render_game_state(state)
        expect(result).to include('Game state: playing')
        expect(result).to include('Top card: r5')
        expect(result).to include('Current player: Alice')
      end
    end
    
    describe '#render_player_order' do
      it 'renders player order' do
        players = ['Alice', 'Bob', 'Charlie']
        expect(renderer.render_player_order(players)).to eq('Player order: Alice -> Bob -> Charlie')
      end
    end
  end
  
  describe Uno::IrcRenderer do
    let(:renderer) { Uno::IrcRenderer.new }
    
    describe '#render_card' do
      it 'renders cards with IRC color codes' do
        result = renderer.render_card(red_5)
        expect(result).to start_with("\x03")  # IRC color code character
        expect(result).to include('[5]')
      end
      
      it 'uses correct color codes' do
        expect(renderer.render_card(red_5)).to include("\x034")      # red
        expect(renderer.render_card(blue_skip)).to include("\x0312") # blue
        expect(renderer.render_card(UnoCard.new(:green, 7))).to include("\x033")    # green
        expect(renderer.render_card(UnoCard.new(:yellow, 9))).to include("\x037")   # yellow
        expect(renderer.render_card(wild_card)).to include("\x0313") # wild
      end
      
      it 'uppercases figure codes' do
        expect(renderer.render_card(blue_skip)).to include('[S]')
        expect(renderer.render_card(wild_draw_4)).to include('[WD4]')
      end
    end
    
    describe '#render_hand' do
      it 'renders multiple cards with IRC formatting' do
        result = renderer.render_hand(hand)
        expect(result).to include("\x034[5]")
        expect(result).to include("\x0312[S]")
        expect(result).to include("\x0313[W]")
      end
    end
    
    describe '#render_game_state' do
      it 'renders state with IRC formatting' do
        state = {
          status: 'playing',
          top_card: red_5,
          current_player: 'Alice'
        }
        result = renderer.render_game_state(state)
        expect(result).to include("Alice's turn")
        expect(result).to include("\x034[5]")
      end
    end
  end
  
  describe Uno::HtmlRenderer do
    let(:renderer) { Uno::HtmlRenderer.new }
    
    describe '#render_card' do
      it 'renders cards as HTML spans' do
        result = renderer.render_card(red_5)
        expect(result).to eq("<span class='uno-card red'>5</span>")
      end
      
      it 'includes color class' do
        expect(renderer.render_card(blue_skip)).to include("class='uno-card blue'")
        expect(renderer.render_card(wild_card)).to include("class='uno-card wild'")
      end
    end
    
    describe '#render_hand' do
      it 'wraps cards in a div' do
        result = renderer.render_hand(hand)
        expect(result).to start_with("<div class='uno-hand'>")
        expect(result).to end_with("</div>")
        expect(result).to include("<span class='uno-card red'>5</span>")
      end
    end
    
    describe '#render_game_state' do
      it 'renders state as HTML' do
        state = {
          status: 'playing',
          top_card: red_5,
          current_player: 'Alice'
        }
        result = renderer.render_game_state(state)
        expect(result).to include("<div class='current-player'>Current: Alice</div>")
        expect(result).to include("<div class='top-card'>Top: <span class='uno-card red'>5</span></div>")
        expect(result).to include("<div class='status'>playing</div>")
      end
    end
    
    describe '#render_player_order' do
      it 'renders order with arrow entities' do
        players = ['Alice', 'Bob']
        result = renderer.render_player_order(players)
        expect(result).to eq("<div class='player-order'>Alice &rarr; Bob</div>")
      end
    end
  end
end