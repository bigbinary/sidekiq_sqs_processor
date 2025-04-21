require "spec_helper"

RSpec.describe SidekiqSqsProcessor::BaseWorker do
  # Create a test worker that inherits from BaseWorker
  class TestWorker < described_class
    def process_message(body)
      # Test implementation
      body["processed"] = true
      body
    end
  end

  let(:message_body) { { "test" => "data" } }
  let(:sqs_message) { mock_sqs_message(body: message_body, worker_class: "TestWorker") }

  describe ".process_message_automatically" do
    it "is enabled by default" do
      expect(TestWorker.process_message_automatically).to be true
    end

    it "can be disabled" do
      TestWorker.process_message_automatically = false
      expect(TestWorker.process_message_automatically).to be false
      TestWorker.process_message_automatically = true # reset
    end
  end

  describe "#perform" do
    let(:worker) { TestWorker.new }

    it "processes the message and passes it to process_message" do
      # Stub the SQS client before performing the test
      client = stub_sqs_client
      allow(client).to receive(:delete_message).and_return(true)
      
      result = nil
      expect(worker).to receive(:process_message) do |arg|
        result = arg
        # Ensure message is properly deserialized before processing
        expect(arg).to eq(message_body)
        arg
      end
      
      worker.perform(sqs_message)
      expect(result).to eq(message_body)
    end

    it "deletes the SQS message after successful processing" do
      client = stub_sqs_client
      
      expect(client).to receive(:delete_message).with(
        queue_url: sqs_message.queue_url,
        receipt_handle: sqs_message.receipt_handle
      )
      
      worker.perform(sqs_message)
    end

    context "when an error occurs during processing" do
      it "reports the error and doesn't delete the message" do
        client = stub_sqs_client
        allow(client).to receive(:delete_message).and_return(true)
        error = StandardError.new("Test error")
        
        # Make the worker raise an error
        allow(worker).to receive(:process_message).and_raise(error)
        
        expect(client).not_to receive(:delete_message)
        expect(SidekiqSqsProcessor).to receive(:handle_error).with(
          error,
          hash_including(
            worker: "TestWorker",
            message: instance_of(OpenStruct)
          )
        )
        
        expect { worker.perform(sqs_message) }.to raise_error(error)
      end
    end
  end

  describe "retries" do
    let(:worker) { TestWorker.new }
    
    it "inherits Sidekiq retry behavior" do
      expect(TestWorker.get_sidekiq_options["retry"]).not_to be false
    end
    
    it "can be configured with custom retry options" do
      class CustomRetryWorker < SidekiqSqsProcessor::BaseWorker
        sidekiq_options retry: 5, backtrace: 10
        
        def process_message(body)
          body
        end
      end
      
      expect(CustomRetryWorker.get_sidekiq_options["retry"]).to eq(5)
      expect(CustomRetryWorker.get_sidekiq_options["backtrace"]).to eq(10)
    end
  end

  describe "queue" do
    it "uses default queue" do
      expect(TestWorker.get_sidekiq_options["queue"]).to eq("default")
    end
    
    it "allows custom queue configuration" do
      class CustomQueueWorker < SidekiqSqsProcessor::BaseWorker
        sidekiq_options queue: "high_priority"
        
        def process_message(body)
          body
        end
      end
      
      expect(CustomQueueWorker.get_sidekiq_options["queue"]).to eq("high_priority")
    end
  end
  
  # Clean up test classes
  after(:all) do
    Object.send(:remove_const, :TestWorker) if Object.const_defined?(:TestWorker)
    Object.send(:remove_const, :CustomRetryWorker) if Object.const_defined?(:CustomRetryWorker)
    Object.send(:remove_const, :CustomQueueWorker) if Object.const_defined?(:CustomQueueWorker)
  end
end
