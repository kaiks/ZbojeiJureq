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

  it 'drains an already queued frame instead of clearing it to enqueue shutdown' do
    started = Queue.new
    release = Queue.new
    queued_completed = Queue.new
    dispatcher = described_class.new(capacity: 1)
    dispatcher.enqueue do
      started << true
      release.pop
    end
    started.pop
    dispatcher.enqueue { queued_completed << true }

    shutdown = Thread.new { dispatcher.shutdown(timeout: 1) }
    expect(shutdown.join(0.05)).to be_nil
    expect { queued_completed.pop(true) }.to raise_error(ThreadError)

    release << true
    shutdown.join
    expect(queued_completed.pop).to be(true)
    expect(dispatcher).to be_stopped
  ensure
    release << true if release&.empty?
    dispatcher&.shutdown
    shutdown&.join
  end
end
