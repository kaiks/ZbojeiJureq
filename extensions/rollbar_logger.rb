require "cinch/logger"


module Cinch
  class Logger
    class RollbarLogger < Logger
      def exception(e)
        Rollbar.error(e)
      end
    end
  end
end