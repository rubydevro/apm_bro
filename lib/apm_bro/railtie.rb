# frozen_string_literal: true

begin
  require "rails/railtie"
rescue LoadError
  # Rails not available, skip railtie definition
end

# Only define Railtie if Rails is available
if defined?(Rails) && defined?(Rails::Railtie)
  module ApmBro
    class Railtie < ::Rails::Railtie

      initializer "apm_bro.subscribe" do |app|
        app.config.after_initialize do
          # Use the shared Client instance for all subscribers
          shared_client = ApmBro.client
          
          ApmBro::Subscriber.subscribe!(client: shared_client)
          # Install outgoing HTTP instrumentation
          require "apm_bro/http_instrumentation"
          ApmBro::HttpInstrumentation.install!(client: shared_client)

          # Install SQL query tracking
          require "apm_bro/sql_subscriber"
          ApmBro::SqlSubscriber.subscribe!

          # Install Rails cache tracking
          require "apm_bro/cache_subscriber"
          ApmBro::CacheSubscriber.subscribe!

          # Install Redis tracking (if Redis-related events are present)
          require "apm_bro/redis_subscriber"
          ApmBro::RedisSubscriber.subscribe!

          # Install view rendering tracking
          require "apm_bro/view_rendering_subscriber"
          ApmBro::ViewRenderingSubscriber.subscribe!(client: shared_client)

          # Install lightweight memory tracking (default)
          require "apm_bro/lightweight_memory_tracker"
          require "apm_bro/memory_leak_detector"
          ApmBro::MemoryLeakDetector.initialize_history

          # Install detailed memory tracking only if enabled
          if ApmBro.configuration.allocation_tracking_enabled
            require "apm_bro/memory_tracking_subscriber"
            ApmBro::MemoryTrackingSubscriber.subscribe!(client: shared_client)
          end

          # Install job tracking if ActiveJob is available
          if defined?(ActiveJob)
            require "apm_bro/job_subscriber"
            require "apm_bro/job_sql_tracking_middleware"
            ApmBro::JobSqlTrackingMiddleware.subscribe!
            ApmBro::JobSubscriber.subscribe!(client: shared_client)
          end
        rescue
          # Never raise in Railtie init
        end
      end

      # Insert Rack middleware early enough to observe uncaught exceptions
      initializer "apm_bro.middleware" do |app|
        require "apm_bro/error_middleware"
        
        # Use the shared Client instance for the middleware
        shared_client = ApmBro.client

        if defined?(::ActionDispatch::DebugExceptions)
          app.config.middleware.insert_before(::ActionDispatch::DebugExceptions, ::ApmBro::ErrorMiddleware, shared_client)
        elsif defined?(::ActionDispatch::ShowExceptions)
          app.config.middleware.insert_before(::ActionDispatch::ShowExceptions, ::ApmBro::ErrorMiddleware, shared_client)
        else
          app.config.middleware.use(::ApmBro::ErrorMiddleware, shared_client)
        end
      rescue
        # Never raise in Railtie init
      end

      # Insert SQL tracking middleware
      initializer "apm_bro.sql_tracking_middleware" do |app|
        require "apm_bro/sql_tracking_middleware"
        app.config.middleware.use(::ApmBro::SqlTrackingMiddleware)
      rescue
        # Never raise in Railtie init
      end
    end
  end
end
