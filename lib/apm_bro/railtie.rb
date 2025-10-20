# frozen_string_literal: true

require "rails/railtie"

module ApmBro
  class Railtie < ::Rails::Railtie
    initializer "apm_bro.configure" do |_app|
      # Allow host app to set config in Rails config, credentials, or ENV.
      # If host app sets config.x.apm_bro, mirror into gem configuration.
      begin
        if Rails.application.config.x.respond_to?(:apm_bro)
          xcfg = Rails.application.config.x.apm_bro
          ApmBro.configure do |cfg|
            cfg.api_key = xcfg.api_key if xcfg.respond_to?(:api_key)
            cfg.enabled = xcfg.enabled if xcfg.respond_to?(:enabled)
          end
        end
      rescue StandardError
      end
    end

    initializer "apm_bro.subscribe" do |app|
      app.config.after_initialize do
        begin
          ApmBro::Subscriber.subscribe!(client: ApmBro::Client.new)
          # Install outgoing HTTP instrumentation
          require "apm_bro/http_instrumentation"
          ApmBro::HttpInstrumentation.install!(client: ApmBro::Client.new)
          
          # Install SQL query tracking
          require "apm_bro/sql_subscriber"
          ApmBro::SqlSubscriber.subscribe!
          
          # Install view rendering tracking
          require "apm_bro/view_rendering_subscriber"
          ApmBro::ViewRenderingSubscriber.subscribe!(client: ApmBro::Client.new)
          
          # Install lightweight memory tracking (default)
          require "apm_bro/lightweight_memory_tracker"
          require "apm_bro/memory_leak_detector"
          ApmBro::MemoryLeakDetector.initialize_history
          
          # Install detailed memory tracking only if enabled
          if ApmBro.configuration.allocation_tracking_enabled
            require "apm_bro/memory_tracking_subscriber"
            ApmBro::MemoryTrackingSubscriber.subscribe!(client: ApmBro::Client.new)
          end
          
          # Install job tracking if ActiveJob is available
          if defined?(ActiveJob)
            require "apm_bro/job_subscriber"
            require "apm_bro/job_sql_tracking_middleware"
            ApmBro::JobSqlTrackingMiddleware.subscribe!
            ApmBro::JobSubscriber.subscribe!(client: ApmBro::Client.new)
          end
        rescue StandardError
          # Never raise in Railtie init
        end
      end
    end

    # Insert Rack middleware early enough to observe uncaught exceptions
    initializer "apm_bro.middleware" do |app|
      begin
        require "apm_bro/error_middleware"

        if defined?(::ActionDispatch::DebugExceptions)
          app.config.middleware.insert_before(::ActionDispatch::DebugExceptions, ::ApmBro::ErrorMiddleware)
        elsif defined?(::ActionDispatch::ShowExceptions)
          app.config.middleware.insert_before(::ActionDispatch::ShowExceptions, ::ApmBro::ErrorMiddleware)
        else
          app.config.middleware.use(::ApmBro::ErrorMiddleware)
        end
      rescue StandardError
        # Never raise in Railtie init
      end
    end

    # Insert SQL tracking middleware
    initializer "apm_bro.sql_tracking_middleware" do |app|
      begin
        require "apm_bro/sql_tracking_middleware"
        app.config.middleware.use(::ApmBro::SqlTrackingMiddleware)
      rescue StandardError
        # Never raise in Railtie init
      end
    end
  end
end


