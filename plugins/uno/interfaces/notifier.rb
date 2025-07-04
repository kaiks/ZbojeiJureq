module Uno
  # Interface for game notifications
  # Implementations should handle how messages are delivered to players
  module Notifier
    # Send a message to all players in the game
    def notify_game(message)
      raise NotImplementedError, "#{self.class} must implement notify_game"
    end
    
    # Send a private message to a specific player
    def notify_player(player_id, message)
      raise NotImplementedError, "#{self.class} must implement notify_player"
    end
    
    # Send an error message to a specific player
    def notify_error(player_id, error)
      raise NotImplementedError, "#{self.class} must implement notify_error"
    end
    
    # Debug output (optional to implement)
    def debug(message)
      # Default: do nothing
    end
  end
  
  # Null implementation for testing
  class NullNotifier
    include Notifier
    
    attr_reader :game_notifications, :player_notifications, :error_notifications, :debug_messages
    
    def initialize
      @game_notifications = []
      @player_notifications = []
      @error_notifications = []
      @debug_messages = []
    end
    
    def notify_game(message)
      @game_notifications << message
    end
    
    def notify_player(player_id, message)
      @player_notifications << { player_id: player_id, message: message }
    end
    
    def notify_error(player_id, error)
      @error_notifications << { player_id: player_id, error: error }
    end
    
    def debug(message)
      @debug_messages << message
    end
    
    def clear
      @game_notifications.clear
      @player_notifications.clear
      @error_notifications.clear
      @debug_messages.clear
    end
  end
  
  # Console implementation for development/debugging
  class ConsoleNotifier
    include Notifier
    
    def notify_game(message)
      puts "[GAME] #{message}"
    end
    
    def notify_player(player_id, message)
      puts "[TO #{player_id}] #{message}"
    end
    
    def notify_error(player_id, error)
      puts "[ERROR to #{player_id}] #{error}"
    end
    
    def debug(message)
      puts "[DEBUG] #{message}"
    end
  end
end