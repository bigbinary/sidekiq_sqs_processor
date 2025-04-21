require 'singleton'

module SidekiqSqsProcessor
  class ContinuousPoller
    include Singleton

    def initialize
      @running = false
      @threads = []
      @mutex = Mutex.new
    end

    def start
      return false if running?

      @mutex.synchronize do
        @running = true
        start_polling_threads
      end

      true
    end

    def stop
      return false unless running?

      @mutex.synchronize do
        @running = false
        stop_polling_threads
      end

      true
    end

    def running?
      @running
    end

    def stats
      {
        running: running?,
        threads: @threads.count,
        queue_urls: SidekiqSqsProcessor.configuration.queue_urls
      }
    end

    private

    def start_polling_threads
      SidekiqSqsProcessor.configuration.queue_urls.each do |queue_url|
        SidekiqSqsProcessor.configuration.poller_thread_count.times do
          thread = Thread.new do
            poll_queue(queue_url) while running?
          end
          @threads << thread
        end
      end
    end

    def stop_polling_threads
      @threads.each(&:exit)
      @threads.each(&:join)
      @threads.clear
    end

    def poll_queue(queue_url)
      response = receive_messages(queue_url)
      process_messages(response.messages, queue_url)
    rescue StandardError => e
      SidekiqSqsProcessor.handle_error(e, { queue_url: queue_url })
      sleep(1) # Brief pause before retrying
    end

    def receive_messages(queue_url)
      SidekiqSqsProcessor.sqs_client.receive_message(
        queue_url: queue_url,
        max_number_of_messages: SidekiqSqsProcessor.configuration.max_number_of_messages,
        visibility_timeout: SidekiqSqsProcessor.configuration.visibility_timeout,
        wait_time_seconds: SidekiqSqsProcessor.configuration.wait_time_seconds,
        attribute_names: ["All"],
        message_attribute_names: ["All"]
      )
    end
    def process_messages(messages, queue_url)
      messages.each do |message|
        message_data = nil
        worker_class = nil
        
        begin
          # Convert to a hash for passing to the worker
          message_data = {
            "message_id" => message.message_id,
            "receipt_handle" => message.receipt_handle,
            "body" => message.body,
            "attributes" => message.attributes,
            "message_attributes" => message.message_attributes,
            "md5_of_body" => message.md5_of_body,
            "queue_url" => queue_url
          }
          
          worker_class = find_worker_for_message(message)
          if worker_class
            # Simply call perform_async, which will be handled appropriately in test vs prod
            worker_class.perform_async(message_data)
          end
        rescue StandardError => e
          # Handle worker error without re-raising
          data_to_pass = message_data || message
          handle_worker_error(e, worker_class&.name, data_to_pass, queue_url)
        end
      end
    end
    
    def handle_worker_error(error, worker_name, message, queue_url)
      context = {
        queue_url: queue_url,
        worker: worker_name || "Unknown",
        message: message
      }
      SidekiqSqsProcessor.handle_error(error, context)
    end
    def find_worker_for_message(message)
      # Default to using the queue name as the worker class name
      # This can be overridden in subclasses for custom routing logic
      worker_name = message.message_attributes&.dig("worker_class", "string_value")
      worker_name ||= queue_name_to_worker_name(message.queue_url)
      
      SidekiqSqsProcessor.find_worker_class(worker_name)
    end

    def queue_name_to_worker_name(queue_url)
      # Convert 'my-queue-name' to 'MyQueueNameWorker'
      queue_name = queue_url.split('/').last
      "#{queue_name.split('-').map(&:capitalize).join}Worker"
    end
  end
end
