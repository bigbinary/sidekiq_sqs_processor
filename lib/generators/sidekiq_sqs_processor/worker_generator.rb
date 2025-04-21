
require 'rails/generators/named_base'

module SidekiqSqsProcessor
  module Generators
    class WorkerGenerator < Rails::Generators::NamedBase
      source_root File.expand_path('templates', __dir__)
      
      desc "Creates a SidekiqSqsProcessor worker for processing SQS messages."
      
      class_option :queue, type: :string, default: nil,
                   desc: "The Sidekiq queue for this worker (defaults to sqs_[worker_name])"
      
      class_option :retry, type: :numeric, default: nil,
                   desc: "Number of retries for this worker (defaults to configuration value)"
      
      class_option :test, type: :boolean, default: true,
                   desc: "Generate test file for this worker"
                   
      def create_worker_file
        template "worker.rb.tt", "app/workers/#{file_name}_worker.rb"
      end
      
      def create_test_file
        return unless options[:test]
        
        if defined?(RSpec) || File.exist?(File.join(destination_root, 'spec'))
          template "worker_spec.rb.tt", "spec/workers/#{file_name}_worker_spec.rb"
        elsif File.exist?(File.join(destination_root, 'test'))
          template "worker_test.rb.tt", "test/workers/#{file_name}_worker_test.rb"
        end
      end
      
      private
      
      def queue_name
        options[:queue] || "sqs_#{file_name.underscore}"
      end
      
      def retry_option
        if options[:retry]
          ", retry: #{options[:retry]}"
        else
          ""
        end
      end
      
      def worker_class_name
        "#{class_name}Worker"
      end
    end
  end
end

