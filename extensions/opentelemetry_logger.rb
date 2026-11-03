require 'cinch/logger'

module Cinch
  class Logger
    class OpenTelemetryLogger < Logger
      def initialize(tracer:)
        super(nil, level: :error)
        @tracer = tracer
      end

      def exception(error)
        @tracer.in_span('cinch.exception') do |span|
          span.record_exception(error)
          span.status = OpenTelemetry::Trace::Status.error(error.message)
        end
      end

      def error(message)
        record_message('error', message)
      end

      def fatal(message)
        record_message('fatal', message)
      end

      private

      def record_message(severity, message)
        text = message.to_s
        @tracer.in_span(
          "cinch.logger.#{severity}",
          attributes: {
            'log.severity' => severity.upcase,
            'log.message' => text
          }
        ) do |span|
          span.status = OpenTelemetry::Trace::Status.error(text)
        end
      end
    end
  end
end
