# frozen_string_literal: true

require "active_support/notifications"

module ApmBro
  class Subscriber
    EVENT_NAME = "process_action.action_controller".freeze

    def self.subscribe!(client: Client.new)
      ActiveSupport::Notifications.subscribe(EVENT_NAME) do |name, started, finished, _unique_id, data|
        duration_ms = ((finished - started) * 1000.0).round(2)
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
          memory_usage: memory_usage_mb,
          gc_stats: gc_stats,
          sql_count: sql_count(data),
          cache_hits: cache_hits(data),
          cache_misses: cache_misses(data)
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
      
      # Filter out sensitive parameters
      sensitive_keys = %w[password password_confirmation token secret key]
      filtered_params = data[:params].except(*sensitive_keys)
      
      # Limit parameter size to prevent huge payloads
      filtered_params.to_json[0..1000] rescue {}
    rescue StandardError
      {}
    end

    def self.safe_user_agent(data)
      return "" unless data[:request]
      
      data[:request].user_agent.to_s[0..200] rescue ""
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
  end
end


