# frozen_string_literal: true

module UnoMachine
  # A bounded single-worker dispatcher. enqueue is always nonblocking and the
  # worker isolates failures so one failed IRC write cannot stop later frames.
  class Dispatcher
    STOP = Object.new.freeze

    def initialize(capacity: 128, error_handler: nil)
      @queue = SizedQueue.new(capacity)
      @error_handler = error_handler || proc { |_error| }
      @mutex = Mutex.new
      @stopped = false
      @worker = Thread.new { work }
      @worker.name = 'uno-machine-delivery' if @worker.respond_to?(:name=)
    end

    def enqueue(&job)
      return false unless job

      @mutex.synchronize do
        return false if @stopped

        @queue.push(job, true)
      end
      true
    rescue ThreadError
      false
    end

    def shutdown(timeout: 1)
      worker = @mutex.synchronize do
        return unless @worker

        @stopped = true
        @worker
      end
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
      stop_enqueued = enqueue_stop_before(deadline)
      remaining = [deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC), 0].max
      worker.join(remaining) if stop_enqueued
      worker.kill if worker.alive?
      worker.join
    ensure
      @mutex.synchronize { @worker = nil }
    end

    def stopped?
      @mutex.synchronize { @stopped }
    end

    private

    def enqueue_stop_before(deadline)
      loop do
        @queue.push(STOP, true)
        return true
      rescue ThreadError
        return false if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

        Thread.pass
      end
    end

    def work
      loop do
        job = @queue.pop
        break if job.equal?(STOP)

        job.call
      rescue StandardError => e
        begin
          @error_handler.call(e)
        rescue StandardError
          nil
        end
      end
    end
  end

  # Enqueues one job per logical frame so all chunks remain ordered.
  class Transport
    def initialize(dispatcher:, notice_target:)
      @dispatcher = dispatcher
      @notice_target = notice_target
    end

    def deliver(nick, lines)
      deliver_batch([[nick, lines]])
    end

    def deliver_batch(deliveries)
      batch = deliveries.map do |nick, lines|
        [nick.to_s.dup.freeze, Array(lines).map { |line| line.to_s.dup.freeze }.freeze]
      end.freeze
      @dispatcher.enqueue do
        batch.each do |nick, frame|
          target = @notice_target.call(nick)
          frame.each { |line| target.notice(line) }
        end
      end
    end

    def shutdown(**options)
      @dispatcher.shutdown(**options)
    end
  end
end
