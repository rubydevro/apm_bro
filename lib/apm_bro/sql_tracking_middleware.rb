# frozen_string_literal: true

module ApmBro
  class SqlTrackingMiddleware
    def initialize(app)
      @app = app
    end

    def call(env)
      # Clear logs for this request
      ApmBro.logger.clear

      # Start SQL tracking for this request
      if defined?(ApmBro::SqlSubscriber)
        puts "Starting SQL tracking for request: #{env['REQUEST_METHOD']} #{env['PATH_INFO']}"
        ApmBro::SqlSubscriber.start_request_tracking
      end

      # Start cache tracking for this request
      if defined?(ApmBro::CacheSubscriber)
        puts "Starting cache tracking for request: #{env['REQUEST_METHOD']} #{env['PATH_INFO']}"
        ApmBro::CacheSubscriber.start_request_tracking
      end

      # Start Redis tracking for this request
      if defined?(ApmBro::RedisSubscriber)
        puts "Starting redis tracking for request: #{env['REQUEST_METHOD']} #{env['PATH_INFO']}"
        ApmBro::RedisSubscriber.start_request_tracking
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

      # Start detailed memory tracking when allocation tracking is enabled
      if ApmBro.configuration.allocation_tracking_enabled && defined?(ApmBro::MemoryTrackingSubscriber)
        puts "Starting detailed memory tracking for request: #{env['REQUEST_METHOD']} #{env['PATH_INFO']}"
        ApmBro::MemoryTrackingSubscriber.start_request_tracking
      end

      # Start outgoing HTTP accumulation for this request
      Thread.current[:apm_bro_http_events] = []

      @app.call(env)
    ensure
      # Clean up thread-local storage
      if defined?(ApmBro::SqlSubscriber)
        queries = Thread.current[:apm_bro_sql_queries]
        Thread.current[:apm_bro_sql_queries] = nil
      end

      if defined?(ApmBro::CacheSubscriber)
        cache_events = Thread.current[:apm_bro_cache_events]
        Thread.current[:apm_bro_cache_events] = nil
      end

      if defined?(ApmBro::RedisSubscriber)
        redis_events = Thread.current[:apm_bro_redis_events]
        Thread.current[:apm_bro_redis_events] = nil
      end

      if defined?(ApmBro::ViewRenderingSubscriber)
        view_events = Thread.current[:apm_bro_view_events]
        Thread.current[:apm_bro_view_events] = nil
      end

      if defined?(ApmBro::LightweightMemoryTracker)
        memory_events = Thread.current[:apm_bro_lightweight_memory]
        Thread.current[:apm_bro_lightweight_memory] = nil
      end

      # Clean up HTTP events
      Thread.current[:apm_bro_http_events] = nil
    end
  end
end
