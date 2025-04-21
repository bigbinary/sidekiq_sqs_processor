require "spec_helper"

RSpec.describe SidekiqSqsProcessor::Configuration do
  let(:config) { described_class.new }

  describe "default values" do
    it "has sensible defaults" do
      expect(config.aws_region).to eq("us-east-1")
      expect(config.queue_urls).to eq([])
      expect(config.max_number_of_messages).to eq(10)
      expect(config.visibility_timeout).to eq(30)
      expect(config.wait_time_seconds).to eq(20)
      expect(config.poller_thread_count).to eq(1)
      expect(config.error_handler).to be_a(Proc)
      expect(config.logger).to be_nil
    end
  end

  describe "aws credentials" do
    it "allows setting credentials via access key and secret" do
      config.aws_access_key_id = "test-key"
      config.aws_secret_access_key = "test-secret"
      
      expect(config.aws_access_key_id).to eq("test-key")
      expect(config.aws_secret_access_key).to eq("test-secret")
    end

    it "allows setting credentials via a credentials object" do
      credentials = Aws::Credentials.new("test-key", "test-secret")
      config.aws_credentials = credentials
      
      expect(config.aws_credentials).to eq(credentials)
    end
  end

  describe "queue management" do
    it "allows setting queue URLs" do
      urls = ["https://sqs.us-east-1.amazonaws.com/123456789012/test-queue"]
      config.queue_urls = urls
      
      expect(config.queue_urls).to eq(urls)
    end

    it "allows adding queue URLs" do
      url = "https://sqs.us-east-1.amazonaws.com/123456789012/test-queue"
      config.queue_urls << url
      
      expect(config.queue_urls).to include(url)
    end
  end

  describe "logger configuration" do
    it "allows setting a custom logger" do
      logger = Logger.new(StringIO.new)
      config.logger = logger
      
      expect(config.logger).to eq(logger)
    end
  end

  describe "#validate!" do
    context "when configuration is valid" do
      before do
        config.aws_region = "us-west-2"
        config.queue_urls = ["https://sqs.us-west-2.amazonaws.com/123456789012/test-queue"]
      end

      it "returns true" do
        expect(config.validate!).to be true
      end
    end

    context "when configuration is invalid" do
      it "raises error when aws_region is missing" do
        config.aws_region = nil
        expect { config.validate! }.to raise_error(ArgumentError, /aws_region/)
      end

      it "raises error when queue_urls is empty" do
        config.queue_urls = []
        expect { config.validate! }.to raise_error(ArgumentError, /queue_urls/)
      end

      it "raises error when max_number_of_messages is invalid" do
        config.max_number_of_messages = 0
        expect { config.validate! }.to raise_error(ArgumentError, /max_number_of_messages/)
      end

      it "raises error when visibility_timeout is invalid" do
        config.visibility_timeout = -1
        expect { config.validate! }.to raise_error(ArgumentError, /visibility_timeout/)
      end

      it "raises error when wait_time_seconds is invalid" do
        config.wait_time_seconds = 30
        expect { config.validate! }.to raise_error(ArgumentError, /wait_time_seconds/)
      end

      it "raises error when poller_thread_count is invalid" do
        config.poller_thread_count = 0
        expect { config.validate! }.to raise_error(ArgumentError, /poller_thread_count/)
      end
    end
  end

  describe "#handle_error" do
    it "calls the configured error handler" do
      error = StandardError.new("Test error")
      context = { foo: "bar" }
      
      handler_called = false
      config.error_handler = ->(err, ctx) { 
        handler_called = true
        expect(err).to eq(error)
        expect(ctx).to eq(context)
      }
      
      config.handle_error(error, context)
      expect(handler_called).to be true
    end

    it "provides a default error handler that logs the error" do
      logger = double("logger")
      config.logger = logger
      
      error = StandardError.new("Test error")
      context = { foo: "bar" }
      
      expect(logger).to receive(:error).with("Test error").ordered
      allow(logger).to receive(:error).with(anything) # Allow backtrace logging
      expect(logger).to receive(:error).with("Context: #{context.inspect}").ordered
      
      # Reset to default handler
      config.error_handler = nil
      config.handle_error(error, context)
    end
  end
end
