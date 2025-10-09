# frozen_string_literal: true

require "active_support/notifications"
require "thread"

module ApmBro
  class SqlSubscriber
    SQL_EVENT_NAME = "sql.active_record".freeze
    THREAD_LOCAL_KEY = :apm_bro_sql_queries

    class << self
      attr_accessor :max_queries, :sanitize_queries
    end

    def self.subscribe!(max_queries: 50, sanitize_queries: true)
      self.max_queries = max_queries
      self.sanitize_queries = sanitize_queries
      
      ActiveSupport::Notifications.subscribe(SQL_EVENT_NAME) do |name, started, finished, _unique_id, data|
        # Only track queries that are part of the current request
        next unless Thread.current[THREAD_LOCAL_KEY]

        query_info = {
          sql: self.sanitize_queries ? sanitize_sql(data[:sql]) : data[:sql],
          name: data[:name],
          duration_ms: ((finished - started) * 1000.0).round(2),
          cached: data[:cached] || false,
          connection_id: data[:connection_id]
        }
        # Add to thread-local storage
        Thread.current[THREAD_LOCAL_KEY] << query_info

        # Limit the number of queries stored per request
        if Thread.current[THREAD_LOCAL_KEY].size > self.max_queries
          Thread.current[THREAD_LOCAL_KEY].shift
        end
      end
    end

    def self.start_request_tracking
      puts "Starting request tracking for thread: #{Thread.current.object_id}"
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

    def self.configure(max_queries: 50, sanitize_queries: true)
      @max_queries = max_queries
      @sanitize_queries = sanitize_queries
    end
  end
end
