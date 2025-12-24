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
        ApmBro::SqlSubscriber.start_request_tracking
      end

      # Start cache tracking for this request
      if defined?(ApmBro::CacheSubscriber)
        ApmBro::CacheSubscriber.start_request_tracking
      end

      # Start Redis tracking for this request
      if defined?(ApmBro::RedisSubscriber)
        ApmBro::RedisSubscriber.start_request_tracking
      end

      # Start view rendering tracking for this request
      if defined?(ApmBro::ViewRenderingSubscriber)
        ApmBro::ViewRenderingSubscriber.start_request_tracking
      end

      # Start lightweight memory tracking for this request
      if defined?(ApmBro::LightweightMemoryTracker)
        ApmBro::LightweightMemoryTracker.start_request_tracking
      end

      # Start detailed memory tracking when allocation tracking is enabled
      if ApmBro.configuration.allocation_tracking_enabled && defined?(ApmBro::MemoryTrackingSubscriber)
        ApmBro::MemoryTrackingSubscriber.start_request_tracking
      end

      # Start outgoing HTTP accumulation for this request
      Thread.current[:apm_bro_http_events] = []

      @app.call(env)
    ensure
      # Clean up thread-local storage
      if defined?(ApmBro::SqlSubscriber)
        Thread.current[:apm_bro_sql_queries]
        Thread.current[:apm_bro_sql_queries] = nil
      end

      if defined?(ApmBro::CacheSubscriber)
        Thread.current[:apm_bro_cache_events]
        Thread.current[:apm_bro_cache_events] = nil
      end

      if defined?(ApmBro::RedisSubscriber)
        Thread.current[:apm_bro_redis_events]
        Thread.current[:apm_bro_redis_events] = nil
      end

      if defined?(ApmBro::ViewRenderingSubscriber)
        Thread.current[:apm_bro_view_events]
        Thread.current[:apm_bro_view_events] = nil
      end

      if defined?(ApmBro::LightweightMemoryTracker)
        Thread.current[:apm_bro_lightweight_memory]
        Thread.current[:apm_bro_lightweight_memory] = nil
      end

      # Clean up HTTP events
      Thread.current[:apm_bro_http_events] = nil
    end
  end
end
