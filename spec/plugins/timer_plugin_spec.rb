require 'spec_helper'
require 'cinch'
require 'sequel'
require_relative '../../extensions/database'
require_relative '../../plugins/timer_plugin'

RSpec.describe TimerPlugin do
  let(:plugin) { described_class.allocate }

  describe '#timer_note' do
    it 'preserves fractional durations' do
      timer_model = class_double('TimerNoteTest').as_stubbed_const
      user = instance_double('User', nick: 'Alice', msg: nil)
      channel = double('Channel', to_s: '#test')
      message = instance_double('Message', user: user, channel: channel)
      now = Time.local(2026, 7, 21, 12, 0, 0)
      Timecop.freeze(now)

      expect(timer_model).to receive(:create).with(
        trigger_time: now + 1_800,
        nick: 'Alice', channel: '#test', message: 'half an hour',
        inserted: now, status: 0
      )

      plugin.timer_note(message, '0.5', 'h', 'half an hour')
    end
  end
end
