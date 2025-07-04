module Uno
  # Interface for player identity management
  # Allows different identity providers (IRC, web, CLI, etc.)
  module PlayerIdentity
    # Get the unique identifier for this player
    def id
      raise NotImplementedError, "#{self.class} must implement id"
    end

    # Get the display name for this player
    def display_name
      raise NotImplementedError, "#{self.class} must implement display_name"
    end

    # Check if this identity matches another
    def matches?(other)
      raise NotImplementedError, "#{self.class} must implement matches?"
    end

    # String representation for display
    def to_s
      display_name
    end

    # Update the display name (optional - not all identity types support this)
    def update_display_name(new_name)
      # Default implementation - do nothing
      # Subclasses can override if they support name updates
    end
  end

  # IRC-based player identity using nicks
  class IrcIdentity
    include PlayerIdentity

    attr_reader :nick

    def initialize(nick)
      @nick = nick
    end

    def id
      @nick
    end

    def display_name
      @nick
    end

    def matches?(other)
      case other
      when IrcIdentity
        @nick == other.display_name
      when String
        @nick == other
      else
        false
      end
    end

    def update_display_name(new_name)
      @nick = new_name
    end
  end

  # Simple string-based identity for testing/CLI
  class SimpleIdentity
    include PlayerIdentity

    attr_reader :name

    def initialize(name)
      @name = name
    end

    def id
      @name
    end

    def display_name
      @name
    end

    def matches?(other)
      case other
      when SimpleIdentity
        @name == other.name
      when String
        @name == other
      else
        false
      end
    end
  end

  # UUID-based identity for web/API usage
  class UuidIdentity
    include PlayerIdentity

    attr_reader :uuid, :name

    def initialize(uuid, name = nil)
      @uuid = uuid
      @name = name || "Player-#{uuid[0..7]}"
    end

    def id
      @uuid
    end

    def display_name
      @name
    end

    def matches?(other)
      case other
      when UuidIdentity
        @uuid == other.uuid
      when String
        @uuid == other
      else
        false
      end
    end

    def update_display_name(new_name)
      @name = new_name
    end
  end
end
