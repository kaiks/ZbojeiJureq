module Cinch
  class Message
    REPLY_DELAY = 2
    MAX_LENGTH = 450
    MAX_SLICES = 5

    def safe_reply(response)
      if response.is_a? Array
        response.each { |line| slow_reply line; sleep(REPLY_DELAY) }
        return
      end

      slices = response.to_s.chars.each_slice(MAX_LENGTH).map(&:join)
      slices.each_with_index do |slice, i|
        reply slice
        sleep(REPLY_DELAY)
        return (reply '(...) - message cut off due to excess length') if i == 4
      end
    end
  end
end