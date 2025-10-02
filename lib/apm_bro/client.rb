# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

module ApmBro
  class Client
    def initialize(configuration = ApmBro.configuration)
      @configuration = configuration
      puts "Configuration: #{@configuration.inspect}"
      puts "--------------------------------"
    end

    def post_metric(event_name:, payload:)
      unless @configuration.enabled
        log_debug("ApmBro disabled; skipping metric #{event_name}")
        return
      end

      api_key = @configuration.resolve_api_key
      endpoint_url = 'http://localhost:3100/apm/v1/metrics'
      if api_key.nil?
        log_debug("ApmBro missing api_key; skipping")
        return
      end


      uri = URI.parse(endpoint_url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == "https")
      http.open_timeout = @configuration.open_timeout
      http.read_timeout = @configuration.read_timeout

      request = Net::HTTP::Post.new(uri.request_uri)
      request["Content-Type"] = "application/json"
      request["Authorization"] = "Bearer #{api_key}"
      request.body = JSON.dump({ event: event_name, payload: payload, sent_at: Time.now.utc.iso8601 })

      # Fire-and-forget using a short-lived thread to avoid blocking the request cycle.
      Thread.new do
        begin
          http.request(request)
        rescue StandardError
          # Swallow errors to never affect host app
        end
      end

      nil
    end

    private

    def log_debug(message)
      if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
        Rails.logger.debug(message)
      else
        $stdout.puts(message)
      end
    end
  end
end


