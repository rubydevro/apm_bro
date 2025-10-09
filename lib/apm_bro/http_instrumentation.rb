# frozen_string_literal: true

require "uri"
require "net/http"

module ApmBro
  module HttpInstrumentation
    EVENT_NAME = "outgoing.http".freeze

    def self.install!(client: Client.new)
      install_net_http!(client)
      install_typhoeus!(client) if defined?(::Typhoeus)
    rescue StandardError
      # Never raise from instrumentation install
    end

    def self.install_net_http!(client)
      mod = Module.new do
        define_method(:request) do |req, body = nil, &block|
          start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          response = nil
          error = nil
          begin
            response = super(req, body, &block)
            response
          rescue Exception => e
            error = e
            raise
          ensure
            finish_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            duration_ms = ((finish_time - start_time) * 1000.0).round(2)
            begin
              uri = URI.parse(req.uri ? req.uri.to_s : "http://#{@address}:#{@port}#{req.path}") rescue nil
              
              # Skip instrumentation for our own APM endpoint to prevent infinite loops
              next if uri && (uri.to_s.include?("localhost") || uri.to_s.include?("uptime.aberatii.com"))
              
              payload = {
                library: "net_http",
                method: req.method,
                url: (uri && uri.to_s),
                host: (uri && uri.host) || @address,
                path: (uri && uri.path) || req.path,
                status: (response && response.code.to_i),
                duration_ms: duration_ms,
                exception: (error && error.class.name)
              }
              # Accumulate per-request; only send with controller metric
              if Thread.current[:apm_bro_http_events]
                Thread.current[:apm_bro_http_events] << payload
              end
            rescue StandardError
            end
          end
        end
      end

      ::Net::HTTP.prepend(mod) unless ::Net::HTTP.ancestors.include?(mod)
    end

    def self.install_typhoeus!(client)
      mod = Module.new do
        define_method(:run) do |*args|
          start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          response = nil
          begin
            response = super(*args)
            response
          ensure
            finish_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            duration_ms = ((finish_time - start_time) * 1000.0).round(2)
            begin
              req_url = respond_to?(:url) ? url : (respond_to?(:base_url) ? base_url : nil)
              
              # Skip instrumentation for our own APM endpoint to prevent infinite loops
              next if req_url && req_url.include?("localhost:3100/apm/v1/metrics")
              
              payload = {
                library: "typhoeus",
                method: respond_to?(:options) && options[:method] ? options[:method].to_s.upcase : nil,
                url: req_url,
                status: (response && response.code),
                duration_ms: duration_ms
              }
              # Accumulate per-request; only send with controller metric
              if Thread.current[:apm_bro_http_events]
                Thread.current[:apm_bro_http_events] << payload
              end
            rescue StandardError
            end
          end
        end
      end

      ::Typhoeus::Request.prepend(mod) unless ::Typhoeus::Request.ancestors.include?(mod)
    rescue StandardError
    end
  end
end


