# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../plugins/uno/machine_protocol'

RSpec.describe UnoMachine::Protocol do
  let(:request) do
    {
      type: 'request_action',
      protocol_version: 1,
      state: {
        your_id: 'Alice',
        hand: Array.new(120) { |index| "r#{index}" },
        available_actions: %w[play draw]
      }
    }
  end

  it 'round trips shuffled and identical duplicate chunks below a conservative line size' do
    lines = described_class.state_lines(
      game_id: 'g1_secret', decision_id: 'd1_secret', reason: :turn_started, request: request
    )
    shuffled = (lines.reverse + [lines.first]).shuffle(random: Random.new(4))

    expect(lines.length).to be > 1
    expect(lines.map(&:bytesize).max).to be < 420
    expect(described_class.reassemble(shuffled)).to include(
      'protocol' => 'UNO_MACHINE_V1',
      'game_id' => 'g1_secret',
      'decision_id' => 'd1_secret',
      'reason' => 'turn_started',
      'request' => JSON.parse(JSON.generate(request))
    )
  end

  it 'rejects missing, conflicting, mixed-correlation, and corrupt chunks' do
    lines = described_class.state_lines(
      game_id: 'g1_secret', decision_id: 'd1_secret', reason: :turn_started, request: request
    )

    expect { described_class.reassemble(lines.drop(1)) }
      .to raise_error(UnoMachine::Protocol::ProtocolError) { |error| expect(error.code).to eq('missing_chunks') }

    conflicting = lines + [lines.first.sub(/data=./, 'data=X')]
    expect { described_class.reassemble(conflicting) }
      .to raise_error(UnoMachine::Protocol::ProtocolError) { |error| expect(error.code).to eq('conflicting_chunk') }

    mixed = lines.dup
    mixed[-1] = mixed[-1].sub('game=g1_secret', 'game=g2_secret')
    expect { described_class.reassemble(mixed) }
      .to raise_error(UnoMachine::Protocol::ProtocolError) { |error| expect(error.code).to eq('mixed_chunks') }

    corrupt = lines.map { |line| line.sub(/data=./, 'data=A') }
    expect { described_class.reassemble(corrupt) }
      .to raise_error(UnoMachine::Protocol::ProtocolError) { |error| expect(error.code).to eq('corrupt_payload') }
  end

  it 'round trips a correlated canonical action envelope' do
    line = described_class.encode_action(
      game_id: 'g1_secret',
      decision_id: 'd1_secret',
      action: { action: 'play', card: 'wd4', wild_color: 'red', double_play: true }
    )

    expect(described_class.parse_action(line)).to eq(
      game_id: 'g1_secret',
      decision_id: 'd1_secret',
      action: {
        'action' => 'play', 'card' => 'wd4', 'wild_color' => 'red', 'double_play' => true
      }
    )
  end

  it 'rejects malformed, oversized, corrupt, and correlation-mismatched actions' do
    expect { described_class.parse_action('UNO_MACHINE_V1 ACTION nope') }
      .to raise_error(UnoMachine::Protocol::ProtocolError) { |error| expect(error.code).to eq('malformed_action') }

    oversized = 'A' * (described_class::MAX_ACTION_DATA_BYTES + 1)
    expect do
      described_class.parse_action("UNO_MACHINE_V1 ACTION game=g1 decision=d1 data=#{oversized}")
    end.to raise_error(UnoMachine::Protocol::ProtocolError) { |error| expect(error.code).to eq('action_too_large') }

    expect do
      described_class.parse_action('UNO_MACHINE_V1 ACTION game=g1 decision=d1 data=not_json')
    end.to raise_error(UnoMachine::Protocol::ProtocolError)

    line = described_class.encode_action(game_id: 'g1', decision_id: 'd1', action: { action: 'draw' })
    mismatched = line.sub('decision=d1', 'decision=d2')
    expect { described_class.parse_action(mismatched) }
      .to raise_error(UnoMachine::Protocol::ProtocolError) { |error| expect(error.code).to eq('correlation_mismatch') }
  end

  it 'round trips correlated terminal event frames' do
    lines = described_class.event_lines(
      game_id: 'g1', decision_id: 'd4', event: 'game_ended', payload: { winner: 'Alice' }
    )

    expect(described_class.reassemble(lines)).to include(
      'type' => 'event', 'event' => 'game_ended', 'game_id' => 'g1', 'decision_id' => 'd4'
    )

    expect do
      described_class.event_lines(game_id: 'g1', decision_id: 'd4', event: 'bad event')
    end.to raise_error(UnoMachine::Protocol::ProtocolError) { |error| expect(error.code).to eq('invalid_event') }
  end
end
