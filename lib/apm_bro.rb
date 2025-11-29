# frozen_string_literal: true

require_relative "apm_bro/version"

module ApmBro
  autoload :Configuration, "apm_bro/configuration"
  autoload :Client, "apm_bro/client"
  autoload :CircuitBreaker, "apm_bro/circuit_breaker"
  autoload :Subscriber, "apm_bro/subscriber"
  autoload :SqlSubscriber, "apm_bro/sql_subscriber"
  autoload :SqlTrackingMiddleware, "apm_bro/sql_tracking_middleware"
  autoload :CacheSubscriber, "apm_bro/cache_subscriber"
  autoload :RedisSubscriber, "apm_bro/redis_subscriber"
  autoload :ViewRenderingSubscriber, "apm_bro/view_rendering_subscriber"
  autoload :MemoryTrackingSubscriber, "apm_bro/memory_tracking_subscriber"
  autoload :MemoryLeakDetector, "apm_bro/memory_leak_detector"
  autoload :LightweightMemoryTracker, "apm_bro/lightweight_memory_tracker"
  autoload :MemoryHelpers, "apm_bro/memory_helpers"
  autoload :JobSubscriber, "apm_bro/job_subscriber"
  autoload :JobSqlTrackingMiddleware, "apm_bro/job_sql_tracking_middleware"
  autoload :Logger, "apm_bro/logger"
  begin
    require "apm_bro/railtie"
  rescue LoadError
  end

  class Error < StandardError; end

  def self.configure
    yield configuration
  end

  def self.configuration
    @configuration ||= Configuration.new
  end

  def self.reset_configuration!
    @configuration = Configuration.new
  end

  # Returns a process-stable deploy identifier used when none is configured.
  # Memoized per-Ruby process to avoid generating a new UUID per request.
  def self.process_deploy_id
    @process_deploy_id ||= begin
      require "securerandom"
      SecureRandom.uuid
    end
  end

  # Returns the logger instance for storing and retrieving log messages
  def self.logger
    @logger ||= Logger.new
  end

  # Returns the current environment (Rails.env or ENV fallback)
  def self.env
    if defined?(Rails) && Rails.respond_to?(:env)
      Rails.env
    else
      ENV["RACK_ENV"] || ENV["RAILS_ENV"] || "development"
    end
  end
end
