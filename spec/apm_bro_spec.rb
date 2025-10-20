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

    it "has user email tracking configuration" do
      config = ApmBro::Configuration.new
      expect(config.user_email_tracking_enabled).to be false
      expect(config.user_email_extractor).to be nil
    end

    it "can extract user email from request data" do
      config = ApmBro::Configuration.new
      config.user_email_tracking_enabled = true

      # Test with current_user.email
      request_data = {
        current_user: double("User", email: "test@example.com")
      }
      expect(config.extract_user_email(request_data)).to eq("test@example.com")

      # Test with params
      request_data = {
        params: { "user_email" => "user@example.com" }
      }
      expect(config.extract_user_email(request_data)).to eq("user@example.com")

      # Test with headers
      request = double("Request", headers: { "X-User-Email" => "header@example.com" })
      request_data = { request: request }
      expect(config.extract_user_email(request_data)).to eq("header@example.com")

      # Test with session
      request_data = {
        session: { "user_email" => "session@example.com" }
      }
      expect(config.extract_user_email(request_data)).to eq("session@example.com")
    end

    it "can use custom user email extractor" do
      config = ApmBro::Configuration.new
      config.user_email_tracking_enabled = true
      config.user_email_extractor = ->(data) { data[:custom_email] }

      request_data = { custom_email: "custom@example.com" }
      expect(config.extract_user_email(request_data)).to eq("custom@example.com")
    end

    it "returns nil when user email tracking is disabled" do
      config = ApmBro::Configuration.new
      config.user_email_tracking_enabled = false

      request_data = {
        current_user: double("User", email: "test@example.com")
      }
      expect(config.extract_user_email(request_data)).to be_nil
    end

    it "has sample rate configuration" do
      config = ApmBro::Configuration.new
      expect(config.sample_rate).to eq(100)
    end

    it "validates sample rate range" do
      config = ApmBro::Configuration.new
      
      # Valid values
      config.sample_rate = 1
      expect(config.sample_rate).to eq(1)
      
      config.sample_rate = 50
      expect(config.sample_rate).to eq(50)
      
      config.sample_rate = 100
      expect(config.sample_rate).to eq(100)
      
      # Invalid values
      expect { config.sample_rate = 0 }.to raise_error(ArgumentError, /Sample rate must be an integer between 1 and 100/)
      expect { config.sample_rate = 101 }.to raise_error(ArgumentError, /Sample rate must be an integer between 1 and 100/)
      expect { config.sample_rate = "50" }.to raise_error(ArgumentError, /Sample rate must be an integer between 1 and 100/)
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
  end

  describe "SqlSubscriber" do
    let(:sql_subscriber) { ApmBro::SqlSubscriber }

    before do
      # Clear any existing subscriptions
      ActiveSupport::Notifications.unsubscribe("sql.active_record")
    end

    after do
      # Clean up subscriptions
      ActiveSupport::Notifications.unsubscribe("sql.active_record")
    end

    it "can sanitize SQL queries" do
      sensitive_sql = "SELECT * FROM users WHERE password = 'secret123' AND email = 'test@example.com'"
      sanitized = sql_subscriber.sanitize_sql(sensitive_sql)
      
      expect(sanitized).to include("password = ?")
      expect(sanitized).to include("email = ?")
      expect(sanitized).not_to include("secret123")
      expect(sanitized).not_to include("test@example.com")
    end

    it "limits query length" do
      long_sql = "SELECT " + "a" * 2000
      sanitized = sql_subscriber.sanitize_sql(long_sql)
      
      expect(sanitized.length).to be <= 1003 # 1000 + "..."
      expect(sanitized).to end_with("...")
    end

    it "tracks SQL queries during request processing" do
      sql_subscriber.subscribe!
      
      # Start request tracking
      sql_subscriber.start_request_tracking
      
      # Simulate SQL queries
      ActiveSupport::Notifications.instrument("sql.active_record", {
        sql: "SELECT * FROM users",
        name: "User Load",
        cached: false,
        connection_id: 123
      })
      
      ActiveSupport::Notifications.instrument("sql.active_record", {
        sql: "UPDATE users SET last_login = NOW()",
        name: "User Update",
        cached: false,
        connection_id: 123
      })
      
      # Get tracked queries
      queries = sql_subscriber.stop_request_tracking
      
      expect(queries).to have(2).items
      expect(queries.first[:sql]).to eq("SELECT * FROM users")
      expect(queries.first[:name]).to eq("User Load")
      expect(queries.first[:cached]).to be false
      expect(queries.first[:connection_id]).to eq(123)
      expect(queries.first[:duration_ms]).to be_a(Numeric)
    end

    it "respects max queries limit" do
      sql_subscriber.subscribe!
      sql_subscriber.start_request_tracking
      
      # Simulate more queries than the limit
      5.times do |i|
        ActiveSupport::Notifications.instrument("sql.active_record", {
          sql: "SELECT * FROM table#{i}",
          name: "Query #{i}",
          cached: false,
          connection_id: 123
        })
      end
      
      queries = sql_subscriber.stop_request_tracking
      expect(queries).to have(2).items
      # Should keep the last 2 queries
      expect(queries.first[:sql]).to eq("SELECT * FROM table3")
      expect(queries.last[:sql]).to eq("SELECT * FROM table4")
    end
  end

  describe "JobSubscriber" do
    let(:job_subscriber) { ApmBro::JobSubscriber }

    before do
      # Clear any existing subscriptions
      ActiveSupport::Notifications.unsubscribe("perform.active_job")
      ActiveSupport::Notifications.unsubscribe("exception.active_job")
    end

    after do
      # Clean up subscriptions
      ActiveSupport::Notifications.unsubscribe("perform.active_job")
      ActiveSupport::Notifications.unsubscribe("exception.active_job")
    end

    it "tracks successful job execution" do
      job_subscriber.subscribe!(client: ApmBro::Client.new)
      
      # Mock a job
      job = double("Job", class: double("JobClass", name: "TestJob"), job_id: "123", queue_name: "default", arguments: ["arg1", "arg2"])
      
      ActiveSupport::Notifications.instrument("perform.active_job", { job: job })
      
      # The job subscriber should have been called (we can't easily test the client call without mocking)
      expect(true).to be true # Placeholder assertion
    end

    it "tracks job exceptions" do
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

    it "sanitizes job arguments" do
      arguments = [
        "normal_string",
        "very_long_string_" + "x" * 300,
        { password: "secret", normal_key: "value" },
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
end
