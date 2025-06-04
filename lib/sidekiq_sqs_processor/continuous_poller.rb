# frozen_string_literal: true

require 'singleton'

module SidekiqSqsProcessor
  class ContinuousPoller
    include Singleton

    def initialize
      puts "[SidekiqSqsProcessor] Initializing ContinuousPoller"
      @running = false
      @threads = []
      @mutex = Mutex.new
    end

    def start
      puts "[SidekiqSqsProcessor] Starting ContinuousPoller"
      puts "[SidekiqSqsProcessor] Current state: running=#{@running}, threads=#{@threads.count}"
      
      return false if running?

      @mutex.synchronize do
        puts "[SidekiqSqsProcessor] Inside start mutex"
        begin
          # Validate configuration before starting
          unless SidekiqSqsProcessor.configuration.ready_for_polling?
            puts "[SidekiqSqsProcessor] WARNING: Configuration not ready for polling. Skipping poller start."
            puts "[SidekiqSqsProcessor] Queue workers: #{SidekiqSqsProcessor.configuration.queue_workers.inspect}"
            return false
          end

          # Validate AWS credentials
          begin
            SidekiqSqsProcessor.sqs_client.get_queue_attributes(
              queue_url: SidekiqSqsProcessor.configuration.queue_urls.first,
              attribute_names: ["QueueArn"]
            )
          rescue Aws::SQS::Errors::ServiceError => e
            puts "[SidekiqSqsProcessor] WARNING: AWS credentials validation failed: #{e.class} - #{e.message}"
            puts "[SidekiqSqsProcessor] Skipping poller start due to AWS configuration issues"
            return false
          end

          @running = true
          start_polling_threads
          puts "[SidekiqSqsProcessor] Polling threads started successfully"
          true
        rescue => e
          puts "[SidekiqSqsProcessor] ERROR starting polling threads: #{e.class} - #{e.message}"
          puts "[SidekiqSqsProcessor] #{e.backtrace.join("\n")}"
          @running = false
          false
        end
      end
    end

    def stop
      puts "[SidekiqSqsProcessor] Stopping ContinuousPoller"
      return false unless running?

      @mutex.synchronize do
        begin
          @running = false
          stop_polling_threads
          puts "[SidekiqSqsProcessor] Polling threads stopped successfully"
          true
        rescue => e
          puts "[SidekiqSqsProcessor] ERROR stopping polling threads: #{e.class} - #{e.message}"
          puts "[SidekiqSqsProcessor] #{e.backtrace.join("\n")}"
          false
        end
      end
    end

    def running?
      @running
    end

    private

    def start_polling_threads
      puts "[SidekiqSqsProcessor] Starting polling threads"
      puts "[SidekiqSqsProcessor] Queue URLs: #{SidekiqSqsProcessor.configuration.queue_urls.inspect}"
      
      SidekiqSqsProcessor.configuration.queue_urls.each do |queue_url|
        thread = Thread.new do
          Thread.current.name = "SQS-Poller-#{queue_url}"
          puts "[SidekiqSqsProcessor] Started polling thread for queue: #{queue_url}"
          
          poll_queue(queue_url) while running?
        end
        @threads << thread
      end
    end

    def stop_polling_threads
      puts "[SidekiqSqsProcessor] Stopping polling threads"
      @threads.each(&:exit)
      @threads.each(&:join)
      @threads.clear
    end

    def poll_queue(queue_url)
      begin 
        response = receive_messages(queue_url)
        process_messages(response.messages, queue_url)
      rescue StandardError => e
        SidekiqSqsProcessor.handle_error(e, { queue_url: queue_url })
      end
    end

    def receive_messages(queue_url)
      SidekiqSqsProcessor.sqs_client.receive_message(
        queue_url: queue_url,
        max_number_of_messages: 10,
        visibility_timeout: 30,
        wait_time_seconds: 1,
        attribute_names: ["All"],
        message_attribute_names: ["All"]
      )
    end

    def process_messages(messages, queue_url)
      messages.each do |message|
        begin
          message_data = {
            "message_id" => message.message_id,
            "receipt_handle" => message.receipt_handle,
            "body" => message.body,
            "attributes" => message.attributes,
            "message_attributes" => message.message_attributes,
            "md5_of_body" => message.md5_of_body,
            "queue_url" => queue_url
          }

          worker_class = find_worker_for_message(message, queue_url)
          if worker_class
            worker_class.perform_async(message_data)
          else
            SidekiqSqsProcessor.handle_error(
              StandardError.new("No worker found for message"),
              { message: message_data, queue_url: queue_url }
            )
          end
        rescue StandardError => e
          SidekiqSqsProcessor.handle_error(e, { message: message, queue_url: queue_url })
        end
      end
    end

    def find_worker_for_message(message, queue_url)
      # First try to get worker class from message attributes
      worker_name = message.message_attributes&.dig("worker_class", "string_value")

      # If not found in message, use the configured mapping
      worker_name ||= SidekiqSqsProcessor.configuration.worker_class_for_queue(queue_url)

      # Convert string to class if needed
      if worker_name.is_a?(String)
        worker_name.constantize
      else
        worker_name
      end
    end
  end
end
