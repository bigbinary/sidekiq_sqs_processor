require "sidekiq"

module SidekiqSqsProcessor
  class BaseWorker
    include Sidekiq::Worker

    class << self
      def process_message_automatically
        return @process_message_automatically if defined?(@process_message_automatically)
        @process_message_automatically = true
      end

      def process_message_automatically=(value)
        @process_message_automatically = value
      end

      def inherited(subclass)
        super
        # Copy the process_message_automatically value to subclasses
        subclass.process_message_automatically = process_message_automatically
      end
    end

    # Configure Sidekiq options with defaults
    sidekiq_options(
      retry: 25,     # Default retry count
      queue: 'default' # Default queue name
    )

    def perform(message_data)
      process_message_data(message_data) if self.class.process_message_automatically
    end

    # Override this method in your worker
    def process_message(body)
      raise NotImplementedError, "You must implement process_message in your worker"
    end

    private

    def process_message_data(message_data)
      begin
        # Parse and process the message
        body = JSON.parse(message_data["body"])
        process_message(body)

        # Delete the message from SQS after successful processing
        delete_sqs_message(message_data)
      rescue JSON::ParserError => e
        handle_error(e, message_data, "Failed to parse message body")
      rescue Aws::SQS::Errors::ServiceError => e
        handle_error(e, message_data, "SQS service error")
      rescue StandardError => e
        handle_error(e, message_data, "Error processing message")
      end
    end

    def delete_sqs_message(message_data)
      return unless message_data["queue_url"] && message_data["receipt_handle"]
      
      SidekiqSqsProcessor.sqs_client.delete_message(
        queue_url: message_data["queue_url"],
        receipt_handle: message_data["receipt_handle"]
      )
    rescue Aws::SQS::Errors::ServiceError => e
      handle_error(e, message_data, "Failed to delete message from SQS")
    end

    def handle_error(error, message_data, description)
      SidekiqSqsProcessor.handle_error(error, {
        worker: self.class.name,
        message: message_data,
        description: description
      })
      raise # Re-raise to trigger Sidekiq retry
    end

    def logger
      SidekiqSqsProcessor.configuration.logger || Sidekiq.logger
    end
  end
end
