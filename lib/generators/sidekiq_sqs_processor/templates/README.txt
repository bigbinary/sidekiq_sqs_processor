
=== SidekiqSqsProcessor Installation ===

SidekiqSqsProcessor has been installed in your Rails application.

== Next Steps ==

1. Review and update the configuration in:
   config/initializers/sidekiq_sqs_processor.rb
   
   Make sure to set your SQS queue URLs!

2. Check the example worker:
   app/workers/example_sqs_worker.rb
   
   Update it to handle your specific message types.

3. Run Sidekiq to start processing messages:
   bundle exec sidekiq

== Worker Generation ==

To create additional SQS message workers:

$ rails generate sidekiq_sqs_processor:worker UserNotification

This will create:
  app/workers/user_notification_worker.rb
  spec/workers/user_notification_worker_spec.rb (if using RSpec)
  
== Advanced Configuration ==

* Set AWS credentials in your environment variables:
  export AWS_ACCESS_KEY_ID=your_key
  export AWS_SECRET_ACCESS_KEY=your_secret
  
* Configure Sidekiq as usual in config/sidekiq.yml

* Enable polling in development mode:
  export ENABLE_SQS_POLLING_IN_

