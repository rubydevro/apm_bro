# frozen_string_literal: true

require_relative "apm_bro/version"

module ApmBro
  autoload :Configuration, "apm_bro/configuration"
  autoload :Client, "apm_bro/client"
  autoload :Subscriber, "apm_bro/subscriber"
  autoload :SqlSubscriber, "apm_bro/sql_subscriber"
  autoload :SqlTrackingMiddleware, "apm_bro/sql_tracking_middleware"
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
end
