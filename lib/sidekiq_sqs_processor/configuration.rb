# frozen_string_literal: true

module SidekiqSqsProcessor
  class Configuration
    attr_accessor :aws_region,
                  :aws_access_key_id,
                  :aws_secret_access_key,
                  :queue_workers,
                  :logger,
                  :error_handler

    def initialize
      puts "[SidekiqSqsProcessor] Initializing configuration..."
      @aws_region = 'us-east-1'
      @queue_workers = {}  # Hash of queue_url => worker_class_name
      @logger = nil
      @error_handler = nil
    end

    def validate!(strict: false)
      puts "[SidekiqSqsProcessor] Validating configuration..."
      puts "[SidekiqSqsProcessor] Current queue workers: #{@queue_workers.inspect}"
      
      raise ArgumentError, "AWS region is required" if @aws_region.nil?

      # Only enforce queue workers in strict mode
      if strict
        raise ArgumentError, "At least one queue worker mapping is required" if @queue_workers.empty?
        raise ArgumentError, "All queue URLs must have a corresponding worker class name" if @queue_workers.values.any?(&:nil?)
      elsif @queue_workers.empty?
        puts "[SidekiqSqsProcessor] WARNING: No queue workers configured yet"
        return false
      end
      
      puts "[SidekiqSqsProcessor] Configuration validation successful"
      true
    end

    def ready_for_polling?
      !@queue_workers.empty? && validate!(strict: false)
    end

    def queue_urls
      @queue_workers.keys
    end

    def worker_class_for_queue(queue_url)
      if worker = @queue_workers[queue_url]
        puts "[SidekiqSqsProcessor] Found worker #{worker} for queue #{queue_url}"
      else
        puts "[SidekiqSqsProcessor] No worker found for queue #{queue_url}"
      end
      worker
    end
  end
end
