require 'spec_helper'
require 'cinch'
require 'stringio'
require_relative '../../extensions/authentication'
require_relative '../../plugins/first_message_spam_filter_plugin'

RSpec.describe FirstMessageSpamFilterPlugin do
  SPAM_TRANSCRIPT = [
    "Hi Guys! It's Madeleine Czura! Just thought I'd leave my number here in case you're lonely ;) .",
    'You can reach me on +44-7599248843 or maddyczura@gmail.com or madeleine.czura@arcadis.com anytime!',
    'Linkedin: uk.linkedin.com/in/maddy-czura',
    'Instagram: instagram.com/maddy_czura',
    'Brothers:  Benjamin V Czura(Ben), Timothy P Czura(Tim), Greg Czura',
    'Sisters: Eleanor Lousie Czura, Josie Czura',
    'Mom: Lucy P Czura',
    'Dad: Peter Christopher Czura',
    'Dad Emails: peter.czura@ntlworld.com, peter.czura@corrigenda.co.uk',
    'Business Address: Top Floor, 164 Plashet Road, London, United Kingdom, E13 0QT',
    'Home Address:  Comrie, 8 Southampton Road, Fareham, Hampshire, United Kingdom, PO16 7DY'
  ].freeze

  JOIN_RACE_MESSAGE = "Hi Guys! It's Madeleine Czura! Just thought I'd leave my number here in case you're lonely ;) . You can reach me on +44-7599248843 or maddyczura@gmail.com or madeleine.czura@arcadis.com anytime! > Linkedin: uk.linkedin.com/in/maddy-czura Instagram: instagram.com/maddy_czura".freeze

  class SpamFilterBot < Cinch::Bot
    def db
      config.shared[:database]
    end
  end

  # Only the network boundary is replaced; messages, users, channels,
  # authentication and moderation use the real Cinch implementation.
  class SpamFilterWire
    attr_reader :commands, :isupport, :network

    def initialize
      @commands = []
      @isupport = Cinch::ISupport.new
      @network = Cinch::Network.new(:unknown, :unknown)
    end

    def send(command)
      @commands << command
    end
  end

  describe FirstMessageSpamFilterPlugin::SpamSignals do
    it 'extracts distinct spam categories from the sample transcript' do
      first_line = described_class.for(SPAM_TRANSCRIPT.first)
      second_line = described_class.for(SPAM_TRANSCRIPT[1])
      family_line = described_class.for(SPAM_TRANSCRIPT[4])
      address_line = described_class.for(SPAM_TRANSCRIPT[9])

      expect(first_line).to include(:target_name, :recruiter_pitch)
      expect(second_line).to include(:recruiter_pitch, :contact_detail)
      expect(family_line).to include(:relative_dump)
      expect(address_line).to include(:address_dump)
    end
  end

  describe FirstMessageSpamFilterPlugin::DetectionWindow do
    let(:current_time) { Time.utc(2026, 5, 4, 12, 0, 0) }
    let(:detector) { described_class.new(clock: -> { current_time }) }
    let(:user_key) { 'advisorybirdMar!spam@vpn.example' }

    it 'flags the provided spam burst after the user joins' do
      detector.track_join('#kx', user_key, at: current_time)

      detected = SPAM_TRANSCRIPT.any? do |line|
        detector.spam_detected?('#kx', user_key, line, at: current_time)
      end

      expect(detected).to be(true)
    end

    it 'still flags a suspicious first message if the join callback loses the race' do
      detected = detector.spam_detected?('#kx', user_key, JOIN_RACE_MESSAGE, at: current_time)

      expect(detected).to be(true)
    end

    it 'tracks joins per channel instead of by nick alone' do
      detector.track_join('#other', user_key, at: current_time)
      expect(detector.spam_detected?('#other', user_key, SPAM_TRANSCRIPT[1], at: current_time)).to be(false)

      detected = detector.spam_detected?('#kx', user_key, SPAM_TRANSCRIPT[4], at: current_time)

      expect(detected).to be(false)
    end

    it 'expires stale tracking during message processing' do
      detector.track_join('#kx', user_key, at: current_time)
      expired_time = current_time + FirstMessageSpamFilterPlugin::TRACKING_TIMEOUT + 1

      expect(detector.spam_detected?('#kx', user_key, JOIN_RACE_MESSAGE, at: expired_time)).to be(false)
      expect(detector.spam_detected?('#kx', user_key, JOIN_RACE_MESSAGE, at: expired_time + 3600)).to be(false)
    end

    it 'stops scanning after the configured first-message window' do
      short_window = described_class.new(clock: -> { current_time }, max_messages: 3)
      short_window.track_join('#kx', user_key, at: current_time)

      3.times do
        expect(short_window.spam_detected?('#kx', user_key, 'hello there', at: current_time)).to be(false)
      end

      SPAM_TRANSCRIPT.each do |line|
        expect(short_window.spam_detected?('#kx', user_key, line, at: current_time)).to be(false)
      end
    end

    it 'starts a fresh scan when the user rejoins after the window closes' do
      detector.track_join('#kx', user_key, at: current_time)
      detector.spam_detected?('#kx', user_key, JOIN_RACE_MESSAGE, at: current_time)

      detector.track_join('#kx', user_key, at: current_time + 1)

      expect(detector.spam_detected?('#kx', user_key, JOIN_RACE_MESSAGE, at: current_time + 1)).to be(true)
    end

    it 'preserves provisional signals when the join callback arrives late' do
      expect(detector.spam_detected?('#kx', user_key, SPAM_TRANSCRIPT[1], at: current_time)).to be(false)
      detector.track_join('#kx', user_key, at: current_time)

      expect(detector.spam_detected?('#kx', user_key, SPAM_TRANSCRIPT[4], at: current_time)).to be(true)
    end

    it 'does not reopen a detected provisional window when the join callback arrives late' do
      expect(detector.spam_detected?('#kx', user_key, JOIN_RACE_MESSAGE, at: current_time)).to be(true)
      detector.track_join('#kx', user_key, at: current_time)

      expect(detector.spam_detected?('#kx', user_key, JOIN_RACE_MESSAGE, at: current_time)).to be(false)
    end

    it 'bans on the first spam line when the target name comes with another signal' do
      detector.track_join('#kx', user_key, at: current_time)

      expect(detector.spam_detected?('#kx', user_key, SPAM_TRANSCRIPT.first, at: current_time)).to be(true)
    end

    it 'does not ban someone who only mentions the target name' do
      detector.track_join('#kx', user_key, at: current_time)

      expect(detector.spam_detected?('#kx', user_key, 'znowu ten spam o madeleine czura', at: current_time)).to be(false)
    end
  end

  describe FirstMessageSpamFilterPlugin::JoinFingerprint do
    it 'matches the spam bot joins from the log' do
      expect(described_class.suspicious?('persistentlizar', '~persisten')).to be(true)
      expect(described_class.suspicious?('rudebovidBrenna', '~rudebovid')).to be(true)
      expect(described_class.suspicious?('sovietcobraElbe', '~sovietcob')).to be(true)
    end

    it 'ignores regular users' do
      expect(described_class.suspicious?('Osk-', '~dsaf')).to be(false)
      expect(described_class.suspicious?('kowalskijan', '~kowalskij')).to be(false)
      expect(described_class.suspicious?('kowalskijanwroc', 'kowalskij')).to be(false)
      expect(described_class.suspicious?('kowalskijanwroc', '~other')).to be(false)
    end
  end

  describe FirstMessageSpamFilterPlugin::Whitelist do
    it 'matches plain nicks case-insensitively' do
      whitelist = described_class.new(['Osk-'])

      expect(whitelist.include?('osk-', 'osk-!~dsaf@80.94.23.248')).to be(true)
      expect(whitelist.include?('rudebovidBrenna', 'rudebovidBrenna!~rudebovid@185.192.16.54')).to be(false)
    end

    it 'matches nick!ident@host masks with wildcards' do
      whitelist = described_class.new('*!*@*.users.quakenet.org, *!~dsaf@*')

      expect(whitelist.include?('someone', 'someone!~x@kaiks.users.quakenet.org')).to be(true)
      expect(whitelist.include?('Osk-', 'Osk-!~dsaf@1.2.3.4')).to be(true)
      expect(whitelist.include?('rudebovidBrenna', 'rudebovidBrenna!~rudebovid@185.192.16.54')).to be(false)
    end

    it 'prefers the environment variable over the config' do
      whitelist = described_class.from(config: { 'spam_filter_whitelist' => ['FromConfig'] },
                                       env: { 'SPAM_FILTER_WHITELIST' => 'FromEnv' })

      expect(whitelist.include?('FromEnv')).to be(true)
      expect(whitelist.include?('FromConfig')).to be(false)
    end
  end

  describe 'moderation through Cinch messages' do
    let(:current_time) { Time.utc(2026, 5, 4, 12, 0, 0) }
    let(:log_io) { StringIO.new }
    let(:wire) { SpamFilterWire.new }
    let(:bot) do
      SpamFilterBot.new { loggers.clear }.tap do |instance|
        instance.instance_variable_set(:@name, 'ZbojeiJureq')
        instance.instance_variable_set(:@irc, wire)
        instance.config.shared[:database] = database
      end
    end
    let(:database) do
      Sequel.sqlite.tap do |db|
        db.create_table(:weather) do
          String :nick, primary_key: true
          String :weather_string
        end
        db.create_table(:user) do
          primary_key :id
          Integer :matchmethod
          String :nick
          String :address
          Integer :accesslevel
        end
        db.create_table(:user_access) do
          primary_key :id
          Integer :level
        end
      end
    end
    let(:plugin) { described_class.new(bot) }
    let(:nick) { 'rudebovidBrenna' }
    let(:ident) { 'rudebovid' }
    let(:prefix) { "#{nick}!~#{ident}@185.192.16.54" }
    let(:join_message) { Cinch::Message.new(":#{prefix} JOIN :#kx", bot) }
    let(:whitelist_entries) { [] }
    let(:moderation_commands) do
      ['MODE #kx +b *!*@185.192.16.54', "KICK #kx #{nick} :Spam detected (automated ban)"]
    end

    def channel_message(text, channel: '#kx')
      Cinch::Message.new(":#{prefix} PRIVMSG #{channel} :#{text}", bot)
    end

    around do |example|
      original_stdout = $stdout
      $stdout = log_io
      example.run
    ensure
      $stdout = original_stdout
    end

    before do
      Timecop.freeze(current_time)
      stub_const('CONFIG', { 'spam_filter_whitelist' => whitelist_entries })
    end

    after do
      plugin.unregister
      database.disconnect
    end

    it 'only logs a suspicious nick/ident on join' do
      plugin.track_join(join_message)

      expect(wire.commands).to be_empty
      expect(log_io.string).to include('JOIN FINGERPRINT MATCH (dry run)')
    end

    context 'with an ordinary matching nickname' do
      let(:nick) { 'alexandermiller' }
      let(:ident) { 'alexander' }

      it 'does not ban the user for joining and greeting the channel' do
        plugin.track_join(join_message)
        plugin.check_first_message(channel_message('hello everyone'))

        expect(wire.commands).to be_empty
      end
    end

    context 'with a whitelisted user' do
      let(:whitelist_entries) { [nick] }

      it 'does not act on join or on spam-looking messages' do
        plugin.track_join(join_message)
        SPAM_TRANSCRIPT.each { |line| plugin.check_first_message(channel_message(line)) }

        expect(wire.commands).to be_empty
        expect(log_io.string).not_to include('JOIN FINGERPRINT MATCH')
      end
    end

    it 'authorizes a registered bot account before deciding whether to ban' do
      database[:user_access].insert(id: 1, level: 1)
      database[:user].insert(matchmethod: 0, nick: nick, accesslevel: 1)
      expect(join_message.user.authorized?).to be(false)

      plugin.track_join(join_message)
      plugin.check_first_message(channel_message(JOIN_RACE_MESSAGE))

      expect(wire.commands).to be_empty
      expect(join_message.user.authorized?).to be(true)
    end

    it 'trusts a saved weather registration even when the nick changes case' do
      database[:weather].insert(nick: nick.upcase, weather_string: 'Berlin')

      plugin.track_join(join_message)
      SPAM_TRANSCRIPT.each { |line| plugin.check_first_message(channel_message(line)) }

      expect(wire.commands).to be_empty
      expect(log_io.string).not_to include('JOIN FINGERPRINT MATCH')
    end

    it 'does not treat underscores in weather registrations as wildcards' do
      database[:weather].insert(nick: 'rudebovid_renna', weather_string: 'Berlin')
      plugin.track_join(join_message)
      plugin.check_first_message(channel_message(SPAM_TRANSCRIPT.first))

      expect(wire.commands).to eq(moderation_commands)
    end

    it 'trusts channel operators' do
      join_message.channel.add_user(join_message.user, ['o'])

      plugin.track_join(join_message)
      plugin.check_first_message(channel_message(JOIN_RACE_MESSAGE))

      expect(wire.commands).to be_empty
    end

    it 'bans and kicks a spammer once, starting with the first spam line' do
      plugin.track_join(join_message)
      plugin.check_first_message(channel_message(SPAM_TRANSCRIPT.first))
      expect(wire.commands).to eq(moderation_commands)

      SPAM_TRANSCRIPT.drop(1).each { |line| plugin.check_first_message(channel_message(line)) }

      expect(wire.commands).to eq(moderation_commands)
      expect(log_io.string).to include('[message signals]')
    end

    it 'still bans when the first message arrives before join tracking completes' do
      plugin.check_first_message(channel_message(JOIN_RACE_MESSAGE))
      plugin.track_join(join_message)
      plugin.check_first_message(channel_message(JOIN_RACE_MESSAGE))

      expect(wire.commands).to eq(moderation_commands)
    end

    it 'does not ban after the first-message limit is reached' do
      plugin.track_join(join_message)
      described_class::MAX_MESSAGES_TO_SCAN.times do
        plugin.check_first_message(channel_message('hello there'))
      end
      plugin.check_first_message(channel_message(JOIN_RACE_MESSAGE))

      expect(wire.commands).to be_empty
    end

    it 'does not ban after the tracking timeout has elapsed' do
      plugin.track_join(join_message)
      Timecop.travel(current_time + described_class::TRACKING_TIMEOUT + 1)
      2.times { plugin.check_first_message(channel_message(JOIN_RACE_MESSAGE)) }

      expect(wire.commands).to be_empty
    end

    it 'starts a new provisional scan after the user is kicked and rejoins' do
      plugin.track_join(join_message)
      plugin.check_first_message(channel_message(JOIN_RACE_MESSAGE))
      wire.commands.clear
      kick = Cinch::Message.new(":Operator!op@ops.example KICK #kx #{nick} :bye", bot)
      plugin.stop_tracking(kick, join_message.user)

      plugin.check_first_message(channel_message(JOIN_RACE_MESSAGE))

      expect(wire.commands).to eq(moderation_commands)
    end

    it 'clears the channel windows of a quitting user' do
      plugin.track_join(join_message)
      plugin.track_join(Cinch::Message.new(":#{prefix} JOIN :#other", bot))
      plugin.check_first_message(channel_message(JOIN_RACE_MESSAGE))
      plugin.check_first_message(channel_message(JOIN_RACE_MESSAGE, channel: '#other'))
      wire.commands.clear
      quit = Cinch::Message.new(":#{prefix} QUIT :bye", bot)
      plugin.stop_tracking(quit, join_message.user)

      plugin.check_first_message(channel_message(JOIN_RACE_MESSAGE))
      plugin.check_first_message(channel_message(JOIN_RACE_MESSAGE, channel: '#other'))

      expect(wire.commands).to eq(moderation_commands + moderation_commands.map { |command| command.sub('#kx', '#other') })
    end

    it 'clears stale scan windows when the bot disconnects' do
      plugin.track_join(join_message)
      plugin.check_first_message(channel_message(JOIN_RACE_MESSAGE))
      wire.commands.clear
      plugin.reset_tracking(nil)

      plugin.check_first_message(channel_message(JOIN_RACE_MESSAGE))

      expect(wire.commands).to eq(moderation_commands)
    end

    context 'with the bot itself joining' do
      let(:nick) { 'ZbojeiJureq' }

      it 'does not act on the bot' do
        plugin.track_join(join_message)
        plugin.check_first_message(channel_message(SPAM_TRANSCRIPT.first))

        expect(wire.commands).to be_empty
      end
    end
  end
end
