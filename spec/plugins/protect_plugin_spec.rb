require 'spec_helper'
require 'cinch'
require_relative '../../plugins/protect_plugin'

RSpec.describe ProtectPlugin do
  let(:plugin) { described_class.allocate }

  it 'has an implementation for every registered handler' do
    targets = described_class.matchers.map(&:method) + described_class.listeners.map(&:method)
    expect(targets).to all(satisfy { |target| described_class.instance_methods.include?(target) })
  end

  describe 'voice commands' do
    let(:channel) { instance_double('Channel') }
    let(:user) { instance_double('User', has_admin_access?: false) }
    let(:message) { instance_double('Message', user: user, channel: channel) }

    it 'does not voice another user for a non-admin' do
      expect(channel).not_to receive(:voice)

      plugin.voice_user(message, 'Alice')
    end

    it 'voices another user for an admin' do
      user = instance_double('User', has_admin_access?: true)
      target = instance_double('TargetUser')
      allow(message).to receive(:user).and_return(user)
      allow(channel).to receive(:get_user).with('Alice').and_return(target)
      expect(channel).to receive(:voice).with(target)

      plugin.voice_user(message, 'Alice')
    end
  end

  describe '#reop' do
    it 'restores op only for users configured to have it' do
      channel = instance_double('Channel')
      message = instance_double('Message', channel: channel)
      user = instance_double('User', op?: true)
      expect(channel).to receive(:op).with(user)

      plugin.reop(message, user)
    end
  end

  describe '#unban_protected_user' do
    it 'removes a ban that matches an authorized user' do
      protected_user = instance_double('User', authorized?: true)
      channel = instance_double('Channel', users: { protected_user => [] })
      message = instance_double('Message', channel: channel)
      ban = instance_double('Ban', match: true, mask: '*!*@example.test')
      expect(channel).to receive(:unban).with('*!*@example.test')

      plugin.unban_protected_user(message, ban)
    end
  end
end
