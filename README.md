# Sidekiq SQS Processor

[![Gem Version](https://badge.fury.io/rb/sidekiq_sqs_processor.svg)](https://badge.fury.io/rb/sidekiq_sqs_processor)

A Ruby gem tha integrates Amazon SQS with Sidekiq for efficient and scalable message processing. Process SQS messages asynchronously with the power and monitoring capabilities of Sidekiq.

## Features

- **Automatic SQS polling** - Continuously polls SQS queues for new messages
- **Parallel processing** - Process messages across multiple Sidekiq workers
- **SNS integration** - Auto-unwraps SNS notifications
- **Configurable polling strategies** - Choose between continuous or scheduled polling
- **Automatic retries** - Leverage Sidekiq's retry mechanism with SQS visibility timeout
- **Easy message routing** - Route messages to different workers based on content
- **Rails integration** - Simple setup with generators for Rails applications
- **Comprehensive monitoring** - Track processing stats and worker health

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'sidekiq-sqs-processor'
```

And then execute:

```bash
$ bundle install
```

Or install it yourself:

```bash
$ gem install sidekiq_sqs_processor
```

## Dependencies

This gem requires the following dependencies in your application:

- Sidekiq (~> 7.0)
- aws-sdk-sqs (~> 1.0)
- Rails (>= 6.0)

### Rails Setup

If you're using Rails, run the built-in generator to create the initializer and example worker:

```bash
$ rails generate sidekiq_sqs_processor:install
```

## Basic Configuration

### Rails Applications

After running the installer, edit the generated initializer at `config/initializers/sidekiq_sqs_processor.rb`:

```ruby
SidekiqSqsProcessor.configure do |config|
  # AWS region for SQS queues
  config.aws_region = 'us-east-1'

  # SQS queue URLs to poll
  config.queue_urls = [
    'https://sqs.us-east-1.amazonaws.com/123456789012/my-queue'
  ]

  # Polling configuration
  config.polling_type = :continuous

  # Map queue URLs to worker classes
  config.queue_workers = {
    'https://sqs.us-east-1.amazonaws.com/123456789012/queue1' => 'Queue1Worker',
    'https://sqs.us-east-1.amazonaws.com/123456789012/queue2' => 'Queue2Worker'
  }

  # Optional: Set custom logger
  config.logger = Rails.logger

  # Optional: Set custom error handler
  config.error_handler = ->(error, context) do
    # Handle errors (e.g., report to monitoring service)
    Rails.logger.error("SQS Error: #{error.message}\nContext: #{context.inspect}")
  end
end
```

### Non-Rails Applications

For non-Rails applications, add this to your initialization code:

```ruby
require 'sidekiq_sqs_processor'

SidekiqSqsProcessor.configure do |config|
  # AWS region for SQS queues
  config.aws_region = 'us-east-1'

  # SQS queue URLs to poll
  config.queue_urls = [
    'https://sqs.us-east-1.amazonaws.com/123456789012/my-queue'
  ]

  # Start polling when Sidekiq starts
  Sidekiq.configure_server do |sidekiq_config|
    sidekiq_config.on(:startup) do
      SidekiqSqsProcessor.start_continuous_poller
    end

    sidekiq_config.on(:shutdown) do
      SidekiqSqsProcessor.stop_continuous_poller
    end
  end
end
```

## Creating Workers

### Using the Generator (Rails)

```bash
$ rails generate sidekiq_sqs_processor:worker UserNotification
```

This will create:
- `app/workers/user_notification_worker.rb`
- `spec/workers/user_notification_worker_spec.rb` (if using RSpec)
- or `test/workers/user_notification_worker_test.rb` (if using Test::Unit)

### Manual Worker Creation

Create a class that inherits from `SidekiqSqsProcessor::BaseWorker`:

```ruby
class MyWorker < SidekiqSqsProcessor::BaseWorker
  # Override the process_message method to handle your SQS messages
  def process_message(message_body)
    # message_body is already parsed from JSON if it was a JSON string

    # Your processing logic here
    User.find_by(id: message_body['user_id'])&.notify(message_body['message'])

    # Return a result (optional)
    { status: 'success' }
  end
end
```

## Usage Examples

### Basic Message Processing

```ruby
class OrderProcessor < SidekiqSqsProcessor::BaseWorker
  def process_message(message_body)
    if message_body.is_a?(Hash) && message_body['order_id']
      # Process an order
      process_order(message_body['order_id'], message_body['items'])
    else
      logger.error("Invalid order message format: #{message_body.inspect}")
    end
  end

  private

  def process_order(order_id, items)
    # Your order processing logic
    Order.process(order_id, items)
  end
end
```

### Handling Different Message Types

```ruby
class EventProcessor < SidekiqSqsProcessor::BaseWorker
  def process_message(message_body)
    case message_body['event_type']
    when 'user_created'
      create_user(message_body['data'])
    when 'order_placed'
      process_order(message_body['data'])
    when 'payment_received'
      process_payment(message_body['data'])
    else
      logger.warn("Unknown event type: #{message_body['event_type']}")
    end
  end

  # ... processing methods ...
end
```

### Handling SNS Messages

SNS messages are automatically detected and unwrapped, so the `message_body` will contain the inner message content:

```ruby
class NotificationProcessor < SidekiqSqsProcessor::BaseWorker
  def process_message(message_body)
    # For an SNS message, the SNS envelope has been removed
    # and message_body is the parsed content of the SNS Message field

    logger.info("Processing notification: #{message_body.inspect}")
    # ... your processing logic ...
  end
end
```

### Direct Message Enqueueing

You can also enqueue messages directly to a worker without going through SQS:

```ruby
# Enqueue a message to a specific worker
SidekiqSqsProcessor.enqueue_message(
  MyWorker,
  { order_id: 123, items: ['item1', 'item2'] }
)
```

## Configuration Options

### AWS Configuration

```ruby
config.aws_region = 'us-east-1'              # AWS region
config.aws_access_key_id = 'YOUR_KEY'        # Optional - uses env vars by default
config.aws_secret_access_key = 'YOUR_SECRET' # Optional - uses env vars by default
```

### SQS Configuration

```ruby
config.queue_urls = ['https://sqs.region.amazonaws.com/account/queue']
config.visibility_timeout = 300    # 5 minutes
config.wait_time_seconds = 20      # 20 seconds (long polling)
config.max_number_of_messages = 10 # Max messages per receive call
```

### Polling Configuration

```ruby
config.polling_type = :continuous  # :continuous or :scheduled
config.polling_frequency = 60      # Only used for scheduled (seconds)
config.polling_enabled = true      # Enable/disable polling
config.poll_on_startup = true      # Start polling when app starts
```

### Sidekiq Configuration

```ruby
config.worker_queue_name = 'sqs_default' # Default Sidekiq queue
config.worker_retry_count = 5            # Default retry count
```

### Error Handling

```ruby
# Custom error handler
config.error_handler = ->(error, context) do
  # Send to your error tracking service
  Sentry.capture_exception(error, extra: context)
end
```

## Best Practices

### Message Structure

For best routing and processing, use structured JSON messages:

```json
{
  "type": "order_placed",
  "data": {
    "order_id": "12345",
    "customer_id": "67890",
    "items": [
      {"id": "item1", "quantity": 2},
      {"id": "item2", "quantity": 1}
    ]
  },
  "metadata": {
    "source": "web",
    "timestamp": "2025-04-21T10:15:30Z"
  }
}
```

### Worker Organization

- Create separate workers for different message types or domains
- Use class inheritance for common processing logic
- Keep workers small and focused

### Error Handling

- Use the `error_handler` config option for global error reporting
- Implement custom error handling in your workers for specific cases
- Let Sidekiq handle retries for transient failures

### Visibility Timeout

- Set your SQS visibility timeout longer than your Sidekiq job timeout
- A good rule of thumb: visibility_timeout = (average_processing_time * 5) + max_retry_delay

### Message Size Limits

Remember that SQS has a 256KB message size limit. For larger data:
- Store the data externally (e.g., S3) and include a reference in the message
- Split large datasets across multiple messages

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
