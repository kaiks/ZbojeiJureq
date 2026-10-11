require 'spec_helper'
require 'cinch'
require 'stringio'
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

  FakeUser = Struct.new(:nick, :mask)
  FakeIdentUser = Struct.new(:nick, :mask, :user)
  FakeAuthUser = Struct.new(:nick, :mask, :authorized?)
  FakeMessage = Struct.new(:user, :channel, :message)
  FakeBot = Struct.new(:nick)

  class FakeChannel
    attr_reader :name, :bans, :kicks

    def initialize(name)
      @name = name
      @bans = []
      @kicks = []
    end

    def ban(mask)
      @bans << mask
    end

    def kick(user, reason)
      @kicks << [user.nick, reason]
    end

    def to_s
      name
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

      detected = detector.spam_detected?('#kx', user_key, SPAM_TRANSCRIPT[1], at: expired_time)

      expect(detected).to be(false)
    end

    it 'stops scanning after the configured first-message window' do
      short_window = described_class.new(clock: -> { current_time }, max_messages: 3)
      short_window.track_join('#kx', user_key, at: current_time)

      3.times do
        expect(short_window.spam_detected?('#kx', user_key, 'hello there', at: current_time)).to be(false)
      end

      expect(short_window.spam_detected?('#kx', user_key, SPAM_TRANSCRIPT[1], at: current_time)).to be(false)
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

  describe '#track_join and #check_first_message' do
    let(:current_time) { Time.utc(2026, 5, 4, 12, 0, 0) }
    let(:plugin) { described_class.allocate }
    let(:log_io) { StringIO.new }
    let(:channel) { FakeChannel.new('#kx') }
    let(:user) { FakeUser.new('advisorybirdMar', 'advisorybirdMar!spam@vpn.example') }

    before do
      plugin.instance_variable_set(:@bot, FakeBot.new('ZbojeiJureq'))
      plugin.instance_variable_set(:@detector, described_class::DetectionWindow.new(clock: -> { current_time }))
      plugin.instance_variable_set(:@moderator, described_class::ChannelModerator.new(log_io: log_io))
      plugin.instance_variable_set(:@whitelist, described_class::Whitelist.new(whitelist_entries))
    end

    let(:whitelist_entries) { [] }
    let(:spam_bot) { FakeIdentUser.new('rudebovidBrenna', 'rudebovidBrenna!~rudebovid@185.192.16.54', '~rudebovid') }

    it 'bans a spam bot right on join by its nick/ident fingerprint' do
      plugin.track_join(FakeMessage.new(spam_bot, channel, nil))

      expect(channel.bans).to eq(['*!*@185.192.16.54'])
      expect(channel.kicks).to eq([['rudebovidBrenna', 'Spam detected (automated ban)']])
      expect(log_io.string).to include('[join fingerprint]')
    end

    context 'with a whitelisted user' do
      let(:whitelist_entries) { ['rudebovidBrenna'] }

      it 'does not ban on join or on spam-looking messages' do
        plugin.track_join(FakeMessage.new(spam_bot, channel, nil))
        SPAM_TRANSCRIPT.each { |line| plugin.check_first_message(FakeMessage.new(spam_bot, channel, line)) }

        expect(channel.bans).to be_empty
        expect(channel.kicks).to be_empty
      end
    end

    it 'skips users with an access level in the bot database' do
      trusted = FakeAuthUser.new('advisorybirdMar', 'advisorybirdMar!spam@vpn.example', true)
      plugin.track_join(FakeMessage.new(trusted, channel, nil))
      plugin.check_first_message(FakeMessage.new(trusted, channel, JOIN_RACE_MESSAGE))

      expect(channel.bans).to be_empty
    end

    it 'bans and kicks the sample spammer once enough signals accumulate' do
      plugin.track_join(FakeMessage.new(user, channel, nil))

      SPAM_TRANSCRIPT.each do |line|
        plugin.check_first_message(FakeMessage.new(user, channel, line))
        break unless channel.bans.empty?
      end

      expect(channel.bans).to eq(['*!*@vpn.example'])
      expect(channel.kicks).to eq([['advisorybirdMar', 'Spam detected (automated ban)']])
      expect(log_io.string).to include('SPAM DETECTED from advisorybirdMar')
    end

    it 'still bans when the first message arrives before join tracking completes' do
      plugin.check_first_message(FakeMessage.new(user, channel, JOIN_RACE_MESSAGE))

      expect(channel.bans).to eq(['*!*@vpn.example'])
      expect(channel.kicks).to eq([['advisorybirdMar', 'Spam detected (automated ban)']])
    end

    it 'does not act on the bot itself joining' do
      bot_user = FakeUser.new('ZbojeiJureq', 'ZbojeiJureq!bot@localhost')
      plugin.track_join(FakeMessage.new(bot_user, channel, nil))
      plugin.check_first_message(FakeMessage.new(bot_user, channel, SPAM_TRANSCRIPT.first))

      expect(channel.bans).to be_empty
      expect(channel.kicks).to be_empty
    end
  end
end
