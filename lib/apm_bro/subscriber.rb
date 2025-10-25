# frozen_string_literal: true

require "active_support/notifications"

module ApmBro
  class Subscriber
    EVENT_NAME = "process_action.action_controller".freeze

    def self.subscribe!(client: Client.new)
      ActiveSupport::Notifications.subscribe(EVENT_NAME) do |name, started, finished, _unique_id, data|
        # Skip excluded controllers or controller#action pairs
        begin
          controller_name = data[:controller].to_s
          action_name = data[:action].to_s
          if ApmBro.configuration.excluded_controller_action?(controller_name, action_name)
            next
          end
        rescue StandardError
        end

        duration_ms = ((finished - started) * 1000.0).round(2)
        # Stop SQL tracking and get collected queries (this was started by the request)
        sql_queries = ApmBro::SqlSubscriber.stop_request_tracking
        
        # Stop view rendering tracking and get collected view events
        view_events = ApmBro::ViewRenderingSubscriber.stop_request_tracking
        view_performance = ApmBro::ViewRenderingSubscriber.analyze_view_performance(view_events)
        
        # Stop memory tracking and get collected memory events
        # Use lightweight tracker by default for better performance
        memory_events = ApmBro::LightweightMemoryTracker.stop_request_tracking
        memory_performance = memory_events # Lightweight tracker returns simplified data
        
        # Record memory sample for leak detection (only if memory tracking enabled)
        if ApmBro.configuration.memory_tracking_enabled
          ApmBro::MemoryLeakDetector.record_memory_sample({
            memory_usage: memory_usage_mb,
            gc_count: gc_stats[:count],
            heap_pages: gc_stats[:heap_allocated_pages],
            object_count: gc_stats[:heap_live_slots],
            request_id: data[:request_id],
            controller: data[:controller],
            action: data[:action]
          })
        end
        
        # Report exceptions attached to this action (e.g. controller/view errors)
        if data[:exception] || data[:exception_object]
          begin
            exception_class, exception_message = data[:exception] if data[:exception]
            exception_obj = data[:exception_object]
            backtrace = Array(exception_obj&.backtrace).first(50)

            error_payload = {
              controller: data[:controller],
              action: data[:action],
              format: data[:format],
              method: data[:method],
              path: safe_path(data),
              status: data[:status],
              duration_ms: duration_ms,
              rails_env: rails_env,
              host: safe_host,
              params: safe_params(data),
              user_agent: safe_user_agent(data),
              user_email: extract_user_email(data),
              exception_class: (exception_class || exception_obj&.class&.name),
              message: (exception_message || exception_obj&.message).to_s[0, 1000],
              backtrace: backtrace,
              error: true
            }

            event_name = (exception_class || exception_obj&.class&.name || "exception").to_s
            client.post_metric(event_name: event_name, payload: error_payload)
          rescue StandardError
          ensure
            next
          end
        end

        payload = {
          controller: data[:controller],
          action: data[:action],
          format: data[:format],
          method: data[:method],
          path: safe_path(data),
          status: data[:status],
          duration_ms: duration_ms,
          view_runtime_ms: data[:view_runtime],
          db_runtime_ms: data[:db_runtime],
          host: safe_host,
          rails_env: rails_env,
          params: safe_params(data),
          user_agent: safe_user_agent(data),
          user_email: extract_user_email(data),
          memory_usage: memory_usage_mb,
          gc_stats: gc_stats,
          sql_count: sql_count(data),
          sql_queries: sql_queries,
          http_outgoing: (Thread.current[:apm_bro_http_events] || []),
          cache_hits: cache_hits(data),
          cache_misses: cache_misses(data),
          view_events: view_events,
          view_performance: view_performance,
          memory_events: memory_events,
          memory_performance: memory_performance
        }
        client.post_metric(event_name: name, payload: payload)
      end
    end

    def self.safe_path(data)
      path = data[:path] || (data[:request] && data[:request].path)
      path.to_s
    rescue StandardError
      ""
    end

    def self.safe_host
      if defined?(Rails) && Rails.respond_to?(:application)
        Rails.application.class.module_parent_name rescue ""
      else
        ""
      end
    end

    def self.rails_env
      if defined?(Rails) && Rails.respond_to?(:env)
        Rails.env
      else
        ENV["RACK_ENV"] || ENV["RAILS_ENV"] || "development"
      end
    end

    def self.safe_params(data)
      return {} unless data[:params]

      params = data[:params]
      begin
        params = params.to_unsafe_h if params.respond_to?(:to_unsafe_h)
      rescue StandardError
      end

      unless params.is_a?(Hash)
        return {}
      end

      # Remove router-provided keys that we already send at top-level
      router_keys = %w[controller action format]

      # Filter out sensitive parameters
      sensitive_keys = %w[password password_confirmation token secret key]

      filtered = params.dup
      router_keys.each { |k| filtered.delete(k) || filtered.delete(k.to_sym) }
      filtered = filtered.except(*sensitive_keys, *sensitive_keys.map(&:to_sym)) if filtered.respond_to?(:except)

      # Truncate deeply to keep payload small and safe
      truncate_value(filtered)
    rescue StandardError
      {}
    end

    # Recursively truncate values to reasonable sizes to avoid huge payloads
    def self.truncate_value(value, max_str: 200, max_array: 20, max_hash_keys: 30)
      case value
      when String
        value.length > max_str ? value[0, max_str] + "…" : value
      when Numeric, TrueClass, FalseClass, NilClass
        value
      when Array
        value[0, max_array].map { |v| truncate_value(v, max_str: max_str, max_array: max_array, max_hash_keys: max_hash_keys) }
      when Hash
        entries = value.to_a[0, max_hash_keys]
        entries.each_with_object({}) do |(k, v), memo|
          memo[k] = truncate_value(v, max_str: max_str, max_array: max_array, max_hash_keys: max_hash_keys)
        end
      else
        value.to_s.length > max_str ? value.to_s[0, max_str] + "…" : value.to_s
      end
    end

    def self.safe_user_agent(data)
      begin
        # Prefer request object if available
        if data[:request]
          ua = nil
          if data[:request].respond_to?(:user_agent)
            ua = data[:request].user_agent
          elsif data[:request].respond_to?(:env)
            ua = data[:request].env && data[:request].env["HTTP_USER_AGENT"]
          end
          return ua.to_s[0..200]
        end

        # Fallback to headers object/hash if present in notification data
        if data[:headers]
          headers = data[:headers]
          if headers.respond_to?(:[])
            ua = headers["HTTP_USER_AGENT"] || headers["User-Agent"] || headers["user-agent"]
            return ua.to_s[0..200]
          elsif headers.respond_to?(:to_h)
            h = headers.to_h rescue {}
            ua = h["HTTP_USER_AGENT"] || h["User-Agent"] || h["user-agent"]
            return ua.to_s[0..200]
          end
        end

        # Fallback to env hash if present in notification data
        if data[:env].is_a?(Hash)
          ua = data[:env]["HTTP_USER_AGENT"]
          return ua.to_s[0..200]
        end

        ""
      rescue StandardError
        ""
      end
    rescue StandardError
      ""
    end

    def self.memory_usage_mb
      if defined?(GC) && GC.respond_to?(:stat)
        # Get memory usage in MB
        memory_kb = `ps -o rss= -p #{Process.pid}`.to_i rescue 0
        (memory_kb / 1024.0).round(2)
      else
        0
      end
    rescue StandardError
      0
    end

    def self.gc_stats
      if defined?(GC) && GC.respond_to?(:stat)
        stats = GC.stat
        {
          count: stats[:count] || 0,
          heap_allocated_pages: stats[:heap_allocated_pages] || 0,
          heap_sorted_pages: stats[:heap_sorted_pages] || 0,
          total_allocated_objects: stats[:total_allocated_objects] || 0
        }
      else
        {}
      end
    rescue StandardError
      {}
    end

    def self.sql_count(data)
      # Count SQL queries from the payload if available
      if data[:sql_count]
        data[:sql_count]
      elsif defined?(ActiveRecord) && ActiveRecord::Base.connection
        # Try to get from ActiveRecord connection
        ActiveRecord::Base.connection.query_cache.size rescue 0
      else
        0
      end
    rescue StandardError
      0
    end

    def self.cache_hits(data)
      if data[:cache_hits]
        data[:cache_hits]
      elsif defined?(Rails) && Rails.cache.respond_to?(:stats)
        Rails.cache.stats[:hits] rescue 0
      else
        0
      end
    rescue StandardError
      0
    end

    def self.cache_misses(data)
      if data[:cache_misses]
        data[:cache_misses]
      elsif defined?(Rails) && Rails.cache.respond_to?(:stats)
        Rails.cache.stats[:misses] rescue 0
      else
        0
      end
    rescue StandardError
      0
    end

    def self.extract_user_email(data)
      data[:headers].env['warden'].user.email
    rescue StandardError
      nil
    end
  end
end


