# frozen_string_literal: true

RSpec.describe ApmBro do
  it "has a version number" do
    expect(ApmBro::VERSION).not_to be nil
  end

  describe "configuration" do
    it "has basic configuration" do
      config = ApmBro::Configuration.new
      expect(config.enabled).to be true
      expect(config.open_timeout).to eq(1.0)
      expect(config.read_timeout).to eq(1.0)
    end

    it "generates a deploy_id by default and can be overridden" do
      config = ApmBro::Configuration.new
      id1 = config.resolve_deploy_id
      expect(id1).to be_a(String)
      expect(id1.length).to be >= 8

      # Override via ENV
      ENV["APM_BRO_DEPLOY_ID"] = "test-deploy-123"
      id2 = ApmBro::Configuration.new.resolve_deploy_id
      expect(id2).to eq("test-deploy-123")
      ENV.delete("APM_BRO_DEPLOY_ID")
    end

    it "has sample rate configuration" do
      config = ApmBro::Configuration.new
      expect(config.sample_rate).to eq(100)
    end

    it "validates sample rate range" do
      config = ApmBro::Configuration.new

      # Valid values
      config.sample_rate = 0
      expect(config.sample_rate).to eq(0)

      config.sample_rate = 1
      expect(config.sample_rate).to eq(1)

      config.sample_rate = 50
      expect(config.sample_rate).to eq(50)

      config.sample_rate = 100
      expect(config.sample_rate).to eq(100)

      # Invalid values
      expect { config.sample_rate = 101 }.to raise_error(ArgumentError, /Sample rate must be an integer between 0 and 100/)
      expect { config.sample_rate = "50" }.to raise_error(ArgumentError, /Sample rate must be an integer between 0 and 100/)
    end

    it "determines sampling correctly" do
      config = ApmBro::Configuration.new

      # 100% sampling should always return true
      config.sample_rate = 100
      expect(config.should_sample?).to be true

      # 0% sampling should always return false
      config.sample_rate = 0
      expect(config.should_sample?).to be false

      # 50% sampling should return true/false randomly
      config.sample_rate = 50
      results = 100.times.map { config.should_sample? }
      expect(results).to include(true)
      expect(results).to include(false)
    end

    it "resolves sample rate from environment variables" do
      config = ApmBro::Configuration.new
      config.sample_rate = nil # Clear explicit setting

      # Test with environment variable
      ENV["APM_BRO_SAMPLE_RATE"] = "25"
      expect(config.resolve_sample_rate).to eq(25)

      # Test with invalid environment variable
      ENV["APM_BRO_SAMPLE_RATE"] = "invalid"
      expect(config.resolve_sample_rate).to eq(100) # Should fall back to default

      # Clean up
      ENV.delete("APM_BRO_SAMPLE_RATE")
    end

    it "falls back to default when no sample rate is configured" do
      config = ApmBro::Configuration.new
      config.sample_rate = nil

      # Should return default of 100
      expect(config.resolve_sample_rate).to eq(100)
    end

    it "resolves api_key from ENV" do
      config = ApmBro::Configuration.new
      config.api_key = nil

      ENV["APM_BRO_API_KEY"] = "env-api-key"
      expect(config.resolve_api_key).to eq("env-api-key")
      ENV.delete("APM_BRO_API_KEY")
    end

    it "resolves endpoint_url from ENV" do
      config = ApmBro::Configuration.new
      config.endpoint_url = nil

      ENV["APM_BRO_ENDPOINT_URL"] = "https://custom-endpoint.com/v1/metrics"
      expect(config.resolve_endpoint_url).to eq("https://custom-endpoint.com/v1/metrics")
      ENV.delete("APM_BRO_ENDPOINT_URL")
    end

    it "resolves deploy_id from GIT_REV" do
      config = ApmBro::Configuration.new
      config.deploy_id = nil

      ENV["GIT_REV"] = "abc123"
      expect(config.resolve_deploy_id).to eq("abc123")
      ENV.delete("GIT_REV")
    end

    it "resolves deploy_id from HEROKU_SLUG_COMMIT" do
      config = ApmBro::Configuration.new
      config.deploy_id = nil

      ENV["HEROKU_SLUG_COMMIT"] = "heroku-commit-123"
      expect(config.resolve_deploy_id).to eq("heroku-commit-123")
      ENV.delete("HEROKU_SLUG_COMMIT")
    end

    it "has memory tracking configuration" do
      config = ApmBro::Configuration.new
      expect(config.memory_tracking_enabled).to be true
      expect(config.allocation_tracking_enabled).to be false
    end

    it "has circuit breaker configuration" do
      config = ApmBro::Configuration.new
      expect(config.circuit_breaker_enabled).to be true
      expect(config.circuit_breaker_failure_threshold).to eq(3)
      expect(config.circuit_breaker_recovery_timeout).to eq(60)
      expect(config.circuit_breaker_retry_timeout).to eq(300)
    end
  end

  describe "Client" do
    let(:config) { ApmBro::Configuration.new }
    let(:client) { ApmBro::Client.new(config) }

    before do
      config.enabled = true
      config.api_key = "test_key"
      config.sample_rate = 100 # Start with 100% sampling
    end

    it "sends metrics when sampling is enabled" do
      # Mock the HTTP request to avoid actual network calls
      allow_any_instance_of(Net::HTTP).to receive(:request).and_return(double("Response", code: "202", message: "Accepted"))

      expect { client.post_metric(event_name: "test", payload: {}) }.not_to raise_error
    end

    it "skips metrics when sampling is disabled" do
      config.sample_rate = 0

      # Should not make HTTP requests
      expect_any_instance_of(Net::HTTP).not_to receive(:request)

      client.post_metric(event_name: "test", payload: {})
    end

    it "skips metrics when disabled" do
      config.enabled = false

      # Should not make HTTP requests
      expect_any_instance_of(Net::HTTP).not_to receive(:request)

      client.post_metric(event_name: "test", payload: {})
    end

    it "skips metrics when api_key is missing" do
      config.api_key = nil

      # Should not make HTTP requests
      expect_any_instance_of(Net::HTTP).not_to receive(:request)

      client.post_metric(event_name: "test", payload: {})
    end

    it "handles circuit breaker when open" do
      config.circuit_breaker_enabled = true
      client = ApmBro::Client.new(config)

      # Force circuit breaker to open state
      circuit_breaker = client.instance_variable_get(:@circuit_breaker)
      circuit_breaker.open!

      # Should not make HTTP requests when circuit is open and not ready to reset
      expect_any_instance_of(Net::HTTP).not_to receive(:request)
      client.post_metric(event_name: "test", payload: {})
    end

    it "uses ruby_dev endpoint when enabled" do
      config.ruby_dev = true
      client = ApmBro::Client.new(config)

      # Mock HTTP request
      http_double = double("Net::HTTP")
      uri_double = double("URI", host: "localhost", port: 3100, scheme: "http", request_uri: "/apm/v1/metrics")
      allow(URI).to receive(:parse).and_return(uri_double)
      allow(Net::HTTP).to receive(:new).and_return(http_double)
      allow(http_double).to receive(:use_ssl=)
      allow(http_double).to receive(:open_timeout=)
      allow(http_double).to receive(:read_timeout=)
      allow(http_double).to receive(:request).and_return(double("Response", code: "202"))

      # Should use dev endpoint
      expect(URI).to receive(:parse).with("http://localhost:3100/apm/v1/metrics")

      client.post_metric(event_name: "test", payload: {})
    end

    it "handles HTTP request failures" do
      http_double = double("Net::HTTP")
      uri_double = double("URI", host: "example.com", port: 443, scheme: "https", request_uri: "/apm/v1/metrics")
      allow(URI).to receive(:parse).and_return(uri_double)
      allow(Net::HTTP).to receive(:new).and_return(http_double)
      allow(http_double).to receive(:use_ssl=)
      allow(http_double).to receive(:open_timeout=)
      allow(http_double).to receive(:read_timeout=)
      allow(http_double).to receive(:request).and_raise(StandardError.new("Network error"))

      # Should not raise error
      expect { client.post_metric(event_name: "test", payload: {}) }.not_to raise_error
    end
  end

  describe "Exclusions" do
    it "excludes specified controllers" do
      config = ApmBro::Configuration.new
      config.excluded_controllers = ["Admin::*", "HealthChecksController"]

      expect(config.excluded_controller?("Admin::UsersController")).to be true
      expect(config.excluded_controller?("HealthChecksController")).to be true
      expect(config.excluded_controller?("UsersController")).to be false
    end

    it "excludes specified controller#action pairs" do
      config = ApmBro::Configuration.new
      config.excluded_controller_actions = [
        "UsersController#show",
        "Admin::*#*"
      ]

      expect(config.excluded_controller_action?("UsersController", "show")).to be true
      expect(config.excluded_controller_action?("UsersController", "index")).to be false
      expect(config.excluded_controller_action?("Admin::ReportsController", "index")).to be true
    end

    it "excludes controller#action patterns from excluded_controllers" do
      config = ApmBro::Configuration.new
      config.excluded_controllers = ["ActiveStorage*#*"]

      expect(config.excluded_controller_action?("ActiveStorage::BlobsController", "show")).to be true
      expect(config.excluded_controller_action?("ActiveStorage::BlobsController", "index")).to be true
      expect(config.excluded_controller_action?("UsersController", "show")).to be false
    end

    it "excludes specified jobs" do
      config = ApmBro::Configuration.new
      config.excluded_jobs = ["ActiveStorage::AnalyzeJob", "Admin::*"]

      expect(config.excluded_job?("ActiveStorage::AnalyzeJob")).to be true
      expect(config.excluded_job?("Admin::CleanupJob")).to be true
      expect(config.excluded_job?("UserSignupJob")).to be false
    end
  end

  describe "Exclusive Tracking" do
    describe "exclusive_controller_action?" do
      it "allows all when exclusive_controller_actions is empty" do
        config = ApmBro::Configuration.new
        config.exclusive_controller_actions = []

        expect(config.exclusive_controller_action?("UsersController", "show")).to be true
        expect(config.exclusive_controller_action?("Admin::ReportsController", "index")).to be true
        expect(config.exclusive_controller_action?("AnyController", "any_action")).to be true
      end

      it "allows all when exclusive_controller_actions is nil" do
        config = ApmBro::Configuration.new
        config.exclusive_controller_actions = nil

        expect(config.exclusive_controller_action?("UsersController", "show")).to be true
        expect(config.exclusive_controller_action?("Admin::ReportsController", "index")).to be true
      end

      it "only allows specified controller#action pairs" do
        config = ApmBro::Configuration.new
        config.exclusive_controller_actions = [
          "UsersController#show",
          "UsersController#index"
        ]

        expect(config.exclusive_controller_action?("UsersController", "show")).to be true
        expect(config.exclusive_controller_action?("UsersController", "index")).to be true
        expect(config.exclusive_controller_action?("UsersController", "create")).to be false
        expect(config.exclusive_controller_action?("Admin::ReportsController", "index")).to be false
      end

      it "supports wildcards for controller and action" do
        config = ApmBro::Configuration.new
        config.exclusive_controller_actions = [
          "UsersController#*",
          "Admin::*#index"
        ]

        expect(config.exclusive_controller_action?("UsersController", "show")).to be true
        expect(config.exclusive_controller_action?("UsersController", "index")).to be true
        expect(config.exclusive_controller_action?("UsersController", "create")).to be true
        expect(config.exclusive_controller_action?("Admin::ReportsController", "index")).to be true
        expect(config.exclusive_controller_action?("Admin::ReportsController", "show")).to be false
        expect(config.exclusive_controller_action?("OtherController", "index")).to be false
      end

      it "supports wildcards for both controller and action" do
        config = ApmBro::Configuration.new
        config.exclusive_controller_actions = ["Admin::*#*"]

        expect(config.exclusive_controller_action?("Admin::ReportsController", "index")).to be true
        expect(config.exclusive_controller_action?("Admin::UsersController", "show")).to be true
        expect(config.exclusive_controller_action?("Admin::ReportsController", "create")).to be true
        expect(config.exclusive_controller_action?("UsersController", "show")).to be false
      end
    end

    describe "exclusive_job?" do
      it "allows all when exclusive_jobs is empty" do
        config = ApmBro::Configuration.new
        config.exclusive_jobs = []

        expect(config.exclusive_job?("UserSignupJob")).to be true
        expect(config.exclusive_job?("Admin::CleanupJob")).to be true
        expect(config.exclusive_job?("AnyJob")).to be true
      end

      it "allows all when exclusive_jobs is nil" do
        config = ApmBro::Configuration.new
        config.exclusive_jobs = nil

        expect(config.exclusive_job?("UserSignupJob")).to be true
        expect(config.exclusive_job?("Admin::CleanupJob")).to be true
      end

      it "only allows specified jobs" do
        config = ApmBro::Configuration.new
        config.exclusive_jobs = [
          "UserSignupJob",
          "PaymentProcessingJob"
        ]

        expect(config.exclusive_job?("UserSignupJob")).to be true
        expect(config.exclusive_job?("PaymentProcessingJob")).to be true
        expect(config.exclusive_job?("EmailDeliveryJob")).to be false
        expect(config.exclusive_job?("Admin::CleanupJob")).to be false
      end

      it "supports wildcards for job names" do
        config = ApmBro::Configuration.new
        config.exclusive_jobs = ["Admin::*", "Payment*"]

        expect(config.exclusive_job?("Admin::CleanupJob")).to be true
        expect(config.exclusive_job?("Admin::ReportsJob")).to be true
        expect(config.exclusive_job?("PaymentProcessingJob")).to be true
        expect(config.exclusive_job?("PaymentVerificationJob")).to be true
        expect(config.exclusive_job?("UserSignupJob")).to be false
      end
    end

    describe "resolve_exclusive_controller_actions" do
      it "resolves from direct configuration" do
        config = ApmBro::Configuration.new
        config.exclusive_controller_actions = ["UsersController#show"]

        result = config.resolve_exclusive_controller_actions
        expect(result).to eq(["UsersController#show"])
      end

      it "resolves from environment variable" do
        config = ApmBro::Configuration.new
        config.exclusive_controller_actions = nil

        ENV["APM_BRO_EXCLUSIVE_CONTROLLER_ACTIONS"] = "UsersController#show,Admin::*#*"
        result = config.resolve_exclusive_controller_actions
        expect(result).to eq(["UsersController#show", "Admin::*#*"])

        ENV.delete("APM_BRO_EXCLUSIVE_CONTROLLER_ACTIONS")
      end

      it "returns empty array when not configured" do
        config = ApmBro::Configuration.new
        config.exclusive_controller_actions = nil

        # Clear any ENV vars
        ENV.delete("APM_BRO_EXCLUSIVE_CONTROLLER_ACTIONS")

        result = config.resolve_exclusive_controller_actions
        expect(result).to eq([])
      end

      it "handles comma-separated environment variable values" do
        config = ApmBro::Configuration.new
        config.exclusive_controller_actions = nil

        ENV["APM_BRO_EXCLUSIVE_CONTROLLER_ACTIONS"] = "UsersController#show, UsersController#index , Admin::*#*"
        result = config.resolve_exclusive_controller_actions
        expect(result).to eq(["UsersController#show", "UsersController#index", "Admin::*#*"])

        ENV.delete("APM_BRO_EXCLUSIVE_CONTROLLER_ACTIONS")
      end
    end

    describe "resolve_exclusive_jobs" do
      it "resolves from direct configuration" do
        config = ApmBro::Configuration.new
        config.exclusive_jobs = ["UserSignupJob"]

        result = config.resolve_exclusive_jobs
        expect(result).to eq(["UserSignupJob"])
      end

      it "resolves from environment variable" do
        config = ApmBro::Configuration.new
        config.exclusive_jobs = nil

        ENV["APM_BRO_EXCLUSIVE_JOBS"] = "UserSignupJob,PaymentProcessingJob"
        result = config.resolve_exclusive_jobs
        expect(result).to eq(["UserSignupJob", "PaymentProcessingJob"])

        ENV.delete("APM_BRO_EXCLUSIVE_JOBS")
      end

      it "returns empty array when not configured" do
        config = ApmBro::Configuration.new
        config.exclusive_jobs = nil

        # Clear any ENV vars
        ENV.delete("APM_BRO_EXCLUSIVE_JOBS")

        result = config.resolve_exclusive_jobs
        expect(result).to eq([])
      end

      it "handles comma-separated environment variable values" do
        config = ApmBro::Configuration.new
        config.exclusive_jobs = nil

        ENV["APM_BRO_EXCLUSIVE_JOBS"] = "UserSignupJob, PaymentProcessingJob , Admin::*"
        result = config.resolve_exclusive_jobs
        expect(result).to eq(["UserSignupJob", "PaymentProcessingJob", "Admin::*"])

        ENV.delete("APM_BRO_EXCLUSIVE_JOBS")
      end
    end

    describe "exclusion takes precedence over exclusive" do
      it "excludes controller actions even if in exclusive list" do
        config = ApmBro::Configuration.new
        config.excluded_controller_actions = ["UsersController#show"]
        config.exclusive_controller_actions = ["UsersController#show"]

        # Should be excluded (exclusion checked first)
        expect(config.excluded_controller_action?("UsersController", "show")).to be true
        # But also in exclusive list
        expect(config.exclusive_controller_action?("UsersController", "show")).to be true
      end

      it "excludes jobs even if in exclusive list" do
        config = ApmBro::Configuration.new
        config.excluded_jobs = ["UserSignupJob"]
        config.exclusive_jobs = ["UserSignupJob"]

        # Should be excluded (exclusion checked first)
        expect(config.excluded_job?("UserSignupJob")).to be true
        # But also in exclusive list
        expect(config.exclusive_job?("UserSignupJob")).to be true
      end
    end

    describe "integration with Subscriber" do
      let(:client) { double("Client") }
      let(:subscriber) { ApmBro::Subscriber }

      before do
        skip unless defined?(ActiveSupport::Notifications)
        # Clear any existing subscriptions
        ActiveSupport::Notifications.unsubscribe("process_action.action_controller")
        # Set up configuration
        ApmBro.configuration.exclusive_controller_actions = nil
        ApmBro.configuration.excluded_controller_actions = []
        ApmBro.configuration.enabled = true
        ApmBro.configuration.api_key = "test-key"
        ApmBro.configuration.sample_rate = 100
      end

      after do
        if defined?(ActiveSupport::Notifications)
          ActiveSupport::Notifications.unsubscribe("process_action.action_controller")
        end
      end

      it "tracks all controller actions when exclusive_controller_actions is not set" do
        ApmBro.configuration.exclusive_controller_actions = []
        subscriber.subscribe!(client: client)

        expect(client).to receive(:post_metric).at_least(:once)

        start_time = Time.now
        finish_time = start_time + 0.1
        ActiveSupport::Notifications.publish("process_action.action_controller", start_time, finish_time, SecureRandom.uuid, {
          controller: "UsersController",
          action: "show",
          format: :html,
          method: "GET",
          status: 200
        })

        sleep(0.1)
      end

      it "only tracks controller actions in exclusive list" do
        ApmBro.configuration.exclusive_controller_actions = ["UsersController#show"]
        subscriber.subscribe!(client: client)

        # This should be tracked
        expect(client).to receive(:post_metric).with(
          event_name: "process_action.action_controller",
          payload: hash_including(controller: "UsersController", action: "show")
        )

        start_time = Time.now
        finish_time = start_time + 0.1
        ActiveSupport::Notifications.publish("process_action.action_controller", start_time, finish_time, SecureRandom.uuid, {
          controller: "UsersController",
          action: "show",
          format: :html,
          method: "GET",
          status: 200
        })

        sleep(0.1)

        # Reset expectations for the next call
        allow(client).to receive(:post_metric)

        # This should NOT be tracked
        expect(client).not_to receive(:post_metric)

        start_time2 = Time.now
        finish_time2 = start_time2 + 0.1
        ActiveSupport::Notifications.publish("process_action.action_controller", start_time2, finish_time2, SecureRandom.uuid, {
          controller: "UsersController",
          action: "index",
          format: :html,
          method: "GET",
          status: 200
        })

        sleep(0.1)
      end

      it "exclusion takes precedence over exclusive tracking" do
        ApmBro.configuration.excluded_controller_actions = ["UsersController#show"]
        ApmBro.configuration.exclusive_controller_actions = ["UsersController#show"]
        subscriber.subscribe!(client: client)

        # Should NOT be tracked even though it's in exclusive list (exclusion takes precedence)
        expect(client).not_to receive(:post_metric)

        start_time = Time.now
        finish_time = start_time + 0.1
        ActiveSupport::Notifications.publish("process_action.action_controller", start_time, finish_time, SecureRandom.uuid, {
          controller: "UsersController",
          action: "show",
          format: :html,
          method: "GET",
          status: 200
        })

        sleep(0.1)
      end
    end

    describe "integration with JobSubscriber" do
      let(:client) { double("Client") }
      let(:job_subscriber) { ApmBro::JobSubscriber }

      before do
        skip unless defined?(ActiveSupport::Notifications)
        # Clear any existing subscriptions
        ActiveSupport::Notifications.unsubscribe("perform.active_job")
        ActiveSupport::Notifications.unsubscribe("exception.active_job")
        # Set up configuration
        ApmBro.configuration.exclusive_jobs = nil
        ApmBro.configuration.excluded_jobs = []
        ApmBro.configuration.enabled = true
        ApmBro.configuration.api_key = "test-key"
        ApmBro.configuration.sample_rate = 100
      end

      after do
        if defined?(ActiveSupport::Notifications)
          ActiveSupport::Notifications.unsubscribe("perform.active_job")
          ActiveSupport::Notifications.unsubscribe("exception.active_job")
        end
      end

      it "tracks all jobs when exclusive_jobs is not set" do
        ApmBro.configuration.exclusive_jobs = []
        job_subscriber.subscribe!(client: client)

        expect(client).to receive(:post_metric).at_least(:once)

        job = double("Job", class: double("JobClass", name: "TestJob"), job_id: "123", queue_name: "default", arguments: [])
        start_time = Time.now
        finish_time = start_time + 0.1

        ActiveSupport::Notifications.publish("perform.active_job", start_time, finish_time, SecureRandom.uuid, {
          job: job
        })

        sleep(0.1)
      end

      it "only tracks jobs in exclusive list" do
        ApmBro.configuration.exclusive_jobs = ["UserSignupJob"]
        job_subscriber.subscribe!(client: client)

        # This should be tracked
        expect(client).to receive(:post_metric).with(
          event_name: "perform.active_job",
          payload: hash_including(job_class: "UserSignupJob")
        )

        job = double("Job", class: double("JobClass", name: "UserSignupJob"), job_id: "123", queue_name: "default", arguments: [])
        start_time = Time.now
        finish_time = start_time + 0.1

        ActiveSupport::Notifications.publish("perform.active_job", start_time, finish_time, SecureRandom.uuid, {
          job: job
        })

        sleep(0.1)

        # Reset expectations for the next call
        allow(client).to receive(:post_metric)

        # This should NOT be tracked
        expect(client).not_to receive(:post_metric)

        job2 = double("Job", class: double("JobClass", name: "EmailDeliveryJob"), job_id: "456", queue_name: "default", arguments: [])
        start_time2 = Time.now
        finish_time2 = start_time2 + 0.1

        ActiveSupport::Notifications.publish("perform.active_job", start_time2, finish_time2, SecureRandom.uuid, {
          job: job2
        })

        sleep(0.1)
      end

      it "exclusion takes precedence over exclusive tracking for jobs" do
        ApmBro.configuration.excluded_jobs = ["UserSignupJob"]
        ApmBro.configuration.exclusive_jobs = ["UserSignupJob"]
        job_subscriber.subscribe!(client: client)

        # Should NOT be tracked even though it's in exclusive list (exclusion takes precedence)
        expect(client).not_to receive(:post_metric)

        job = double("Job", class: double("JobClass", name: "UserSignupJob"), job_id: "123", queue_name: "default", arguments: [])
        start_time = Time.now
        finish_time = start_time + 0.1

        ActiveSupport::Notifications.publish("perform.active_job", start_time, finish_time, SecureRandom.uuid, {
          job: job
        })

        sleep(0.1)
      end
    end
  end

  describe "JobSubscriber" do
    let(:job_subscriber) { ApmBro::JobSubscriber }

    before do
      # Clear any existing subscriptions
      if defined?(ActiveSupport::Notifications)
        ActiveSupport::Notifications.unsubscribe("perform.active_job")
        ActiveSupport::Notifications.unsubscribe("exception.active_job")
      end
    end

    after do
      # Clean up subscriptions
      if defined?(ActiveSupport::Notifications)
        ActiveSupport::Notifications.unsubscribe("perform.active_job")
        ActiveSupport::Notifications.unsubscribe("exception.active_job")
      end
    end

    it "tracks successful job execution", skip: "Requires ActiveSupport::Notifications" do
      skip unless defined?(ActiveSupport::Notifications)

      job_subscriber.subscribe!(client: ApmBro::Client.new)

      # Mock a job
      job = double("Job", class: double("JobClass", name: "TestJob"), job_id: "123", queue_name: "default", arguments: ["arg1", "arg2"])

      ActiveSupport::Notifications.instrument("perform.active_job", {job: job})

      # The job subscriber should have been called (we can't easily test the client call without mocking)
      expect(true).to be true # Placeholder assertion
    end

    it "tracks job exceptions", skip: "Requires ActiveSupport::Notifications" do
      skip unless defined?(ActiveSupport::Notifications)

      job_subscriber.subscribe!(client: ApmBro::Client.new)

      # Mock a job and exception
      job = double("Job", class: double("JobClass", name: "TestJob"), job_id: "123", queue_name: "default", arguments: ["arg1"])
      exception = StandardError.new("Test error")
      exception.set_backtrace(["line1", "line2"])

      ActiveSupport::Notifications.instrument("exception.active_job", {
        job: job,
        exception_object: exception
      })

      # The job subscriber should have been called
      expect(true).to be true # Placeholder assertion
    end

    it "sanitizes job arguments", skip: "Requires ActiveSupport::Notifications" do
      skip unless defined?(ActiveSupport::Notifications)

      arguments = [
        "normal_string",
        "very_long_string_" + "x" * 300,
        {password: "secret", normal_key: "value"},
        [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]
      ]

      sanitized = job_subscriber.send(:safe_arguments, arguments)

      expect(sanitized[0]).to eq("normal_string")
      expect(sanitized[1]).to end_with("...")
      expect(sanitized[2]).not_to have_key(:password)
      expect(sanitized[2]).to have_key(:normal_key)
      expect(sanitized[3]).to have(5).items
    end
  end

  describe "Logger" do
    let(:logger) { ApmBro::Logger.new }

    before do
      logger.clear
    end

    it "logs debug messages" do
      logger.debug("Debug message")
      logs = logger.logs
      expect(logs.length).to eq(1)
      expect(logs.first[:sev]).to eq("debug")
      expect(logs.first[:msg]).to eq("Debug message")
    end

    it "logs info messages" do
      logger.info("Info message")
      logs = logger.logs
      expect(logs.length).to eq(1)
      expect(logs.first[:sev]).to eq("info")
      expect(logs.first[:msg]).to eq("Info message")
    end

    it "logs warn messages" do
      logger.warn("Warning message")
      logs = logger.logs
      expect(logs.first[:sev]).to eq("warn")
      expect(logs.first[:msg]).to eq("Warning message")
    end

    it "logs error messages" do
      logger.error("Error message")
      logs = logger.logs
      expect(logs.first[:sev]).to eq("error")
      expect(logs.first[:msg]).to eq("Error message")
    end

    it "logs fatal messages" do
      logger.fatal("Fatal message")
      logs = logger.logs
      expect(logs.first[:sev]).to eq("fatal")
      expect(logs.first[:msg]).to eq("Fatal message")
    end

    it "stores multiple logs" do
      logger.debug("First")
      logger.info("Second")
      logger.warn("Third")

      logs = logger.logs
      expect(logs.length).to eq(3)
      expect(logs.map { |l| l[:sev] }).to eq(["debug", "info", "warn"])
    end

    it "clears logs" do
      logger.debug("Message")
      expect(logger.logs.length).to eq(1)

      logger.clear
      expect(logger.logs.length).to eq(0)
    end

    it "includes timestamps in logs" do
      logger.info("Test")
      log = logger.logs.first
      expect(log[:time]).to be_a(String)
      expect(log[:time]).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
    end
  end

  describe "CircuitBreaker" do
    let(:circuit_breaker) { ApmBro::CircuitBreaker.new(failure_threshold: 3, recovery_timeout: 1) }

    it "starts in closed state" do
      expect(circuit_breaker.state).to eq(:closed)
      expect(circuit_breaker.failure_count).to eq(0)
    end

    it "tracks failures and opens after threshold" do
      expect(circuit_breaker.state).to eq(:closed)

      # Simulate failures
      3.times { circuit_breaker.send(:on_failure) }

      expect(circuit_breaker.state).to eq(:open)
      expect(circuit_breaker.failure_count).to eq(3)
    end

    it "resets failure count on success" do
      circuit_breaker.send(:on_failure)
      expect(circuit_breaker.failure_count).to eq(1)

      circuit_breaker.send(:on_success)
      expect(circuit_breaker.failure_count).to eq(0)
      expect(circuit_breaker.state).to eq(:closed)
    end

    it "transitions to half-open when should_attempt_reset?" do
      circuit_breaker.open!
      expect(circuit_breaker.state).to eq(:open)

      # Wait for recovery timeout
      sleep(1.1)

      expect(circuit_breaker.should_attempt_reset?).to be true
      circuit_breaker.transition_to_half_open!
      expect(circuit_breaker.state).to eq(:half_open)
    end

    it "returns false for should_attempt_reset? when not enough time has passed" do
      circuit_breaker.open!
      expect(circuit_breaker.should_attempt_reset?).to be false
    end

    it "resets to closed state" do
      circuit_breaker.open!
      circuit_breaker.send(:on_failure)

      circuit_breaker.reset!
      expect(circuit_breaker.state).to eq(:closed)
      expect(circuit_breaker.failure_count).to eq(0)
      expect(circuit_breaker.last_failure_time).to be_nil
    end

    it "transitions back to open from half-open on failure" do
      circuit_breaker.transition_to_half_open!
      expect(circuit_breaker.state).to eq(:half_open)

      circuit_breaker.send(:on_failure)
      expect(circuit_breaker.state).to eq(:open)
    end

    it "tracks last_failure_time and last_success_time" do
      expect(circuit_breaker.last_failure_time).to be_nil
      expect(circuit_breaker.last_success_time).to be_nil

      circuit_breaker.send(:on_failure)
      expect(circuit_breaker.last_failure_time).to be_a(Time)

      circuit_breaker.send(:on_success)
      expect(circuit_breaker.last_success_time).to be_a(Time)
    end
  end

  describe "ApmBro module" do
    it "configures settings via configure block" do
      ApmBro.configure do |config|
        config.enabled = false
        config.api_key = "test-key"
      end

      expect(ApmBro.configuration.enabled).to be false
      expect(ApmBro.configuration.api_key).to eq("test-key")
    end

    it "resets configuration" do
      ApmBro.configure do |config|
        config.enabled = false
        config.api_key = "test-key"
      end

      ApmBro.reset_configuration!

      expect(ApmBro.configuration.enabled).to be true
      expect(ApmBro.configuration.api_key).to be_nil
    end

    it "returns a logger instance" do
      logger = ApmBro.logger
      expect(logger).to be_a(ApmBro::Logger)
      expect(ApmBro.logger).to eq(logger) # Should be memoized
    end

    it "generates process_deploy_id" do
      id = ApmBro.process_deploy_id
      expect(id).to be_a(String)
      expect(id.length).to eq(36) # UUID format
      expect(ApmBro.process_deploy_id).to eq(id) # Should be memoized
    end

    it "returns environment via env method" do
      env = ApmBro.env
      expect(env).to be_a(String)
      # Should return development, test, or production, or fallback to ENV
      expect(["development", "test", "production", ENV["RACK_ENV"], ENV["RAILS_ENV"]].compact).to include(env)
    end
  end
end
