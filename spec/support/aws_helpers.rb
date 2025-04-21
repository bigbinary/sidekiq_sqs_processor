require "aws-sdk-sqs"
require "ostruct"

module AWSHelpers
  def stub_sqs_client
    client = instance_double(Aws::SQS::Client)
    allow(SidekiqSqsProcessor).to receive(:sqs_client).and_return(client)
    client
  end

  def mock_sqs_message(body: {}, attributes: {}, message_attributes: {})
    msg_body = body.is_a?(String) ? body : JSON.generate(body)
    receipt_handle = SecureRandom.uuid
    queue_url = "https://sqs.us-east-1.amazonaws.com/123456789012/test-queue"
    
    OpenStruct.new(
      message_id: SecureRandom.uuid,
      receipt_handle: receipt_handle,
      body: msg_body,
      attributes: attributes,
      message_attributes: message_attributes,
      md5_of_body: Digest::MD5.hexdigest(msg_body),
      queue_url: queue_url,
      to_h: {
        "message_id" => SecureRandom.uuid,
        "receipt_handle" => receipt_handle,
        "body" => msg_body,
        "attributes" => attributes,
        "message_attributes" => message_attributes,
        "md5_of_body" => Digest::MD5.hexdigest(msg_body),
        "queue_url" => queue_url
      }
    )
  end

  def mock_sqs_response(messages: [])
    OpenStruct.new(
      messages: messages.map { |msg| 
        msg.is_a?(OpenStruct) ? msg : mock_sqs_message(body: msg)
      }
    )
  end
end

RSpec.configure do |config|
  config.include AWSHelpers
end
