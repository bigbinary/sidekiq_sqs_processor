require "spec_helper"

RSpec.describe SidekiqSqsProcessor do
  it "has a version number" do
    expect(SidekiqSqsProcessor::VERSION).not_to be nil
  end

  describe ".configure" do
    it "yields the configuration object" do
      yielded_config = nil
      described_class.configure do |config|
        yielded_config = config
      end

      expect(yielded_config).to be_a(SidekiqSqsProcessor::Configuration)
      expect(yielded_config).to eq(described_class.configuration)
    end
  end

  describe ".sqs_client" do
    it "creates and caches an SQS client" do
      described_class.reset!
      
      expect(Aws::SQS::Client).to receive(:new).once.and_call_original
      client1 = described_class.sqs_client
      client2 = described_class.sqs_client
      
      expect(client1).to be_a(Aws::SQS::Client)
      expect(client1).to eq(client2)
    end
  end

  describe ".worker_classes" do
    before do
      # Define test worker classes
      class TestWorker1 < SidekiqSqsProcessor::BaseWorker
        def process_message(body); end
      end
      
      class TestWorker2 < SidekiqSqsProcessor::BaseWorker
        def process_message(body); end
      end
      
      class NotAWorker
        def process_message(body); end
      end
    end

    after do
      # Clean up test classes
      Object.send(:remove_const, :TestWorker1) if Object.const_defined?(:TestWorker1)
      Object.send(:remove_const, :TestWorker2) if Object.const_defined?(:TestWorker2)
      Object.send(:remove_const, :NotAWorker) if Object.const_defined?(:NotAWorker)
    end

    it "finds all worker classes inheriting from BaseWorker" do
      worker_classes = described_class.worker_classes
      
      expect(worker_classes).to include(TestWorker1)
      expect(worker_classes).to include(TestWorker2)
      expect(worker_classes).not_to include(NotAWorker)
    end
  end

  describe ".find_worker_class" do
    before do
      class TestSQSWorker < SidekiqSqsProcessor::BaseWorker
        def process_message(body); end
      end
    end

    after do
      Object.send(:remove_const, :TestSQSWorker) if Object.const_defined?(:TestSQSWorker)
    end

    it "finds a worker class by name" do
      worker_class = described_class.find_worker_class("TestSQSWorker")
      expect(worker_class).to eq(TestSQSWorker)
    end

    it "returns nil for non-existent worker class" do
      worker_class = described_class.find_worker_class("NonExistentWorker")
      expect(worker_class).to be_nil
    end
  end

  describe ".enqueue_message" do
    before do
      class EnqueueTestWorker < SidekiqSqsProcessor::BaseWorker
        def process_message(body); end
      end
    end

    after do
      Object.send(:remove_const, :EnqueueTestWorker) if Object.const_defined?(:EnqueueTestWorker)
    end

    it "enqueues a message to the specified worker" do
      # Store original testing mode
      original_mode = Sidekiq::Testing.fake? ? :fake : :inline

      begin
        # Switch to fake mode and clear existing jobs
        Sidekiq::Testing.fake!
        Sidekiq::Worker.clear_all
        
        message_body = { "test" => "data" }
        job_id = SidekiqSqsProcessor.enqueue_message(EnqueueTestWorker, message_body)
        
        expect(job_id).not_to be_nil
        expect(EnqueueTestWorker.jobs.size).to eq(1)
        
        job_args = EnqueueTestWorker.jobs.first["args"].first
        expect(JSON.parse(job_args["body"])).to eq(message_body)
      ensure
        # Restore original testing mode
        original_mode == :fake ? Sidekiq::Testing.fake! : Sidekiq::Testing.inline!
      end
    end

    it "raises an error if worker doesn't inherit from BaseWorker" do
      class RegularWorker
        include Sidekiq::Worker
      end

      expect {
        SidekiqSqsProcessor.enqueue_message(RegularWorker, { "test" => "data" })
      }.to raise_error(ArgumentError, /must inherit from/)

      Object.send(:remove_const, :RegularWorker)
    end
  end
end
