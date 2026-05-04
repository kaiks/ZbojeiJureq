# frozen_string_literal: true

require 'set'

# FirstMessageSpamFilterPlugin
# Detects and bans users who post characteristic spam bursts immediately
# after joining a channel.
class FirstMessageSpamFilterPlugin
  include Cinch::Plugin

  TRACKING_TIMEOUT = 3600
  MAX_MESSAGES_TO_SCAN = 12
  SPAM_SIGNAL_THRESHOLD = 3

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

  module SpamSignals
    module_function

    def for(message)
      SIGNAL_PATTERNS.each_with_object(Set.new) do |(signal, patterns), hits|
        hits << signal if patterns.any? { |pattern| message.match?(pattern) }
      end
    end
  end

  class DetectionWindow
    Entry = Struct.new(:joined_at, :messages_seen, :signals, keyword_init: true)

    def initialize(clock: -> { Time.now }, timeout: TRACKING_TIMEOUT, max_messages: MAX_MESSAGES_TO_SCAN, threshold: SPAM_SIGNAL_THRESHOLD)
      @clock = clock
      @timeout = timeout
      @max_messages = max_messages
      @threshold = threshold
      @entries = {}
      @mutex = Mutex.new
    end

    def track_join(channel_key, user_key, at: @clock.call)
      @mutex.synchronize do
        cleanup(at)
        @entries[[channel_key, user_key]] = Entry.new(joined_at: at, messages_seen: 0, signals: Set.new)
      end
    end

    def spam_detected?(channel_key, user_key, message, at: @clock.call)
      @mutex.synchronize do
        cleanup(at)

        key = [channel_key, user_key]
        entry = @entries[key]
        return false unless entry

        entry.messages_seen += 1
        entry.signals.merge(SpamSignals.for(message))

        detected = entry.signals.length >= @threshold
        forget(key) if detected || entry.messages_seen >= @max_messages
        detected
      end
    end

    private

    def cleanup(now)
      expired_keys = @entries.select { |_key, entry| (now - entry.joined_at) > @timeout }.keys
      expired_keys.each { |key| forget(key) }
    end

    def forget(key)
      @entries.delete(key)
    end
  end

  class ChannelModerator
    def initialize(log_io: $stdout)
      @log_io = log_io
    end

    def ban_and_kick(message)
      user = message.user
      channel = message.channel
      user_mask = generate_ban_mask(user)

      log("SPAM DETECTED from #{user.nick} (#{user.mask}): #{message.message[0..150]}...")

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

    private

    def log(text)
      @log_io.puts(text)
    end
  end

  def initialize(*args)
    super
    @detector = DetectionWindow.new
    @moderator = ChannelModerator.new
  end

  def track_join(m)
    return unless m.channel
    return if bot_user?(m.user)

    @detector.track_join(channel_key(m.channel), user_key(m.user))
  end

  def check_first_message(m)
    return unless m.channel

    detected = @detector.spam_detected?(channel_key(m.channel), user_key(m.user), m.message)
    @moderator.ban_and_kick(m) if detected
  end

  private

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
