# frozen_string_literal: true

module ApmBro
  class Configuration
    DEFAULT_ENDPOINT_PATH = "/v1/metrics".freeze

    attr_accessor :api_key, :endpoint_url, :open_timeout, :read_timeout, :enabled, :ruby_dev, :memory_tracking_enabled, :allocation_tracking_enabled

    def initialize
      @api_key = nil
      @endpoint_url = nil
      @open_timeout = 1.0
      @read_timeout = 1.0
      @enabled = true
      @ruby_dev = false
      @memory_tracking_enabled = true
      @allocation_tracking_enabled = false # Disabled by default for performance
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

    private

    def present?(value)
      !(value.nil? || (value.respond_to?(:empty?) && value.empty?))
    end

    def fetch_from_rails_settings(path_keys = ["apm_bro", "api_key"])
      # Try Rails.application.config_for(:apm_bro)
      begin
        if Rails.respond_to?(:application) && Rails.application.respond_to?(:config_for)
          config = Rails.application.config_for(:apm_bro) rescue nil
          if config && config.is_a?(Hash)
            return dig_hash(config, *Array(path_keys))
          end
        end
      rescue StandardError
      end

      # Try Rails.application.credentials
      begin
        creds = Rails.application.credentials if Rails.respond_to?(:application)
        if creds
          # credentials.apm_bro[:api_key] or credentials[:apm_bro][:api_key]
          value = dig_credentials(creds, *Array(path_keys))
          return value if present?(value)
        end
      rescue StandardError
      end

      # Try Rails.application.config.x.apm_bro.api_key
      begin
        x = Rails.application.config.x if Rails.respond_to?(:application)
        if x && x.respond_to?(:apm_bro)
          config_x = x.apm_bro
          return config_x.public_send(Array(path_keys).last) if config_x.respond_to?(Array(path_keys).last)
        end
      rescue StandardError
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


