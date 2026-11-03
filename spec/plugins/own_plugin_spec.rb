require 'spec_helper'
require 'cinch'
require 'sequel'
require_relative '../../extensions/database'
require_relative '../../plugins/own_plugin'

RSpec.describe OwnPlugin do
  let(:database) do
    Sequel.sqlite.tap do |db|
      db.create_table(:own) do
        primary_key :id
        String :nick, unique: true
        String :last_owned_by
        String :last_owned_time
        Integer :own_stage
        Integer :owned_times, null: false, default: 0
        Integer :owning_times, null: false, default: 0
      end
    end
  end
  let(:record_class) do
    Class.new(Sequel::Model(database[:own])) do
      def time
        return Time.at(0) if last_owned_time.nil? || last_owned_time.empty?

        Time.parse(last_owned_time)
      rescue ArgumentError
        Time.at(0)
      end
    end
  end
  let(:plugin) { described_class.allocate }
  let(:user) { instance_double('User', nick: 'Alice', level: 1) }
  let(:target) { instance_double('TargetUser') }
  let(:channel) { instance_double('Channel', get_user: target, kick: nil) }
  let(:message) { instance_double('Message', user: user, channel: channel, reply: nil) }

  before do
    stub_const('OwnRecord', record_class)
  end

  after do
    database.disconnect
  end

  it 'credits the owner and victim separately' do
    plugin.own(message, 'Bob')

    expect(record_class[nick: 'Alice'].owning_times).to eq(1)
    expect(record_class[nick: 'Alice'].owned_times).to eq(0)
    expect(record_class[nick: 'Bob'].owning_times).to eq(0)
    expect(record_class[nick: 'Bob'].owned_times).to eq(1)
  end

  it 'rejects a repeated own during the cooldown without violating uniqueness' do
    plugin.own(message, 'Bob')

    expect { plugin.own(message, 'Bob') }.not_to raise_error
    expect(record_class[nick: 'Alice'].owning_times).to eq(1)
    expect(record_class[nick: 'Bob'].owned_times).to eq(1)
  end

  it 'handles unowning a user with no record' do
    expect(message).to receive(:reply).with('Nobody is not currently owned.')

    expect { plugin.unown(message, 'Nobody') }.not_to raise_error
  end
end
