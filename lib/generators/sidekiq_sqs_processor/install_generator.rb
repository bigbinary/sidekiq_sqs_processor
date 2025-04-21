require 'rails/generators/base'

module SidekiqSqsProcessor
  module Generators
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path('templates', __dir__)
      
      desc "Creates a SidekiqSqsProcessor initializer and configuration for your Rails application."
      
      class_option :queue_urls, type: :array, default: [],
                   desc: "List of SQS queue URLs to process"
      
      class_option :continuous, type: :boolean, default: true,
                   desc: "Use continuous polling (true) or scheduled polling (false)"
                   
      class_option :aws_region, type: :string, default: 'us-east-1',
                   desc: "AWS region for SQS queues"
      
      def create_initializer_file
        template "initializer.rb.tt", "config/initializers/sidekiq_sqs_processor.rb"
      end
      
      def create_example_worker
        template "worker.rb.tt", "app/workers/example_sqs_worker.rb"
      end
      
      def show_readme
        readme "README.txt" if behavior == :invoke
      end
      
      private
      
      def continuous_polling?
        options[:continuous]
      end
      
      def polling_type
        continuous_polling? ? ':continuous' : ':scheduled'
      end
      
      def queue_urls
        urls = options[:queue_urls]
        if urls.empty?
          "[] # Add your queue URLs here, e.g. ['https://sqs.us-east-1.amazonaws.com/123456789012/my-queue']"
        else
          urls.inspect
        end
      end
      
      def aws_region
        options[:aws_region]
      end
    end
  end
end

