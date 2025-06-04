# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.5] - 2024-04-21

### Changed
- Reduced configuration readiness check retries from 30 to 2 seconds
- Improved startup performance by reducing wait time for configuration

## [0.1.4] - 2024-04-21

### Added
- Enhanced error handling in ContinuousPoller
- Improved configuration validation
- Better logging for configuration issues
- Graceful handling of missing queue-to-worker mappings

### Changed
- Made ContinuousPoller more resilient to misconfigurations
- Sidekiq now continues running even if SQS polling is not configured
- Improved warning messages for configuration issues

## [0.1.3] - 2024-04-20

### Added
- Initial release with basic SQS polling functionality
- Support for continuous and scheduled polling
- Rails integration with generators
- Basic error handling and logging
- Support for SNS message unwrapping
- Message routing based on queue-to-worker mappings

### Dependencies
- Sidekiq (~> 7.0)
- aws-sdk-sqs (~> 1.0)
- Rails (>= 7.0) 