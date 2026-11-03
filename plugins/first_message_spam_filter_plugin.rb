# frozen_string_literal: true

require 'set'
require 'sequel'

# FirstMessageSpamFilterPlugin
# Logs suspicious nick/ident fingerprints on JOIN and bans spam bots based
# on content signals in their first messages.
#
# Trusted users are never acted on:
# - anyone matching CONFIG['spam_filter_whitelist'] (or the comma-separated
#   SPAM_FILTER_WHITELIST environment variable, which takes precedence),
# - anyone with an access level in the bot's own user database (.add ...),
# - anyone with a saved weather registration (.w register ...),
# - channel operators.
class FirstMessageSpamFilterPlugin
  include Cinch::Plugin

  TRACKING_TIMEOUT = 3600
  MAX_MESSAGES_TO_SCAN = 12
  SPAM_SIGNAL_THRESHOLD = 3
  # A hit on any of these signals lowers the threshold to INSTANT_THRESHOLD,
  # so the first spam line is enough and the contact details never get out.
  # One signal alone is not enough, so people just talking about the spam
  # are not banned.
  INSTANT_SIGNALS = %i[target_name].freeze
  INSTANT_THRESHOLD = 2

  # What to do when a joining user matches JoinFingerprint:
  #   :ban – ban + kick immediately on JOIN
  #   :log – only log (dry run, to check for false positives)
  #   :off – disabled, rely on message filter only
  # This heuristic also matches ordinary users; collect evidence before
  # enabling bans based on nick/ident alone.
  JOIN_FINGERPRINT_ACTION = :log

  SIGNAL_PATTERNS = {
    target_name: [
      /madeleine\s+czura/i
    ],
    recruiter_pitch: [
      /just.*thought.*i['’]?d.*leave.*my.*number/i,
      /you.*can.*reach.*me.*on/i,
      /feel.*free.*to.*contact/i
    ],
    contact_detail: [
      /\+44-?7\d{9,10}/,
      /\+\d{1,3}-?\d{7,11}/,
      /\b[\w.+-]+@[\w.-]+\.[a-z]{2,}\b/i,
      %r{\b(?:uk\.)?linkedin\.com/\S+}i,
      %r{\binstagram\.com/\S+}i,
      %r{\btwitter\.com/\S+}i,
      %r{\btelegram\.me/\S+}i,
      %r{\bdiscord(?:app)?\.com/\S+}i
    ],
    relative_dump: [
      /brothers?\s*:/i,
      /sisters?\s*:/i,
      /mom\s*:/i,
      /dad\s*:/i
    ],
    address_dump: [
      /\b(?:business|home|office|street)\s+address\s*:/i,
      /\b\d+\s+[[:alpha:]].*\b(?:road|street|avenue|lane)\b/i
    ]
  }.freeze

  listen_to :join,    method: :track_join
  listen_to :channel, method: :check_first_message
  listen_to :leaving, method: :stop_tracking
  listen_to :disconnect, method: :reset_tracking

  module SpamSignals
    module_function

    def for(message)
      SIGNAL_PATTERNS.each_with_object(Set.new) do |(signal, patterns), hits|
        hits << signal if patterns.any? { |pattern| message.match?(pattern) }
      end
    end
  end

  # Fingerprint of the spam bot's JOIN, e.g.:
  #   persistentlizar (~persisten@193.36.223.15)
  #   rudebovidBrenna (~rudebovid@185.192.16.54)
  #   sovietcobraElbe (~sovietcob@185.223.152.213)
  # - nick: lowercase words + optional Capitalized name, cut to exactly
  #   the network's max nick length (15 on QuakeNet)
  # - ident: no identd (~), and it is just the first chars of the nick
  # IPs rotate, so the host is ignored.
  module JoinFingerprint
    module_function

    NICK_LENGTH = 15
    NICK_PATTERN = /\A[a-z]{6,}(?:[A-Z][a-z]*)?\z/
    MIN_IDENT_LENGTH = 8

    def suspicious?(nick, ident)
      nick = nick.to_s
      ident = ident.to_s
      return false unless ident.start_with?('~')

      ident = ident.delete_prefix('~').downcase
      nick.length == NICK_LENGTH &&
        nick.match?(NICK_PATTERN) &&
        ident.length >= MIN_IDENT_LENGTH &&
        nick.downcase.start_with?(ident)
    end
  end

  # Entries are either a plain nick ("Osk-") or a nick!ident@host mask with
  # * and ? wildcards ("*!~dsaf@*", "*!*@*.users.quakenet.org").
  # Matching is case-insensitive.
  class Whitelist
    CONFIG_KEY = 'spam_filter_whitelist'
    ENV_KEY = 'SPAM_FILTER_WHITELIST'

    def self.from(config: {}, env: ENV)
      raw = env.key?(ENV_KEY) ? env.fetch(ENV_KEY) : config.fetch(CONFIG_KEY, [])
      new(raw)
    end

    def initialize(entries)
      values = entries.is_a?(String) ? entries.split(',') : Array(entries)
      values = values.map { |entry| entry.to_s.strip }.reject(&:empty?)
      @nicks = values.reject { |entry| mask?(entry) }.map(&:downcase).to_set.freeze
      @masks = values.select { |entry| mask?(entry) }.map { |entry| glob_to_regexp(entry) }.freeze
    end

    def include?(nick, mask = nil)
      return true if @nicks.include?(nick.to_s.downcase)

      mask = mask.to_s
      !mask.empty? && @masks.any? { |pattern| mask.match?(pattern) }
    end

    def empty?
      @nicks.empty? && @masks.empty?
    end

    private

    def mask?(entry)
      entry.include?('!') || entry.include?('@')
    end

    def glob_to_regexp(glob)
      body = Regexp.escape(glob).gsub('\*', '.*').gsub('\?', '.')
      Regexp.new("\\A#{body}\\z", Regexp::IGNORECASE)
    end
  end

  class DetectionWindow
    Entry = Struct.new(:joined_at, :messages_seen, :signals, :provisional, :closed, keyword_init: true)

    def initialize(clock: -> { Time.now }, timeout: TRACKING_TIMEOUT, max_messages: MAX_MESSAGES_TO_SCAN,
                   threshold: SPAM_SIGNAL_THRESHOLD, instant_signals: INSTANT_SIGNALS,
                   instant_threshold: INSTANT_THRESHOLD)
      @clock = clock
      @timeout = timeout
      @max_messages = max_messages
      @threshold = threshold
      @instant_signals = Set.new(instant_signals)
      @instant_threshold = instant_threshold
      @entries = {}
      @mutex = Mutex.new
    end

    def track_join(channel_key, user_key, at: @clock.call)
      @mutex.synchronize do
        key = [channel_key, user_key]
        entry = @entries[key]
        if entry&.provisional
          # A late JOIN must not discard signals or reopen a window that
          # was already completed by the message handler.
          entry.provisional = false
        else
          @entries[key] = Entry.new(joined_at: at, messages_seen: 0, signals: Set.new)
        end
      end
    end

    def spam_detected?(channel_key, user_key, message, at: @clock.call)
      @mutex.synchronize do
        key = [channel_key, user_key]
        entry = @entries[key]
        return false if entry&.closed
        if entry && (at - entry.joined_at) > @timeout
          close(entry)
          return false
        end

        signals = SpamSignals.for(message)
        if entry.nil?
          return false if signals.empty?

          # Cinch dispatches JOIN and PRIVMSG handlers on separate
          # threads, so the first spam line can arrive before the join
          # tracker is visible. Create a provisional window from the
          # first suspicious message so the race does not drop the burst.
          entry = Entry.new(joined_at: at, messages_seen: 0, signals: Set.new, provisional: true)
          @entries[key] = entry
        end

        entry.messages_seen += 1
        entry.signals.merge(signals)

        detected = detected?(entry.signals)
        close(entry) if detected || entry.messages_seen >= @max_messages
        detected
      end
    end

    def forget_user(user_key, channel_key: nil)
      @mutex.synchronize do
        @entries.delete_if { |(channel, user), _entry| user == user_key && (channel_key.nil? || channel == channel_key) }
      end
    end

    def clear(channel_key: nil)
      @mutex.synchronize do
        if channel_key
          @entries.delete_if { |(channel, _user), _entry| channel == channel_key }
        else
          @entries.clear
        end
      end
    end

    private

    def detected?(signals)
      threshold = signals.intersect?(@instant_signals) ? @instant_threshold : @threshold
      signals.length >= threshold
    end

    def close(entry)
      # Keep a tombstone until departure/rejoin so the JOIN-race fallback
      # cannot reopen a finished or expired scan.
      entry.closed = true
      entry.signals.clear
    end
  end

  class ChannelModerator
    def initialize(log_io: $stdout)
      @log_io = log_io
    end

    def ban_and_kick(channel, user, reason:, details: nil)
      user_mask = generate_ban_mask(user)

      log("SPAM DETECTED from #{user.nick} (#{user.mask}) [#{reason}]#{details ? ": #{details}" : ''}")

      begin
        channel.ban(user_mask)
        log("Banned #{user_mask} from #{channel}")
      rescue StandardError => e
        log("Error banning user: #{e.message}")
      end

      begin
        channel.kick(user, 'Spam detected (automated ban)')
      rescue StandardError => e
        log("Error kicking user #{user.nick}: #{e.message}")
      end
    end

    def generate_ban_mask(user)
      nick_and_user, host = user.mask.to_s.split('@', 2)
      return "*!*@#{host}" if nick_and_user && host && !host.empty?

      user.mask
    end

    def log(text)
      @log_io.puts(text)
    end
  end

  def initialize(*args)
    super
    @detector = DetectionWindow.new
    @moderator = ChannelModerator.new
    @whitelist = Whitelist.from(config: defined?(CONFIG) ? CONFIG : {})
  end

  def track_join(m)
    return unless m.channel
    return if bot_user?(m.user)
    return if trusted?(m.channel, m.user)

    # Content signals are still required when the JOIN heuristic only logs.
    @detector.track_join(channel_key(m.channel), user_key(m.user))
    handle_join_fingerprint(m)
  end

  def stop_tracking(m, user)
    channel = channel_key(m.channel) if m.channel
    if bot_user?(user)
      @detector.clear(channel_key: channel)
    else
      @detector.forget_user(user_key(user), channel_key: channel)
    end
  end

  def reset_tracking(_m)
    @detector.clear
  end

  def check_first_message(m)
    return unless m.channel
    return if bot_user?(m.user)
    return if trusted?(m.channel, m.user)

    detected = @detector.spam_detected?(channel_key(m.channel), user_key(m.user), m.message)
    return unless detected

    @moderator.ban_and_kick(m.channel, m.user, reason: 'message signals', details: "#{m.message[0..150]}...")
  end

  private

  def handle_join_fingerprint(m)
    return if JOIN_FINGERPRINT_ACTION == :off
    return unless JoinFingerprint.suspicious?(m.user.nick, ident_of(m.user))

    if JOIN_FINGERPRINT_ACTION == :ban
      @moderator.ban_and_kick(m.channel, m.user, reason: 'join fingerprint')
    else
      @moderator.log("JOIN FINGERPRINT MATCH (dry run) #{m.user.nick} (#{m.user.mask}) on #{m.channel}")
    end
  end

  def trusted?(channel, user)
    whitelisted?(user) || weather_registered?(user) || bot_authorized?(user) || channel_op?(channel, user)
  end

  def whitelisted?(user)
    @whitelist&.include?(user.nick, user.respond_to?(:mask) ? user.mask : nil)
  end

  def weather_registered?(user)
    return false unless bot.respond_to?(:db) && bot.db

    bot.db[:weather].where(Sequel.function(:lower, :nick) => user.nick.downcase).any?
  rescue StandardError => e
    @moderator.log("Weather whitelist check failed for #{user.nick}: #{e.message}")
    false
  end

  # Users added with .add nick/ident/host in AuthenticationPlugin.
  # AuthenticationPlugin authorizes on JOIN in its own thread, so authorize
  # here too instead of relying on that having finished.
  def bot_authorized?(user)
    return false unless user.respond_to?(:authorized?)
    return true if user.authorized?

    user.authorize if user.respond_to?(:authorize)
    user.authorized?
  rescue StandardError => e
    @moderator.log("Whitelist auth check failed for #{user.nick}: #{e.message}")
    false
  end

  def channel_op?(channel, user)
    channel.respond_to?(:opped?) && channel.opped?(user)
  rescue StandardError
    false
  end

  def ident_of(user)
    user.respond_to?(:user) ? user.user : nil
  end

  def channel_key(channel)
    channel.respond_to?(:name) ? channel.name : channel.to_s
  end

  def user_key(user)
    user.respond_to?(:mask) && !user.mask.to_s.empty? ? user.mask : user.nick
  end

  def bot_user?(user)
    return false unless bot

    user == bot || (user.respond_to?(:nick) && bot.respond_to?(:nick) && user.nick == bot.nick)
  end
end
