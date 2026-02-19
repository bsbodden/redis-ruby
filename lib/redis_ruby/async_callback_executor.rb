# frozen_string_literal: true

module RR
  # Executes callbacks asynchronously using a thread pool.
  #
  # Provides non-blocking callback execution to prevent slow callbacks
  # from impacting connection performance. Uses a fixed-size thread pool
  # with a bounded queue to prevent resource exhaustion.
  #
  # @example Basic usage
  #   executor = RR::AsyncCallbackExecutor.new(pool_size: 4)
  #
  #   executor.execute do
  #     # This runs in a background thread
  #     send_metrics_to_datadog
  #   end
  #
  #   executor.shutdown
  #
  # @example With error handler
  #   error_handler = RR::CallbackErrorHandler.new(strategy: :log)
  #   executor = RR::AsyncCallbackExecutor.new(
  #     pool_size: 4,
  #     error_handler: error_handler
  #   )
  #
  class AsyncCallbackExecutor
    # Default thread pool size
    DEFAULT_POOL_SIZE = 4

    # Default queue size (max pending callbacks)
    DEFAULT_QUEUE_SIZE = 100

    attr_reader :pool_size, :queue_size

    # Initialize a new async callback executor.
    #
    # @param pool_size [Integer] Number of worker threads
    # @param queue_size [Integer] Maximum number of pending callbacks
    # @param error_handler [CallbackErrorHandler, nil] Error handler for callback errors
    def initialize(pool_size: DEFAULT_POOL_SIZE, queue_size: DEFAULT_QUEUE_SIZE, error_handler: nil)
      @pool_size = pool_size
      @queue_size = queue_size
      @error_handler = error_handler || CallbackErrorHandler.new(strategy: :log)
      @queue = SizedQueue.new(queue_size)
      @workers = []
      @shutdown = false
      @mutex = Mutex.new

      start_workers
    end

    # Execute a callback asynchronously.
    #
    # Queues the callback for execution by a worker thread. If the queue is full,
    # this method will block until space is available (or execute synchronously
    # if shutdown is in progress).
    #
    # @param context [String, nil] Context information for error handling
    # @yield Block to execute asynchronously
    # @return [void]
    def execute(context: nil, &block)
      return if @shutdown

      begin
        @queue.push([block, context], true) # non_block=true
      rescue ThreadError
        # Queue is full, execute synchronously as fallback
        @error_handler.call(context: context, &block)
      end
    end

    # Shutdown the executor and wait for pending callbacks to complete.
    #
    # @param timeout [Float, nil] Maximum time to wait for workers to finish (nil = wait forever)
    # @return [Boolean] true if all workers finished, false if timeout occurred
    def shutdown(timeout: nil)
      @mutex.synchronize do
        return if @shutdown

        @shutdown = true
      end

      # Signal workers to stop by pushing nil
      @pool_size.times { @queue.push(nil) }

      # Wait for workers to finish
      deadline = timeout ? Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout : nil

      @workers.each do |worker|
        if deadline
          remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
          worker.join([remaining, 0].max)
        else
          worker.join
        end
      end

      # Check if all workers finished
      @workers.all? { |w| !w.alive? }
    end

    # Check if the executor is shutdown.
    #
    # @return [Boolean]
    def shutdown?
      @shutdown
    end

    # Get the number of pending callbacks in the queue.
    #
    # @return [Integer]
    def queue_length
      @queue.length
    end

    private

    # Start worker threads.
    def start_workers
      @pool_size.times do
        @workers << Thread.new { worker_loop }
      end
    end

    # Worker thread loop.
    def worker_loop
      loop do
        item = @queue.pop
        break if item.nil? # Shutdown signal

        block, context = item
        @error_handler.call(context: context, &block)
      end
    rescue StandardError => e
      # Worker thread error - log and exit
      @error_handler.handle_error(e, context: "async callback worker")
    end
  end
end
