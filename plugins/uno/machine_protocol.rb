# frozen_string_literal: true

require 'base64'
require 'json'
require 'zlib'

module UnoMachine
  # Encoding and parsing for the versioned IRC machine protocol.
  module Protocol
    NAME = 'UNO_MACHINE_V1'
    VERSION = 1
    CHUNK_BYTES = 280
    MAX_ACTION_DATA_BYTES = 384
    TOKEN = /\A[A-Za-z0-9_-]{1,64}\z/

    class ProtocolError < StandardError
      attr_reader :code

      def initialize(code, message = code)
        @code = code
        super(message)
      end
    end

    module_function

    def state_lines(game_id:, decision_id:, reason:, request:)
      payload = {
        protocol: NAME,
        protocol_version: VERSION,
        type: 'request_action',
        game_id: game_id,
        decision_id: decision_id,
        reason: reason.to_s,
        request: request
      }
      chunked_lines('STATE', game_id: game_id, decision_id: decision_id, payload: payload)
    end

    def event_lines(game_id:, decision_id:, event:, payload: {})
      body = {
        protocol: NAME,
        protocol_version: VERSION,
        type: 'event',
        event: event.to_s,
        game_id: game_id,
        decision_id: decision_id,
        payload: payload
      }
      chunked_lines(
        'EVENT', game_id: game_id, decision_id: decision_id || '-', event: event.to_s, payload: body
      )
    end

    def registered_line(game_id:, channel:)
      encoded_channel = encode_uncompressed(channel.to_s)
      "#{NAME} REGISTERED game=#{game_id} channel=#{encoded_channel}"
    end

    def ack_line(game_id:, decision_id:, action:)
      "#{NAME} ACK game=#{game_id} decision=#{decision_id} status=ok action=#{action}"
    end

    def error_line(code:, game_id: '-', decision_id: '-', retryable: false)
      safe_game_id = valid_token?(game_id) ? game_id : '-'
      safe_decision_id = valid_token?(decision_id) ? decision_id : '-'
      safe_code = code.to_s.match?(TOKEN) ? code : 'protocol_error'
      "#{NAME} ERROR game=#{safe_game_id} decision=#{safe_decision_id} " \
        "code=#{safe_code} retry=#{retryable ? 1 : 0}"
    end

    def encode_action(game_id:, decision_id:, action:)
      validate_token!(game_id, 'invalid_game_id')
      validate_token!(decision_id, 'invalid_decision_id')
      envelope = {
        protocol: NAME,
        protocol_version: VERSION,
        game_id: game_id,
        decision_id: decision_id,
        action: action
      }
      data = encode_uncompressed(JSON.generate(envelope))
      raise ProtocolError.new('action_too_large') if data.bytesize > MAX_ACTION_DATA_BYTES

      "#{NAME} ACTION game=#{game_id} decision=#{decision_id} data=#{data}"
    end

    def parse_action(line)
      match = line.to_s.match(
        /\A#{NAME} ACTION game=([^ ]+) decision=([^ ]+) data=([^ ]+)\z/
      )
      raise ProtocolError.new('malformed_action') unless match

      game_id, decision_id, data = match.captures
      validate_token!(game_id, 'invalid_game_id')
      validate_token!(decision_id, 'invalid_decision_id')
      raise ProtocolError.new('action_too_large') if data.bytesize > MAX_ACTION_DATA_BYTES

      envelope = parse_json(decode_uncompressed(data))
      validate_action_envelope!(envelope, game_id, decision_id)
      { game_id: game_id, decision_id: decision_id, action: envelope.fetch('action') }
    end

    # Primarily a client/contract helper: accepts shuffled lines and identical
    # duplicate parts, while rejecting incomplete or conflicting frames.
    def reassemble(lines)
      parsed = Array(lines).map { |line| parse_chunk(line) }
      raise ProtocolError.new('missing_chunks') if parsed.empty?

      metadata = parsed.first.slice(:kind, :game_id, :decision_id, :event, :total)
      unless parsed.all? { |part| part.slice(:kind, :game_id, :decision_id, :event, :total) == metadata }
        raise ProtocolError.new('mixed_chunks')
      end

      by_part = {}
      parsed.each do |part|
        if by_part.key?(part[:part]) && by_part[part[:part]] != part[:data]
          raise ProtocolError.new('conflicting_chunk')
        end
        by_part[part[:part]] = part[:data]
      end
      expected_parts = (1..metadata.fetch(:total)).to_a
      raise ProtocolError.new('missing_chunks') unless by_part.keys.sort == expected_parts

      payload = parse_json(inflate(decode_uncompressed(expected_parts.map { |part| by_part.fetch(part) }.join)))
      validate_reassembled_payload!(payload, metadata)
      payload
    rescue Zlib::Error
      raise ProtocolError.new('corrupt_payload')
    end

    def valid_token?(value)
      value.to_s == '-' || value.to_s.match?(TOKEN)
    end

    def chunked_lines(kind, game_id:, decision_id:, payload:, event: nil)
      validate_token!(game_id, 'invalid_game_id')
      validate_token!(decision_id, 'invalid_decision_id') unless decision_id == '-'
      validate_token!(event, 'invalid_event') if event
      data = encode_uncompressed(Zlib::Deflate.deflate(JSON.generate(payload)))
      chunks = data.scan(/.{1,#{CHUNK_BYTES}}/)
      chunks.each_with_index.map do |chunk, index|
        fields = [NAME, kind, "game=#{game_id}", "decision=#{decision_id}"]
        fields << "event=#{event}" if event
        fields << "part=#{index + 1}/#{chunks.length}"
        fields << "data=#{chunk}"
        fields.join(' ')
      end
    end
    private_class_method :chunked_lines

    def parse_chunk(line)
      match = line.to_s.match(
        /\A#{NAME} (STATE|EVENT) game=([^ ]+) decision=([^ ]+) (?:event=([^ ]+) )?part=(\d+)\/(\d+) data=([^ ]+)\z/
      )
      raise ProtocolError.new('malformed_chunk') unless match

      kind, game_id, decision_id, event, part, total, data = match.captures
      validate_token!(game_id, 'invalid_game_id')
      validate_token!(decision_id, 'invalid_decision_id') unless decision_id == '-'
      validate_token!(event, 'invalid_event') if event
      raise ProtocolError.new('malformed_chunk') if kind == 'EVENT' && event.nil?
      raise ProtocolError.new('malformed_chunk') if kind == 'STATE' && event

      part = Integer(part, 10)
      total = Integer(total, 10)
      raise ProtocolError.new('invalid_part') if total < 1 || part < 1 || part > total

      {
        kind: kind,
        game_id: game_id,
        decision_id: decision_id,
        event: event,
        part: part,
        total: total,
        data: data
      }
    rescue ArgumentError
      raise ProtocolError.new('invalid_part')
    end
    private_class_method :parse_chunk

    def validate_reassembled_payload!(payload, metadata)
      unless payload['protocol'] == NAME && payload['protocol_version'] == VERSION
        raise ProtocolError.new('unsupported_protocol')
      end
      unless payload['game_id'] == metadata[:game_id] &&
             (payload['decision_id'] || '-') == metadata[:decision_id]
        raise ProtocolError.new('correlation_mismatch')
      end
      if metadata[:kind] == 'STATE'
        raise ProtocolError.new('unexpected_frame_type') unless payload['type'] == 'request_action'
      elsif payload['type'] != 'event' || payload['event'] != metadata[:event]
        raise ProtocolError.new('correlation_mismatch')
      end
    end
    private_class_method :validate_reassembled_payload!

    def validate_action_envelope!(envelope, game_id, decision_id)
      unless envelope['protocol'] == NAME && envelope['protocol_version'] == VERSION
        raise ProtocolError.new('unsupported_protocol')
      end
      unless envelope['game_id'] == game_id && envelope['decision_id'] == decision_id
        raise ProtocolError.new('correlation_mismatch')
      end
      raise ProtocolError.new('malformed_action') unless envelope['action'].is_a?(Hash)
    end
    private_class_method :validate_action_envelope!

    def validate_token!(value, code)
      raise ProtocolError.new(code) unless value.to_s.match?(TOKEN)
    end
    private_class_method :validate_token!

    def encode_uncompressed(data)
      Base64.urlsafe_encode64(data, padding: false)
    end
    private_class_method :encode_uncompressed

    def decode_uncompressed(data)
      raise ProtocolError.new('invalid_base64') unless data.to_s.match?(/\A[A-Za-z0-9_-]+\z/)

      Base64.urlsafe_decode64(data.to_s.ljust((data.to_s.length + 3) / 4 * 4, '='))
    rescue ArgumentError
      raise ProtocolError.new('invalid_base64')
    end
    private_class_method :decode_uncompressed

    def inflate(data)
      Zlib::Inflate.inflate(data)
    end
    private_class_method :inflate

    def parse_json(data)
      parsed = JSON.parse(data)
      raise ProtocolError.new('malformed_json') unless parsed.is_a?(Hash)

      parsed
    rescue JSON::ParserError
      raise ProtocolError.new('malformed_json')
    end
    private_class_method :parse_json
  end
end
