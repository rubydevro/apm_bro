# frozen_string_literal: true

RSpec.describe ApmBro do
  it "has a version number" do
    expect(ApmBro::VERSION).not_to be nil
  end

  describe "configuration" do
    it "has default SQL tracking configuration" do
      config = ApmBro::Configuration.new
      expect(config.track_sql_queries).to be true
      expect(config.max_sql_queries).to eq(50)
      expect(config.sanitize_sql_queries).to be true
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
      sql_subscriber.subscribe!(max_queries: 10, sanitize_queries: true)
      
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
      sql_subscriber.subscribe!(max_queries: 2, sanitize_queries: true)
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
end
