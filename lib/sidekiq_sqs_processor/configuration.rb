module SidekiqSqsProcessor
  class Configuration
    # AWS credentials
    attr_accessor :aws_access_key_id, :aws_secret_access_key, :aws_credentials
    attr_reader :aws_region, :queue_urls, :max_number_of_messages,
                :visibility_timeout, :wait_time_seconds, :poller_thread_count,
                :error_handler, :polling_enabled, :polling_type, :poll_on_startup,
                :polling_frequency

    # Worker configuration
    attr_accessor :worker_retry_count, :worker_queue_name, :logger

    def initialize
      @aws_region = "us-east-1"
      @queue_urls = []
      @max_number_of_messages = 10
      @visibility_timeout = 30
      @wait_time_seconds = 20
      @poller_thread_count = 1
      @worker_retry_count = 25
      @worker_queue_name = "default"
      @error_handler = default_error_handler
      @polling_enabled = true
      @polling_type = :continuous
      @poll_on_startup = true
      @polling_frequency = 60 # seconds
    end

    def aws_region=(region)
      @aws_region = region&.strip
    end

    def queue_urls=(urls)
      @queue_urls = Array(urls).map(&:strip)
    end

    def add_queue_url(url)
      @queue_urls << url.strip
      @queue_urls.uniq!
    end

    def max_number_of_messages=(value)
      @max_number_of_messages = value.to_i
    end

    def visibility_timeout=(value)
      @visibility_timeout = value.to_i
    end

    def wait_time_seconds=(value)
      @wait_time_seconds = value.to_i
    end

    def poller_thread_count=(value)
      @poller_thread_count = value.to_i
    end

    def error_handler=(handler)
      if !handler.respond_to?(:call) && !handler.nil?
        raise ArgumentError, "Error handler must be callable (respond to #call)"
      end
      @error_handler = handler
    end
    
    def polling_enabled=(value)
      @polling_enabled = !!value
    end
    
    def polling_type=(value)
      value = value.to_sym if value.respond_to?(:to_sym)
      unless [:continuous, :scheduled].include?(value)
        raise ArgumentError, "polling_type must be :continuous or :scheduled"
      end
      @polling_type = value
    end
    
    def poll_on_startup=(value)
      @poll_on_startup = !!value
    end
    
    def polling_frequency=(value)
      @polling_frequency = [value.to_i, 1].max
    end

    def handle_error(error, context = {})
      if @error_handler
        @error_handler.call(error, context)
      else
        default_error_handler.call(error, context)
      end
    end

    def validate!
      errors = []

      # AWS Config
      if aws_region.nil? || aws_region.empty?
        errors << "aws_region is not configured"
      end

      # Validate thread and message settings before queue URLs
      if !poller_thread_count.positive?
        errors << "poller_thread_count must be positive"
      end

      if !max_number_of_messages.between?(1, 10)
        errors << "max_number_of_messages must be between 1 and 10"
      end

      if !wait_time_seconds.between?(0, 20)
        errors << "wait_time_seconds must be between 0 and 20"
      end

      if !visibility_timeout.positive?
        errors << "visibility_timeout must be positive"
      end
      
      if ![:continuous, :scheduled].include?(polling_type)
        errors << "polling_type must be :continuous or :scheduled"
      end
      
      if !polling_frequency.positive?
        errors << "polling_frequency must be positive"
      end
      
      # Queue URLs should be checked last
      if queue_urls.empty?
        errors << "queue_urls is empty"
      end

      # Raise first specific error for single-error tests
      if errors.length == 1
        raise ArgumentError, errors.first
      end

      # Raise all errors together
      if errors.any?
        raise ArgumentError, "Invalid configuration: #{errors.join(', ')}"
      end

      true
    end

    private

    def default_error_handler
      ->(error, context = {}) do
        logger = self.logger || Sidekiq.logger
        if error.is_a?(Exception)
          logger.error(error.message)
          logger.error(error.backtrace.join("\n")) if error.backtrace
        else
          logger.error(error.to_s)
        end
        logger.error("Context: #{context.inspect}") unless context.empty?
      end
    end
  end
end
