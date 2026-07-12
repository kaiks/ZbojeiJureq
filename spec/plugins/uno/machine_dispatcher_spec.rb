# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../plugins/uno/machine_dispatcher'

RSpec.describe UnoMachine::Dispatcher do
  it 'does not block producers when its bounded queue is full' do
    started = Queue.new
    release = Queue.new
    dispatcher = described_class.new(capacity: 1)
    dispatcher.enqueue do
      started << true
      release.pop
    end
    started.pop
    expect(dispatcher.enqueue {}).to be(true)

    began_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    expect(dispatcher.enqueue {}).to be(false)
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - began_at

    expect(elapsed).to be < 0.05
  ensure
    release << true if release
    dispatcher&.shutdown
  end

  it 'isolates job exceptions and cleanly rejects work after shutdown' do
    errors = Queue.new
    completed = Queue.new
    dispatcher = described_class.new(error_handler: ->(error) { errors << error })
    dispatcher.enqueue { raise 'network failed' }
    dispatcher.enqueue { completed << true }

    expect(completed.pop).to be(true)
    expect(errors.pop.message).to eq('network failed')
    dispatcher.shutdown
    expect(dispatcher).to be_stopped
    expect(dispatcher.enqueue {}).to be(false)
  end
end
