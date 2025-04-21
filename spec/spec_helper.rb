# Start SimpleCov at the very top
unless defined?(SimpleCov)
  require "simplecov"
  SimpleCov.start do
    add_filter "/spec/"
    add_group "Core", "lib/sidekiq_sqs_processor.rb"
    add_group "Configuration", "lib/sidekiq_sqs_processor/configuration.rb"
    add_group "Workers", "lib/sidekiq_sqs_processor/base_worker.rb"
    add_group "Pollers", ["lib/sidekiq_sqs_processor/continuous_poller.rb", "lib/sidekiq_sqs_processor/scheduled_poller.rb"]
  end
end

require "bundler/setup"
require "sidekiq_sqs_processor"
require "sidekiq/testing"
require "aws-sdk-sqs"
require "json"
require "rspec"
require "securerandom"
require "digest/md5"
require "ostruct"
require "pry" if ENV["DEBUG"]

# Add helpers for testing with SQS
module SQSTestHelpers
  def mock_sqs_message(body:, worker_class: nil)
    message_body = body.is_a?(String) ? body : body.to_json
    receipt_handle = SecureRandom.uuid
    message_id = SecureRandom.uuid
    queue_url = "https://sqs.us-east-1.amazonaws.com/123456789012/test-queue"
    
    message_attributes = {}
    if worker_class
      message_attributes["worker_class"] = {
        "string_value" => worker_class.to_s,
        "data_type" => "String"
      }
    end

    # Create an OpenStruct that supports both method and hash access
    message = OpenStruct.new(
      message_id: message_id,
      receipt_handle: receipt_handle,
      body: message_body,
      attributes: {},
      message_attributes: message_attributes,
      md5_of_body: Digest::MD5.hexdigest(message_body),
      queue_url: queue_url
    )

    # Define [] method for hash-like access
    def message.[](key)
      key = key.to_s
      return to_h[key] if to_h.key?(key)
      super
    end

    # Define to_h method
    def message.to_h
      {
        "message_id" => message_id,
        "receipt_handle" => receipt_handle,
        "body" => body,
        "attributes" => attributes,
        "message_attributes" => message_attributes,
        "md5_of_body" => md5_of_body,
        "queue_url" => queue_url
      }
    end

    message
  end

  def mock_sqs_response(messages: [])
    OpenStruct.new(
      messages: messages,
      to_h: {
        "messages" => messages.map(&:to_h)
      }
    )
  end

  def stub_sqs_client
    client = instance_double(Aws::SQS::Client)
    allow(SidekiqSqsProcessor).to receive(:sqs_client).and_return(client)
    # Add default stubs for common operations to avoid AWS errors
    allow(client).to receive(:delete_message).and_return(true)
    client
  end
end

# Load support files
Dir[File.join(File.dirname(__FILE__), "support/**/*.rb")].sort.each { |f| require f }

# Configure RSpec
RSpec.configure do |config|
  config.include SQSTestHelpers
  
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  # Use the specified formatter
  config.formatter = :documentation

  # Run tests in random order to surface order dependencies
  config.order = :random

  # Enable warnings
  config.warnings = true

  # Set expectations syntax
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
    expectations.syntax = :expect
  end

  # Configure mock framework
  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  # Reset Sidekiq and SidekiqSqsProcessor between tests
  config.before do
    Sidekiq::Testing.inline!  # Run jobs immediately for testing
    Sidekiq::Worker.clear_all
    SidekiqSqsProcessor.reset!
  end
end
