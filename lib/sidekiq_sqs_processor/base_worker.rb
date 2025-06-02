require "sidekiq"

module SidekiqSqsProcessor
  class BaseWorker
    include Sidekiq::Worker

    # Configure Sidekiq options with defaults
    sidekiq_options(
      retry: 25,     # Default retry count
      queue: 'default' # Default queue name
    )

    def perform(message_data)
      begin
        # Parse the SQS message body
        body = JSON.parse(message_data["body"])

        # Extract the actual message from the SQS message
        # SNS messages are wrapped in a JSON structure with a "Message" field
        actual_message = if body["Message"]
          JSON.parse(body["Message"])
        else
          body
        end

        # Process the message
        process_message(actual_message)

        # Delete the message from SQS after successful processing
        delete_sqs_message(message_data)
      rescue JSON::ParserError => e
        SidekiqSqsProcessor.handle_error(e, {
          worker: self.class.name,
          message: message_data,
          description: "Failed to parse message body"
        })
        raise # Re-raise to trigger Sidekiq retry
      rescue Aws::SQS::Errors::ServiceError => e
        SidekiqSqsProcessor.handle_error(e, {
          worker: self.class.name,
          message: message_data,
          description: "SQS service error"
        })
        raise # Re-raise to trigger Sidekiq retry
      rescue StandardError => e
        SidekiqSqsProcessor.handle_error(e, {
          worker: self.class.name,
          message: message_data,
          description: "Error processing message"
        })
        raise # Re-raise to trigger Sidekiq retry
      end
    end

    # Override this method in your worker
    def process_message(body)
      raise NotImplementedError, "You must implement process_message in your worker"
    end

    private

    def delete_sqs_message(message_data)
      return unless message_data["queue_url"] && message_data["receipt_handle"]

      SidekiqSqsProcessor.sqs_client.delete_message(
        queue_url: message_data["queue_url"],
        receipt_handle: message_data["receipt_handle"]
      )
    rescue Aws::SQS::Errors::ServiceError => e
      SidekiqSqsProcessor.handle_error(e, {
        worker: self.class.name,
        message: message_data,
        description: "Failed to delete message from SQS"
      })
      raise # Re-raise to trigger Sidekiq retry
    end
  end
end
