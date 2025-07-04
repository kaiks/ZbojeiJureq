module Uno
  # Interface for rendering game elements
  # Implementations handle how cards and game state are displayed
  module Renderer
    # Render a single card
    def render_card(card)
      raise NotImplementedError, "#{self.class} must implement render_card"
    end
    
    # Render a hand of cards
    def render_hand(cards)
      raise NotImplementedError, "#{self.class} must implement render_hand"
    end
    
    # Render the current game state
    def render_game_state(state)
      raise NotImplementedError, "#{self.class} must implement render_game_state"
    end
    
    # Render player order
    def render_player_order(players)
      raise NotImplementedError, "#{self.class} must implement render_player_order"
    end
  end
  
  # Plain text renderer
  class TextRenderer
    include Renderer
    
    def render_card(card)
      card.to_s
    end
    
    def render_hand(cards)
      cards.map { |card| render_card(card) }.join(' ')
    end
    
    def render_game_state(state)
      "Game state: #{state[:status]} | Top card: #{render_card(state[:top_card])} | Current player: #{state[:current_player]}"
    end
    
    def render_player_order(players)
      "Player order: #{players.join(' -> ')}"
    end
  end
  
  # IRC color-coded renderer
  class IrcRenderer
    include Renderer
    
    def render_card(card)
      "#{3.chr}#{color_code(card.color)}[#{card.normalize_figure.to_s.upcase}]"
    end
    
    def render_hand(cards)
      cards.map { |card| render_card(card) }.join(' ')
    end
    
    def render_game_state(state)
      "#{state[:current_player]}'s turn. Top card: #{render_card(state[:top_card])}"
    end
    
    def render_player_order(players)
      "Current order: #{players.join(' ')}"
    end
    
    private
    
    def color_code(color)
      case color
      when :green then 3
      when :red then 4
      when :yellow then 7
      when :blue then 12
      when :wild then 13
      else 13
      end
    end
  end
  
  # HTML renderer (for potential web interface)
  class HtmlRenderer
    include Renderer
    
    def render_card(card)
      color_class = card.color.to_s
      figure = card.normalize_figure.to_s.upcase
      "<span class='uno-card #{color_class}'>#{figure}</span>"
    end
    
    def render_hand(cards)
      cards_html = cards.map { |card| render_card(card) }.join(' ')
      "<div class='uno-hand'>#{cards_html}</div>"
    end
    
    def render_game_state(state)
      <<~HTML
        <div class='game-state'>
          <div class='current-player'>Current: #{state[:current_player]}</div>
          <div class='top-card'>Top: #{render_card(state[:top_card])}</div>
          <div class='status'>#{state[:status]}</div>
        </div>
      HTML
    end
    
    def render_player_order(players)
      "<div class='player-order'>#{players.join(' &rarr; ')}</div>"
    end
  end
end