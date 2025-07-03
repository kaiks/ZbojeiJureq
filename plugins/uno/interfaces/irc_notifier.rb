require_relative 'notifier'

module Uno
  # IRC implementation of the Notifier interface
  class IrcNotifier
    include Notifier
    
    def initialize(irc_bot, channel)
      @irc = irc_bot
      @channel = channel
    end
    
    def notify_game(message)
      @irc.Channel(@channel).send(message)
    end
    
    def notify_player(player_id, message)
      @irc.User(player_id).notice(message)
    end
    
    def notify_error(player_id, error)
      @irc.User(player_id).notice("Error: #{error}")
    end
    
    def debug(message)
      # In production, we might not want debug messages in IRC
      # Could make this configurable
    end
  end
end