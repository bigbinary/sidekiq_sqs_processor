require "spec_helper"

RSpec.describe SidekiqSqsProcessor::ContinuousPoller do
  let(:poller) { described_class.instance }
  let(:test_queue_url) { "https://sqs.us-east-1.amazonaws.com/123456789012/test-queue" }

  # Helper method to create test workers
  def create_test_worker(name: "TestSQSWorker", &block)
    Class.new(SidekiqSqsProcessor::BaseWorker) do
      define_singleton_method(:name) { name }
      
      if block_given?
        define_method(:process_message, &block)
      else
        define_method(:process_message) { |body| body }
      end
    end
  end

  # Reset the singleton instance between tests
  before(:each) do
    described_class.instance_variable_set(:@instance, nil)
  end

  after(:each) do
    poller.stop if poller.running?
    described_class.instance_variable_set(:@instance, nil)
  end

  before do
    SidekiqSqsProcessor.configure do |config|
      config.aws_region = "us-east-1"
      config.queue_urls = [test_queue_url]
      config.poller_thread_count = 1
    end
  end

  after do
    poller.stop if poller.running?
  end

  describe "#start" do
    it "starts polling threads" do
      expect(poller.running?).to be false
      poller.start
      expect(poller.running?).to be true
      expect(poller.stats[:threads]).to eq(1)
    end

    it "doesn't start polling if already running" do
      poller.start
      thread_count = poller.stats[:threads]
      
      poller.start
      expect(poller.stats[:threads]).to eq(thread_count)
    end

    it "respects configured thread count" do
      SidekiqSqsProcessor.configuration.poller_thread_count = 2
      
      poller.start
      expect(poller.stats[:threads]).to eq(2)
      
      # Reset for other tests
      SidekiqSqsProcessor.configuration.poller_thread_count = 1
    end
  end

  describe "#stop" do
    it "stops all polling threads" do
      poller.start
      expect(poller.running?).to be true
      
      poller.stop
      expect(poller.running?).to be false
      expect(poller.stats[:threads]).to eq(0)
    end

    it "does nothing if not running" do
      expect(poller.running?).to be false
      poller.stop
      expect(poller.running?).to be false
    end

    it "waits for threads to finish gracefully" do
      poller.start
      
      # Simulate long-running thread cleanup
      allow_any_instance_of(Thread).to receive(:join).and_return(true)
      
      poller.stop
      expect(poller.running?).to be false
    end
  end

  describe "#poll_queue" do
    let(:client) { stub_sqs_client }
    let(:sqs_message) { mock_sqs_message(body: { "test" => "data" }, worker_class: "TestSQSWorker") }
    let(:sqs_response) { mock_sqs_response(messages: [sqs_message]) }

    it "receives messages from SQS and processes them" do
      # Create a test worker using our helper
      worker_class = create_test_worker
      stub_const("TestSQSWorker", worker_class)
      
      # Mock SQS receive_message
      expect(client).to receive(:receive_message).with(
        queue_url: test_queue_url,
        max_number_of_messages: SidekiqSqsProcessor.configuration.max_number_of_messages,
        visibility_timeout: SidekiqSqsProcessor.configuration.visibility_timeout,
        wait_time_seconds: SidekiqSqsProcessor.configuration.wait_time_seconds,
        message_attribute_names: ["All"],
        attribute_names: ["All"]
      ).and_return(sqs_response)
      
      # Add a worker_class attribute to the SQS message
      # The worker_class is already set in the sqs_message helper
      # Expect the worker to be called
      expect(worker_class).to receive(:perform_async).with(anything)
      
      # Call poll_queue and verify it processes the message
      poller.send(:poll_queue, test_queue_url)
    end

    it "handles errors during polling gracefully" do
      expect(client).to receive(:receive_message).and_raise(Aws::SQS::Errors::ServiceError.new(nil, "Test error"))
      expect(SidekiqSqsProcessor).to receive(:handle_error)
      
      # Should not raise an error
      expect { poller.send(:poll_queue, test_queue_url) }.not_to raise_error
    end

    it "handles message processing errors gracefully" do
      expect(client).to receive(:receive_message).and_return(sqs_response)
      
      # Create a test worker that raises an error
      error_worker = create_test_worker do |_body|
        raise StandardError, "Test processing error"
      end
      
      # Make sure the worker class is available
      stub_const("TestSQSWorker", error_worker)
      
      # Store and temporarily change Sidekiq mode to make test consistent
      original_mode = Sidekiq::Testing.fake? ? :fake : :inline
      Sidekiq::Testing.fake!
      
      # Allow perform_async to be called but then raise an error
      expect(error_worker).to receive(:perform_async).and_raise(StandardError.new("Test processing error"))
      
      # Expect the error to be handled properly
      expect(poller).to receive(:handle_worker_error).with(
        instance_of(StandardError),
        "TestSQSWorker",
        anything,
        test_queue_url
      )
      
      # Call poll_queue and verify it handles errors
      expect { poller.send(:poll_queue, test_queue_url) }.not_to raise_error
      
      # Restore original testing mode
      original_mode == :fake ? Sidekiq::Testing.fake! : Sidekiq::Testing.inline!
    end
  end
end
