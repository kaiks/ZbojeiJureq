# frozen_string_literal: true

# FirstMessageSpamFilterPlugin
# Detects and bans users who post spam messages on their first line after joining
# Particularly targets the "Madeleine Czura" scam pattern and similar recruitment/spam

class FirstMessageSpamFilterPlugin
  include Cinch::Plugin

  listen_to :join,    method: :track_join
  listen_to :channel, method: :check_first_message

  def initialize(*args)
    super
    @new_users = {}  # Track users who just joined: {nick => time}
    @checked_users = Set.new  # Users we've already checked
  end

  # Spam patterns - detects first-message recruiter/scam spam
  SPAM_PATTERNS = [
    # Madeleine Czura pattern
    /madeleine\s+czura/i,
    
    # Generic recruiter patterns
    /just.*thought.*i'd.*leave.*my.*number/i,
    /you.*can.*reach.*me.*on/i,
    /you\s+can\s+reach/i,
    /feel.*free.*to.*contact/i,
    
    # Contact info patterns
    /linkedin\s*:/i,
    /instagram\s*:/i,
    /twitter\s*:/i,
    /telegram\s*:/i,
    /skype\s*:/i,
    /discord\s*:/i,
    /whatsapp\s*:/i,
    /email\s*:/i,
    
    # Family/personal disclosure (unusual in first message)
    /brothers?\s*:/i,
    /sisters?\s*:/i,
    /mom\s*:/i,
    /dad\s*:/i,
    
    # Address patterns
    /business.*address/i,
    /home.*address/i,
    /office.*address/i,
    /street.*address/i,
    
    # Common scam phone patterns
    /\+44-?7\d{9,10}/,  # UK phone
    /\+\d{1,3}-?\d{7,11}/,  # Generic international
    
    # Email patterns (unusual as first message)
    /\S+@\S+\.com/i,
    /\S+@\S+\.co\.uk/i,
    
    # Address keywords
    /\d+\s+[a-z].*road.*london/i,
    /comrie.*southampton.*road/i,
  ].freeze

  # If a message matches this many patterns, it's considered spam
  SPAM_CONFIDENCE_THRESHOLD = 2

  # Clean up old tracking entries after this many seconds
  TRACKING_TIMEOUT = 3600  # 1 hour

  def track_join(m)
    # Only track in channels (not private messages)
    return unless m.channel

    # Track newly joined users (nick -> timestamp)
    @new_users[m.user.nick] = Time.now
    
    # Cleanup old entries
    cleanup_old_entries
  end

  def check_first_message(m)
    # Only check channel messages
    return unless m.channel

    user_nick = m.user.nick

    # Check if this is a newly joined user
    return unless @new_users.key?(user_nick)

    # Skip if we already checked this user
    return if @checked_users.include?(user_nick)

    # Mark as checked
    @checked_users.add(user_nick)

    # Remove from new users list
    @new_users.delete(user_nick)

    # Check if message matches spam patterns
    if spam_detected?(m.message)
      handle_spam(m)
    end
  end

  private

  def spam_detected?(message)
    matching_patterns = SPAM_PATTERNS.count { |pattern| message.match?(pattern) }
    matching_patterns >= SPAM_CONFIDENCE_THRESHOLD
  end

  def handle_spam(m)
    user = m.user
    channel = m.channel
    message = m.message

    # Log the action
    puts "🚨 SPAM DETECTED from #{user.nick} (#{user.mask}): #{message[0..150]}..."

    # Kick the user
    begin
      channel.kick(user, "Spam detected on first message")
    rescue => e
      puts "⚠️  Error kicking user #{user.nick}: #{e.message}"
    end

    # Ban the user via IRC MODE command
    user_mask = generate_ban_mask(user)
    begin
      @bot.send("MODE #{channel} +b #{user_mask}")
      puts "✓ Banned #{user_mask} from #{channel}"
    rescue => e
      puts "⚠️  Error banning user: #{e.message}"
    end
  end

  def generate_ban_mask(user)
    # Generate a ban mask: *!*@host
    # This bans all users from the same host
    # Format: nick!user@host
    parts = user.mask.split('@')
    if parts.length == 2
      host = parts[1]
      "*!*@#{host}"
    else
      # Fallback: ban by nick
      user.mask
    end
  end

  def cleanup_old_entries
    # Remove entries older than TRACKING_TIMEOUT
    now = Time.now
    @new_users.each do |nick, time|
      @new_users.delete(nick) if (now - time) > TRACKING_TIMEOUT
    end
  end
end
