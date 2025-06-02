require_relative "lib/sidekiq_sqs_processor/version"

Gem::Specification.new do |spec|
  spec.name        = "sidekiq_sqs_processor"
  spec.version     = SidekiqSqsProcessor::VERSION
  spec.authors     = ["Unnikrishnan KP"]
  spec.email       = ["unnikrishnan.kp@bigbinary.com"]
  spec.homepage    = "https://github.com/unni/pub-sub-with-sqs/sidekiq-sqs-processor#readme"
  spec.summary     = "Sidekiq-based SQS message processing framework"
  spec.description = "A Ruby gem that seamlessly integrates Amazon SQS with Sidekiq for efficient and scalable message processing"
  spec.license     = "MIT"
  
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/unni/pub-sub-with-sqs/sidekiq-sqs-processor"
  spec.metadata["changelog_uri"] = "https://github.com/unni/pub-sub-with-sqs/sidekiq-sqs-processor/blob/master/CHANGELOG.md"
  spec.metadata["documentation_uri"] = "https://github.com/unni/pub-sub-with-sqs/sidekiq-sqs-processor/wiki"
  spec.metadata["bug_tracker_uri"] = "https://github.com/unni/pub-sub-with-sqs/sidekiq-sqs-processor/issues"
  
  spec.files = Dir.glob("{bin,lib}/**/*") + %w(README.md)
  spec.require_paths = ["lib"]
  
  spec.required_ruby_version = ">= 2.6.0"
  
  spec.add_dependency "sidekiq", "~> 7.0"
  spec.add_dependency "aws-sdk-sqs", "~> 1.0"
  spec.add_dependency "rails", ">= 7.0"
  
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rubocop", "~> 1.0"
  spec.add_development_dependency "simplecov", "~> 0.21.0"
end
