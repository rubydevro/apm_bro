# frozen_string_literal: true

begin
  require "active_support/notifications"
rescue LoadError
  # ActiveSupport not available
end

module ApmBro
  class SqlSubscriber
    SQL_EVENT_NAME = "sql.active_record"
    THREAD_LOCAL_KEY = :apm_bro_sql_queries
    THREAD_LOCAL_ALLOC_START_KEY = :apm_bro_sql_alloc_start
    THREAD_LOCAL_ALLOC_RESULTS_KEY = :apm_bro_sql_alloc_results
    THREAD_LOCAL_BACKTRACE_KEY = :apm_bro_sql_backtraces

    def self.subscribe!
      # Subscribe with a start/finish listener to measure allocations per query
      if ActiveSupport::Notifications.notifier.respond_to?(:subscribe)
        begin
          ActiveSupport::Notifications.notifier.subscribe(SQL_EVENT_NAME, SqlAllocListener.new)
        rescue
        end
      end

      ActiveSupport::Notifications.subscribe(SQL_EVENT_NAME) do |name, started, finished, _unique_id, data|
        next if data[:name] == "SCHEMA"
        # Only track queries that are part of the current request
        next unless Thread.current[THREAD_LOCAL_KEY]
        unique_id = _unique_id
        allocations = nil
        captured_backtrace = nil
        begin
          alloc_results = Thread.current[THREAD_LOCAL_ALLOC_RESULTS_KEY]
          allocations = alloc_results && alloc_results.delete(unique_id)

          # Get the captured backtrace from when the query started
          backtrace_map = Thread.current[THREAD_LOCAL_BACKTRACE_KEY]
          captured_backtrace = backtrace_map && backtrace_map.delete(unique_id)
        rescue
        end

        query_info = {
          sql: sanitize_sql(data[:sql]),
          name: data[:name],
          duration_ms: ((finished - started) * 1000.0).round(2),
          cached: data[:cached] || false,
          connection_id: data[:connection_id],
          trace: safe_query_trace(data, captured_backtrace),
          allocations: allocations
        }
        # Add to thread-local storage
        Thread.current[THREAD_LOCAL_KEY] << query_info
      end
    end

    def self.start_request_tracking
      Thread.current[THREAD_LOCAL_KEY] = []
      Thread.current[THREAD_LOCAL_ALLOC_START_KEY] = {}
      Thread.current[THREAD_LOCAL_ALLOC_RESULTS_KEY] = {}
      Thread.current[THREAD_LOCAL_BACKTRACE_KEY] = {}
    end

    def self.stop_request_tracking
      queries = Thread.current[THREAD_LOCAL_KEY]
      Thread.current[THREAD_LOCAL_KEY] = nil
      Thread.current[THREAD_LOCAL_ALLOC_START_KEY] = nil
      Thread.current[THREAD_LOCAL_ALLOC_RESULTS_KEY] = nil
      Thread.current[THREAD_LOCAL_BACKTRACE_KEY] = nil
      queries || []
    end

    def self.sanitize_sql(sql)
      return sql unless sql.is_a?(String)

      # Remove sensitive data patterns
      sql = sql.gsub(/\b(password|token|secret|key|ssn|credit_card)\s*=\s*['"][^'"]*['"]/i, '\1 = ?')
      sql = sql.gsub(/\b(password|token|secret|key|ssn|credit_card)\s*=\s*[^'",\s)]+/i, '\1 = ?')

      # Remove specific values in WHERE clauses that might be sensitive
      sql = sql.gsub(/WHERE\s+[^=]+=\s*['"][^'"]*['"]/i) do |match|
        match.gsub(/=\s*['"][^'"]*['"]/, "= ?")
      end

      # Limit query length to prevent huge payloads
      (sql.length > 1000) ? sql[0..1000] + "..." : sql
    end

    def self.safe_query_trace(data, captured_backtrace = nil)
      return [] unless data.is_a?(Hash)

      # Build trace from available data fields
      trace = []

      # Use filename, line, and method if available
      if data[:filename] && data[:line] && data[:method]
        trace << "#{data[:filename]}:#{data[:line]}:in `#{data[:method]}'"
      end

      # Use the captured backtrace from when the query started (most accurate)
      if captured_backtrace && captured_backtrace.is_a?(Array) && !captured_backtrace.empty?
        # Filter to only include frames that contain "app/" (application code)
        app_frames = captured_backtrace.select do |frame|
          frame.include?("app/") && !frame.include?("/vendor/")
        end

        caller_trace = app_frames.map do |line|
          # Remove any potential sensitive information from file paths
          line.gsub(/\/[^\/]*(password|secret|key|token)[^\/]*\//i, "/[FILTERED]/")
        end

        trace.concat(caller_trace)
      else
        # Fallback: try to get backtrace from current context
        begin
          # Get all available frames - we'll filter to find application code
          all_frames = Thread.current.backtrace || []

          if all_frames.empty?
            # Fallback to caller_locations if backtrace is empty
            locations = caller_locations(1, 50)
            all_frames = locations.map { |loc| "#{loc.path}:#{loc.lineno}:in `#{loc.label}'" } if locations
          end

          # Filter to only include frames that contain "app/" (application code)
          app_frames = all_frames.select do |frame|
            frame.include?("app/") && !frame.include?("/vendor/")
          end

          caller_trace = app_frames.map do |line|
            line.gsub(/\/[^\/]*(password|secret|key|token)[^\/]*\//i, "/[FILTERED]/")
          end

          trace.concat(caller_trace)
        rescue
          # If backtrace fails, try caller as fallback
          begin
            caller_stack = caller(20, 50) # Get more frames to find app/ frames
            app_frames = caller_stack.select { |frame| frame.include?("app/") && !frame.include?("/vendor/") }
            caller_trace = app_frames.map do |line|
              line.gsub(/\/[^\/]*(password|secret|key|token)[^\/]*\//i, "/[FILTERED]/")
            end
            trace.concat(caller_trace)
          rescue
            # If caller also fails, we still have the immediate location
          end
        end
      end

      # If we have a backtrace in the data, use it (but it's usually nil for SQL events)
      if data[:backtrace] && data[:backtrace].is_a?(Array)
        # Filter to only include frames that contain "app/"
        app_backtrace = data[:backtrace].select do |line|
          line.is_a?(String) && line.include?("app/") && !line.include?("/vendor/")
        end

        backtrace_trace = app_backtrace.map do |line|
          case line
          when String
            line.gsub(/\/[^\/]*(password|secret|key|token)[^\/]*\//i, "/[FILTERED]/")
          else
            line.to_s
          end
        end
        trace.concat(backtrace_trace)
      end

      # Remove duplicates and return all app/ frames (no limit)
      trace.uniq.map do |line|
        case line
        when String
          # Remove any potential sensitive information from file paths
          line.gsub(/\/[^\/]*(password|secret|key|token)[^\/]*\//i, "/[FILTERED]/")
        else
          line.to_s
        end
      end
    rescue
      []
    end
  end
end

module ApmBro
  # Listener that records GC allocation deltas per SQL event id
  class SqlAllocListener
    def start(name, id, payload)
      map = (Thread.current[ApmBro::SqlSubscriber::THREAD_LOCAL_ALLOC_START_KEY] ||= {})
      map[id] = GC.stat[:total_allocated_objects] if defined?(GC) && GC.respond_to?(:stat)

      # Capture the backtrace at query start time (before notification system processes it)
      # This gives us the actual call stack where the SQL was executed
      backtrace_map = (Thread.current[ApmBro::SqlSubscriber::THREAD_LOCAL_BACKTRACE_KEY] ||= {})
      captured_backtrace = Thread.current.backtrace
      if captured_backtrace && captured_backtrace.is_a?(Array)
        # Skip the first few frames (our listener code) to get to the actual query execution
        backtrace_map[id] = captured_backtrace[5..-1] || captured_backtrace
      end
    rescue
    end

    def finish(name, id, payload)
      start_map = Thread.current[ApmBro::SqlSubscriber::THREAD_LOCAL_ALLOC_START_KEY]
      return unless start_map && start_map.key?(id)

      start_count = start_map.delete(id)
      end_count = begin
        GC.stat[:total_allocated_objects]
      rescue
        nil
      end
      return unless start_count && end_count

      delta = end_count - start_count
      results = (Thread.current[ApmBro::SqlSubscriber::THREAD_LOCAL_ALLOC_RESULTS_KEY] ||= {})
      results[id] = delta
    rescue
    end
  end
end
