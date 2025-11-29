# frozen_string_literal: true

module ApmBro
  class Configuration
    DEFAULT_ENDPOINT_PATH = "/v1/metrics"

    attr_accessor :api_key, :endpoint_url, :open_timeout, :read_timeout, :enabled, :ruby_dev, :memory_tracking_enabled, :allocation_tracking_enabled, :circuit_breaker_enabled, :circuit_breaker_failure_threshold, :circuit_breaker_recovery_timeout, :circuit_breaker_retry_timeout, :sample_rate, :excluded_controllers, :excluded_jobs, :excluded_controller_actions, :deploy_id, :slow_query_threshold_ms, :explain_analyze_enabled

    def initialize
      @api_key = nil
      @endpoint_url = nil
      @open_timeout = 1.0
      @read_timeout = 1.0
      @enabled = true
      @ruby_dev = false
      @memory_tracking_enabled = true
      @allocation_tracking_enabled = false # Disabled by default for performance
      @circuit_breaker_enabled = true
      @circuit_breaker_failure_threshold = 3
      @circuit_breaker_recovery_timeout = 60 # seconds
      @circuit_breaker_retry_timeout = 300 # seconds
      @sample_rate = 100 # 100% sampling by default
      @excluded_controllers = []
      @excluded_jobs = []
      @excluded_controller_actions = []
      @deploy_id = resolve_deploy_id
      @slow_query_threshold_ms = 500 # Default: 500ms
      @explain_analyze_enabled = false # Enable EXPLAIN ANALYZE for slow queries by default
    end

    def resolve_api_key
      # Priority: explicit config -> Rails credentials/settings -> ENV
      return @api_key if present?(@api_key)

      if defined?(Rails)
        key = fetch_from_rails_settings
        return key if present?(key)
      end

      env_key = ENV["APM_BRO_API_KEY"]
      return env_key if present?(env_key)

      nil
    end

    def resolve_endpoint_url
      return @endpoint_url if present?(@endpoint_url)

      if defined?(Rails)
        host = fetch_from_rails_settings(%w[apm_bro host]) || ENV["APM_BRO_HOST"]
        if present?(host)
          return join_url(host, DEFAULT_ENDPOINT_PATH)
        end
      end

      ENV["APM_BRO_ENDPOINT_URL"]
    end

    def resolve_sample_rate
      # Priority: explicit config -> Rails credentials/settings -> ENV -> default
      return @sample_rate if present?(@sample_rate)

      if defined?(Rails)
        rate = fetch_from_rails_settings(%w[apm_bro sample_rate])
        return rate if present?(rate)
      end

      env_rate = ENV["APM_BRO_SAMPLE_RATE"]
      return env_rate.to_i if present?(env_rate) && env_rate.match?(/^\d+$/)

      100 # default
    end

    def resolve_deploy_id
      # Priority: explicit config -> Rails settings/credentials -> ENV -> random UUID
      return @deploy_id if present?(@deploy_id)

      if defined?(Rails)
        val = fetch_from_rails_settings(%w[apm_bro deploy_id])
        return val if present?(val)
      end

      # Prefer explicit env var, then common platform-specific var
      apm_bro_deploy_id = ENV["APM_BRO_DEPLOY_ID"]
      return apm_bro_deploy_id if present?(apm_bro_deploy_id)

      env_val = ENV["GIT_REV"]
      return env_val if present?(env_val)

      heroku_val = ENV["HEROKU_SLUG_COMMIT"]
      return heroku_val if present?(heroku_val)

      # Fall back to a process-stable ID
      ApmBro.process_deploy_id
    end

    def excluded_controller?(controller_name)
      list = resolve_excluded_controllers
      return false if list.nil? || list.empty?
      list.any? { |pat| match_name_or_pattern?(controller_name, pat) }
    end

    def excluded_job?(job_class_name)
      list = resolve_excluded_jobs
      return false if list.nil? || list.empty?
      list.any? { |pat| match_name_or_pattern?(job_class_name, pat) }
    end

    def excluded_controller_action?(controller_name, action_name)
      list = resolve_excluded_controller_actions
      return false if list.nil? || list.empty?
      target = "#{controller_name}##{action_name}"
      list.any? { |pat| match_name_or_pattern?(target, pat) }
    end

    def resolve_excluded_controller_actions
      # Collect patterns from @excluded_controller_actions
      patterns = []
      if @excluded_controller_actions && !@excluded_controller_actions.empty?
        patterns.concat(Array(@excluded_controller_actions))
      end

      # Also check @excluded_controllers for patterns containing '#' (controller action patterns)
      if @excluded_controllers && !@excluded_controllers.empty?
        action_patterns = Array(@excluded_controllers).select { |pat| pat.to_s.include?("#") }
        patterns.concat(action_patterns)
      end

      return patterns if !patterns.empty?

      if defined?(Rails)
        list = fetch_from_rails_settings(%w[apm_bro excluded_controller_actions])
        if list
          rails_patterns = Array(list)
          # Also check excluded_controllers from Rails settings for action patterns
          controllers_list = fetch_from_rails_settings(%w[apm_bro excluded_controllers])
          if controllers_list
            action_patterns = Array(controllers_list).select { |pat| pat.to_s.include?("#") }
            rails_patterns.concat(action_patterns)
          end
          return rails_patterns if !rails_patterns.empty?
        end
      end

      env = ENV["APM_BRO_EXCLUDED_CONTROLLER_ACTIONS"]
      if env && !env.strip.empty?
        env_patterns = env.split(",").map(&:strip)
        # Also check excluded_controllers env var for action patterns
        controllers_env = ENV["APM_BRO_EXCLUDED_CONTROLLERS"]
        if controllers_env && !controllers_env.strip.empty?
          action_patterns = controllers_env.split(",").map(&:strip).select { |pat| pat.include?("#") }
          env_patterns.concat(action_patterns)
        end
        return env_patterns if !env_patterns.empty?
      end

      []
    end

    def resolve_excluded_controllers
      return @excluded_controllers if @excluded_controllers && !@excluded_controllers.empty?

      if defined?(Rails)
        list = fetch_from_rails_settings(%w[apm_bro excluded_controllers])
        return Array(list) if list
      end

      env = ENV["APM_BRO_EXCLUDED_CONTROLLERS"]
      return env.split(",").map(&:strip) if env && !env.strip.empty?

      []
    end

    def resolve_excluded_jobs
      return @excluded_jobs if @excluded_jobs && !@excluded_jobs.empty?

      if defined?(Rails)
        list = fetch_from_rails_settings(%w[apm_bro excluded_jobs])
        return Array(list) if list
      end

      env = ENV["APM_BRO_EXCLUDED_JOBS"]
      return env.split(",").map(&:strip) if env && !env.strip.empty?

      []
    end

    def should_sample?
      sample_rate = resolve_sample_rate
      return true if sample_rate >= 100
      return false if sample_rate <= 0

      # Generate random number 1-100 and check if it's within sample rate
      rand(1..100) <= sample_rate
    end

    def sample_rate=(value)
      # Allow nil to use default/resolved value
      if value.nil?
        @sample_rate = nil
        return
      end

      # Allow 0 to disable sampling, or 1-100 for percentage
      unless value.is_a?(Integer) && value >= 0 && value <= 100
        raise ArgumentError, "Sample rate must be an integer between 0 and 100, got: #{value.inspect}"
      end
      @sample_rate = value
    end

    private

    def present?(value)
      !(value.nil? || (value.respond_to?(:empty?) && value.empty?))
    end

    def match_name_or_pattern?(name, pattern)
      return false if name.nil? || pattern.nil?
      pat = pattern.to_s
      return !!(name.to_s == pat) unless pat.include?("*")
      
      # For controller action patterns (containing '#'), use .* to match any characters including colons
      # For controller-only patterns, use [^:]* to match namespace segments
      if pat.include?("#")
        # Controller action pattern: allow * to match any characters including colons
        regex = Regexp.new("^" + Regexp.escape(pat).gsub("\\*", ".*") + "$")
      else
        # Controller-only pattern: use [^:]* to match namespace segments
        regex = Regexp.new("^" + Regexp.escape(pat).gsub("\\*", "[^:]*") + "$")
      end
      !!(name.to_s =~ regex)
    rescue
      false
    end

    def fetch_from_rails_settings(path_keys = ["apm_bro", "api_key"])
      # Try Rails.application.config_for(:apm_bro)
      begin
        if Rails.respond_to?(:application) && Rails.application.respond_to?(:config_for)
          config = begin
            Rails.application.config_for(:apm_bro)
          rescue
            nil
          end
          if config && config.is_a?(Hash)
            return dig_hash(config, *Array(path_keys))
          end
        end
      rescue
      end

      # Try Rails.application.credentials
      begin
        creds = Rails.application.credentials if Rails.respond_to?(:application)
        if creds
          # credentials.apm_bro[:api_key] or credentials[:apm_bro][:api_key]
          value = dig_credentials(creds, *Array(path_keys))
          return value if present?(value)
        end
      rescue
      end

      # Try Rails.application.config.x.apm_bro.api_key
      begin
        x = Rails.application.config.x if Rails.respond_to?(:application)
        if x && x.respond_to?(:apm_bro)
          config_x = x.apm_bro
          return config_x.public_send(Array(path_keys).last) if config_x.respond_to?(Array(path_keys).last)
        end
      rescue
      end

      nil
    end

    def dig_hash(hash, *keys)
      keys.reduce(hash) do |memo, key|
        break nil unless memo.is_a?(Hash)
        memo[key.to_s] || memo[key.to_sym]
      end
    end

    def dig_credentials(creds, *keys)
      # Rails credentials can behave like hashes or use methods
      current = creds
      keys.each do |key|
        if current.respond_to?(:[]) && current[key].nil? && current[key.to_sym].nil?
          if current.respond_to?(key)
            current = current.public_send(key)
          elsif current.respond_to?(key.to_sym)
            current = current.public_send(key.to_sym)
          else
            return nil
          end
        else
          current = current[key] || current[key.to_sym]
        end
        return nil if current.nil?
      end
      current
    end

    def join_url(base, path)
      base = base.to_s
      path = path.to_s
      base = base.chomp("/")
      path = "/#{path}" unless path.start_with?("/")
      base + path
    end
  end
end
