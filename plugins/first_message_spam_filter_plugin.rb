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
    @new_users = {}           # Track users who just joined: {nick => time}
    @user_spam_scores = Hash.new(0)  # Accumulate spam score: {nick => score}
    @mutex = Mutex.new        # Protect shared state from Cinch's threaded dispatch
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
    # Don't track the bot itself
    return if m.user == bot

    @mutex.synchronize do
      # Track newly joined users (nick -> timestamp)
      @new_users[m.user.nick] = Time.now
      # Cleanup old entries
      cleanup_old_entries
    end
  end

  def check_first_message(m)
    # Only check channel messages
    return unless m.channel

    user_nick = m.user.nick
    should_ban = false

    @mutex.synchronize do
      # Check if this is a recently joined user
      next unless @new_users.key?(user_nick)

      # Accumulate spam score for this user based on their message
      score = matching_patterns(m.message)
      @user_spam_scores[user_nick] += score if score > 0

      # Check if accumulated score meets or exceeds threshold
      if @user_spam_scores[user_nick] >= SPAM_CONFIDENCE_THRESHOLD
        # Remove tracking immediately to prevent duplicate bans from parallel threads
        @new_users.delete(user_nick)
        @user_spam_scores.delete(user_nick)
        should_ban = true
      end
    end

    handle_spam(m) if should_ban
  end

  private

  def matching_patterns(message)
    SPAM_PATTERNS.count { |pattern| message.match?(pattern) }
  end

  def handle_spam(m)
    user = m.user
    channel = m.channel
    message = m.message

    # Log the action
    puts "🚨 SPAM DETECTED from #{user.nick} (#{user.mask}): #{message[0..150]}..."

    # Ban the user via Cinch Channel method
    user_mask = generate_ban_mask(user)
    begin
      channel.ban(user_mask)
      puts "✓ Banned #{user_mask} from #{channel}"
    rescue => e
      puts "⚠️  Error banning user: #{e.message}"
    end

    # Kick the user (after ban to prevent immediate rejoin)
    begin
      channel.kick(user, "Spam detected (automated ban)")
    rescue => e
      puts "⚠️  Error kicking user #{user.nick}: #{e.message}"
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
    # NOTE: called from within @mutex.synchronize in track_join
    now = Time.now
    expired = @new_users.select { |_nick, time| (now - time) > TRACKING_TIMEOUT }.keys
    expired.each do |nick|
      @new_users.delete(nick)
      @user_spam_scores.delete(nick)
    end
  end
end
