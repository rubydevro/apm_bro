# frozen_string_literal: true

require "active_support/notifications"
require "thread"

module ApmBro
  class SqlSubscriber
    SQL_EVENT_NAME = "sql.active_record".freeze
    THREAD_LOCAL_KEY = :apm_bro_sql_queries

    def self.subscribe!
      puts "Subscribing to SQL events"
      
      ActiveSupport::Notifications.subscribe(SQL_EVENT_NAME) do |name, started, finished, _unique_id, data|
        # Only track queries that are part of the current request
        next unless Thread.current[THREAD_LOCAL_KEY]

        query_info = {
          sql: sanitize_sql(data[:sql]),
          name: data[:name],
          duration_ms: ((finished - started) * 1000.0).round(2),
          cached: data[:cached] || false,
          connection_id: data[:connection_id],
          trace: safe_query_trace(data)
        }
        # Add to thread-local storage
        Thread.current[THREAD_LOCAL_KEY] << query_info

      end
    end

    def self.start_request_tracking
      Thread.current[THREAD_LOCAL_KEY] = []
    end

    def self.stop_request_tracking
      queries = Thread.current[THREAD_LOCAL_KEY]
      Thread.current[THREAD_LOCAL_KEY] = nil
      queries || []
    end

    def self.sanitize_sql(sql)
      return sql unless sql.is_a?(String)

      # Remove sensitive data patterns
      sql = sql.gsub(/\b(password|token|secret|key|ssn|credit_card)\s*=\s*['"][^'"]*['"]/i, '\1 = ?')
      sql = sql.gsub(/\b(password|token|secret|key|ssn|credit_card)\s*=\s*[^'",\s)]+/i, '\1 = ?')
      
      # Remove specific values in WHERE clauses that might be sensitive
      sql = sql.gsub(/WHERE\s+[^=]+=\s*['"][^'"]*['"]/i) do |match|
        match.gsub(/=\s*['"][^'"]*['"]/, '= ?')
      end

      # Limit query length to prevent huge payloads
      sql.length > 1000 ? sql[0..1000] + "..." : sql
    end

    def self.safe_query_trace(data)
      return [] unless data.is_a?(Hash)

      # Build trace from available data fields
      trace = []
      
      # Use filename, line, and method if available
      if data[:filename] && data[:line] && data[:method]
        trace << "#{data[:filename]}:#{data[:line]}:in `#{data[:method]}'"
      end
      
      # Always try to get the full call stack for better trace information
      begin
        # Get the current call stack, skip the first few frames (our own code)
        caller_stack = caller(3, 1) # Skip 3 frames, get up to 1
        caller_trace = caller_stack.map do |line|
          # Remove any potential sensitive information from file paths
          line.gsub(/\/[^\/]*(password|secret|key|token)[^\/]*\//i, '/[FILTERED]/')
        end
        
        # Combine the immediate location with the call stack
        trace.concat(caller_trace)
      rescue StandardError
        # If caller fails, we still have the immediate location
      end
      
      # If we have a backtrace, use it (but it's usually nil for SQL events)
      if data[:backtrace] && data[:backtrace].is_a?(Array)
        backtrace_trace = data[:backtrace].first(5).map do |line|
          case line
          when String
            line.gsub(/\/[^\/]*(password|secret|key|token)[^\/]*\//i, '/[FILTERED]/')
          else
            line.to_s
          end
        end
        trace.concat(backtrace_trace)
      end
      
      # Remove duplicates and limit the number of frames
      trace.uniq.first(10).map do |line|
        case line
        when String
          # Remove any potential sensitive information from file paths
          line.gsub(/\/[^\/]*(password|secret|key|token)[^\/]*\//i, '/[FILTERED]/')
        else
          line.to_s
        end
      end
    rescue StandardError
      []
    end

  end
end
