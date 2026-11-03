# frozen_string_literal: true

module UnoRules
  TRUE_VALUES = %w[1 true yes on].freeze
  FALSE_VALUES = %w[0 false no off].freeze

  module_function

  def two_player_reverse_acts_as_skip?(config: {}, env: ENV)
    raw = if env.key?('UNO_TWO_PLAYER_REVERSE_ACTS_AS_SKIP')
            env.fetch('UNO_TWO_PLAYER_REVERSE_ACTS_AS_SKIP')
          else
            config.fetch('uno_two_player_reverse_acts_as_skip', false)
          end

    return raw if raw == true || raw == false

    normalized = raw.to_s.strip.downcase
    return true if TRUE_VALUES.include?(normalized)
    return false if FALSE_VALUES.include?(normalized)

    raise ArgumentError,
          "uno_two_player_reverse_acts_as_skip must be true or false, got #{raw.inspect}"
  end
end
