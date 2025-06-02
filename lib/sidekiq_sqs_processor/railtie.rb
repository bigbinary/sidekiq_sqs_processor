require 'rails'
require 'sidekiq'

module SidekiqSqsProcessor
  # Rails integration for SidekiqSqsProcessor
  # Handles initialization, configuration, and lifecycle management
  class Railtie < Rails::Railtie
    config.before_initialize do |app|
      puts "[SidekiqSqsProcessor] Loading Railtie..."
    end

    # Move initialization to after Rails has fully loaded to ensure
    # all gems have had a chance to configure themselves
    config.after_initialize do |app|
      puts "[SidekiqSqsProcessor] Starting Rails initialization..."
      
      # Set default logger to Rails logger if not specified
      SidekiqSqsProcessor.configuration.logger ||= Rails.logger

      # Configure Sidekiq server middleware and lifecycle hooks
      if defined?(Sidekiq)
        puts "[SidekiqSqsProcessor] Configuring Sidekiq server..."
        
        Sidekiq.configure_server do |config|
          puts "[SidekiqSqsProcessor] Inside Sidekiq server configuration..."
          
          # Start continuous poller when Sidekiq server starts
          config.on(:startup) do
            puts "[SidekiqSqsProcessor] Sidekiq server starting up..."
            
            # Only run the poller in the scheduler process if using Sidekiq Enterprise
            # For regular Sidekiq, this will run in every process
            if !defined?(Sidekiq::Enterprise) || Sidekiq.schedule?
              # Initialize poller in a non-blocking way
              Thread.new do
                # Name the thread for easier debugging
                Thread.current.name = "SQSPollerInit"
                begin
                  puts "[SidekiqSqsProcessor] Initializing SQS poller in background thread..."
                  
                  # Wait for up to 30 seconds for configuration to be ready
                  30.times do |i|
                    if SidekiqSqsProcessor.configuration.ready_for_polling?
                      puts "[SidekiqSqsProcessor] Configuration is ready, starting poller..."
                      SidekiqSqsProcessor.start_continuous_poller
                      puts "[SidekiqSqsProcessor] Poller started successfully"
                      break
                    else
                      puts "[SidekiqSqsProcessor] Waiting for configuration to be ready... (#{i+1}/30)" if i % 5 == 0
                      sleep 1
                    end
                  end

                  # Final check after timeout
                  unless SidekiqSqsProcessor.configuration.ready_for_polling?
                    puts "[SidekiqSqsProcessor] WARNING: Configuration not ready after 30 seconds"
                    puts "[SidekiqSqsProcessor] WARNING: SQS polling will not start"
                    puts "[SidekiqSqsProcessor] WARNING: Current configuration state:"
                    puts "[SidekiqSqsProcessor] Queue workers: #{SidekiqSqsProcessor.configuration.queue_workers.inspect}"
                  end
                rescue => e
                  puts "[SidekiqSqsProcessor] ERROR: Failed to start poller: #{e.class} - #{e.message}"
                  puts "[SidekiqSqsProcessor] ERROR: Backtrace: #{e.backtrace.join("\n")}"
                  # Log the error but don't crash the thread
                end
              end
            else
              puts "[SidekiqSqsProcessor] Skipping poller in non-scheduler process"
            end
          end

          # Stop continuous poller when Sidekiq server shuts down
          config.on(:shutdown) do
            if SidekiqSqsProcessor.continuous_poller_running?
              puts "[SidekiqSqsProcessor] Stopping continuous poller..."
              SidekiqSqsProcessor.stop_continuous_poller
            end
          end
        end
      else
        puts "[SidekiqSqsProcessor] WARNING: Sidekiq is not defined!"
      end
    end

    # Expose rake tasks if available
    rake_tasks do
      load "tasks/sidekiq_sqs_processor_tasks.rake" if File.exist?(File.join(File.dirname(__FILE__), "../tasks/sidekiq_sqs_processor_tasks.rake"))
    end

    # Register Rails generators
    generators do
      require_relative "../generators/sidekiq_sqs_processor/install_generator" if File.exist?(File.join(File.dirname(__FILE__), "../generators/sidekiq_sqs_processor/install_generator.rb"))
      require_relative "../generators/sidekiq_sqs_processor/worker_generator" if File.exist?(File.join(File.dirname(__FILE__), "../generators/sidekiq_sqs_processor/worker_generator.rb"))
    end
  end
end
