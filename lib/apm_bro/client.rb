# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

module ApmBro
  class Client
    def initialize(configuration = ApmBro.configuration)
      @configuration = configuration
      @circuit_breaker = create_circuit_breaker
      puts "Configuration: #{@configuration.inspect}"
      puts "--------------------------------"
    end

    def post_metric(event_name:, payload:, error: false)
      unless @configuration.enabled
        log_debug("ApmBro disabled; skipping metric #{event_name}")
        return
      end

      api_key = @configuration.resolve_api_key
      
      if api_key.nil?
        log_debug("ApmBro missing api_key; skipping")
        return
      end

      # Check circuit breaker before making request
      if @circuit_breaker && @configuration.circuit_breaker_enabled
        if @circuit_breaker.state == :open
          log_debug("ApmBro circuit breaker is open; skipping metric #{event_name}")
          return
        end
      end

      # Make the HTTP request (async)
      make_http_request(event_name, payload, error, api_key)

      nil
    end

    private

    def create_circuit_breaker
      return nil unless @configuration.circuit_breaker_enabled
      
      CircuitBreaker.new(
        failure_threshold: @configuration.circuit_breaker_failure_threshold,
        recovery_timeout: @configuration.circuit_breaker_recovery_timeout,
        retry_timeout: @configuration.circuit_breaker_retry_timeout
      )
    end

    def make_http_request(event_name, payload, error, api_key)
      endpoint_url = @configuration.respond_to?(:ruby_dev) && @configuration.ruby_dev ?
          'http://localhost:3100/apm/v1/metrics' :
          "https://deadbro.aberatii.com/apm/v1/metrics"

      uri = URI.parse(endpoint_url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == "https")
      http.open_timeout = @configuration.open_timeout
      http.read_timeout = @configuration.read_timeout

      request = Net::HTTP::Post.new(uri.request_uri)
      request["Content-Type"] = "application/json"
      request["Authorization"] = "Bearer #{api_key}"
      request.body = JSON.dump({ event: event_name, payload: payload, sent_at: Time.now.utc.iso8601, error: error })

      # Fire-and-forget using a short-lived thread to avoid blocking the request cycle.
      Thread.new do
        begin
          response = http.request(request)
          
          # Update circuit breaker based on response
          if @circuit_breaker && @configuration.circuit_breaker_enabled
            if response.is_a?(Net::HTTPSuccess)
              @circuit_breaker.send(:on_success)
              log_debug("ApmBro circuit breaker closed - requests resuming") if @circuit_breaker.state == :closed
            else
              @circuit_breaker.send(:on_failure)
              log_debug("ApmBro circuit breaker opened after #{@circuit_breaker.failure_count} failures") if @circuit_breaker.state == :open
            end
          end
          
          response
        rescue StandardError => e
          log_debug("ApmBro HTTP request failed: #{e.message}")
          
          # Update circuit breaker on exception
          if @circuit_breaker && @configuration.circuit_breaker_enabled
            @circuit_breaker.send(:on_failure)
            log_debug("ApmBro circuit breaker opened after #{@circuit_breaker.failure_count} failures") if @circuit_breaker.state == :open
          end
        end
      end

      nil
    end

    def log_debug(message)
      if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
        Rails.logger.debug(message)
      else
        $stdout.puts(message)
      end
    end
  end
end


