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
            cfg.endpoint_url = xcfg.endpoint_url if xcfg.respond_to?(:endpoint_url)
            cfg.enabled = xcfg.enabled if xcfg.respond_to?(:enabled)
            cfg.track_sql_queries = xcfg.track_sql_queries if xcfg.respond_to?(:track_sql_queries)
            cfg.max_sql_queries = xcfg.max_sql_queries if xcfg.respond_to?(:max_sql_queries)
            cfg.sanitize_sql_queries = xcfg.sanitize_sql_queries if xcfg.respond_to?(:sanitize_sql_queries)
          end
        end
      rescue StandardError
      end
    end

    initializer "apm_bro.subscribe" do |app|
      app.config.after_initialize do
        begin
          puts "Subscribing to Subscriber"
          ApmBro::Subscriber.subscribe!(client: ApmBro::Client.new)
          # Install outgoing HTTP instrumentation
          require "apm_bro/http_instrumentation"
          puts "Installing HTTP instrumentation"
          ApmBro::HttpInstrumentation.install!(client: ApmBro::Client.new)
          
            # Install SQL query tracking if enabled
            puts "ApmBro.configuration.track_sql_queries: #{ApmBro.configuration.track_sql_queries}"
            puts "ApmBro.configuration.max_sql_queries: #{ApmBro.configuration.max_sql_queries}"
            puts "ApmBro.configuration.sanitize_sql_queries: #{ApmBro.configuration.sanitize_sql_queries}"
            if ApmBro.configuration.track_sql_queries
              puts "Installing SQL query tracking"
              require "apm_bro/sql_subscriber"
              ApmBro::SqlSubscriber.subscribe!(
                max_queries: ApmBro.configuration.max_sql_queries || 50,
                sanitize_queries: ApmBro.configuration.sanitize_sql_queries != false
              )
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


