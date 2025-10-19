# frozen_string_literal: true

module ApmBro
  class SqlTrackingMiddleware
    def initialize(app)
      @app = app
    end

    def call(env)
      # Start SQL tracking for this request
      if defined?(ApmBro::SqlSubscriber)
        puts "Starting SQL tracking for request: #{env['REQUEST_METHOD']} #{env['PATH_INFO']}"
        ApmBro::SqlSubscriber.start_request_tracking
      end

      # Start view rendering tracking for this request
      if defined?(ApmBro::ViewRenderingSubscriber)
        puts "Starting view rendering tracking for request: #{env['REQUEST_METHOD']} #{env['PATH_INFO']}"
        ApmBro::ViewRenderingSubscriber.start_request_tracking
      end

      # Start lightweight memory tracking for this request
      if defined?(ApmBro::LightweightMemoryTracker)
        puts "Starting lightweight memory tracking for request: #{env['REQUEST_METHOD']} #{env['PATH_INFO']}"
        ApmBro::LightweightMemoryTracker.start_request_tracking
      end

      # Start outgoing HTTP accumulation for this request
      Thread.current[:apm_bro_http_events] = []

      @app.call(env)
    ensure
      # Clean up thread-local storage
      if defined?(ApmBro::SqlSubscriber)
        queries = Thread.current[:apm_bro_sql_queries]
        puts "Ending SQL tracking for request: #{env['REQUEST_METHOD']} #{env['PATH_INFO']} - Found #{queries&.size || 0} queries"
        Thread.current[:apm_bro_sql_queries] = nil
      end

      if defined?(ApmBro::ViewRenderingSubscriber)
        view_events = Thread.current[:apm_bro_view_events]
        puts "Ending view rendering tracking for request: #{env['REQUEST_METHOD']} #{env['PATH_INFO']} - Found #{view_events&.size || 0} view events"
        Thread.current[:apm_bro_view_events] = nil
      end

      if defined?(ApmBro::LightweightMemoryTracker)
        memory_events = Thread.current[:apm_bro_lightweight_memory]
        puts "Ending lightweight memory tracking for request: #{env['REQUEST_METHOD']} #{env['PATH_INFO']} - Memory growth: #{memory_events&.dig(:memory_growth_mb) || 0}MB"
        Thread.current[:apm_bro_lightweight_memory] = nil
      end

      # Clean up HTTP events
      Thread.current[:apm_bro_http_events] = nil
    end
  end
end
