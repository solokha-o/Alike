# Offline tests for the price and win-back commands of
# tools/app_store_iap_metadata.rb. No network: a stub client answers the GET
# requests and records every write, so "a dry run writes nothing" and "a
# conflict writes nothing" are assertions, not claims.
#
#   ruby tools/app_store_iap_metadata_test.rb
require "minitest/autorun"
require "stringio"
require "tmpdir"
require_relative "app_store_iap_metadata"

TODAY = Date.new(2026, 11, 13)
D_DAY = "2026-11-26"

class StubClient
  attr_reader :writes

  # prices: [[territory, currency, point_id, price, start_date_or_nil, preserved]]
  def initialize(prices:, win_back_offers: [], win_back_prices: {})
    @prices = prices
    @win_back_offers = win_back_offers
    @win_back_prices = win_back_prices
    @writes = []
    @next_id = 0
  end

  # Price points per territory: "<territory>-<price>" ids. Equalizations of
  # the USA 9.99 point give DEU 9.99 and UKR 11.99, as App Store Connect did
  # on 13.11.2026; USA 1.99 gives DEU 1.99 and UKR 2.49.
  POINTS = {
    "USA" => %w[1.99 5.99 8.99 9.99],
    "DEU" => %w[1.99 6.99 9.99],
    "UKR" => %w[2.49 6.99 11.99]
  }.freeze
  EQUALIZATIONS = {
    "USA-9.99" => { "DEU" => "9.99", "UKR" => "11.99" },
    "USA-1.99" => { "DEU" => "1.99", "UKR" => "2.49" }
  }.freeze
  CURRENCIES = { "USA" => "USD", "DEU" => "EUR", "UKR" => "USD" }.freeze

  def get(path)
    case path
    when %r{\A/v1/apps\?}
      { "data" => [{ "id" => "app1" }] }
    else
      raise "unexpected GET #{path}"
    end
  end

  def paged(path)
    case path
    when %r{/subscriptionGroups\?}
      [{ "id" => "group1" }]
    when %r{/subscriptionGroups/group1/subscriptions\?}
      [{ "id" => "sub-monthly", "attributes" => { "productId" => "com.alike.app.pro.monthly" } }]
    when %r{/pricePoints\?}
      territory = URI.decode_www_form(path.split("?", 2).last).to_h.fetch("filter[territory]")
      POINTS.fetch(territory, []).map { |price| { "id" => "#{territory}-#{price}", "attributes" => { "customerPrice" => price } } }
    when %r{/winBackOffers\?}
      @win_back_offers
    when %r{/winBackOffers/([^/]+)/prices}
      @win_back_prices.fetch(Regexp.last_match(1), {}).map do |territory, point|
        { "relationships" => { "territory" => { "data" => { "id" => territory } },
                               "subscriptionPricePoint" => { "data" => { "id" => point } } } }
      end
    else
      raise "unexpected paged #{path}"
    end
  end

  def paged_with_included(path)
    case path
    when %r{/subscriptionPricePoints/([^/]+)/equalizations}
      base = Regexp.last_match(1)
      data = EQUALIZATIONS.fetch(base).map do |territory, price|
        { "id" => "#{territory}-#{price}", "attributes" => { "customerPrice" => price },
          "relationships" => { "territory" => { "data" => { "id" => territory } } } }
      end
      { data: data, included: territories }
    when %r{/subscriptions/sub-monthly/prices}
      data = @prices.each_with_index.map do |(territory, _currency, point, _price, start, preserved), index|
        { "id" => "row#{index}", "attributes" => { "startDate" => start, "preserved" => preserved },
          "relationships" => { "territory" => { "data" => { "id" => territory } },
                               "subscriptionPricePoint" => { "data" => { "id" => point } } } }
      end
      points = @prices.map { |row| { "type" => "subscriptionPricePoints", "id" => row[2], "attributes" => { "customerPrice" => row[3] } } }
      { data: data, included: points + territories }
    else
      raise "unexpected paged_with_included #{path}"
    end
  end

  def post(path, body)
    @writes << [:post, path, body]
    @next_id += 1
    { "data" => { "id" => "new#{@next_id}" } }
  end

  def delete(path)
    @writes << [:delete, path]
    {}
  end

  private

  def territories
    CURRENCIES.map { |id, currency| { "type" => "territories", "id" => id, "attributes" => { "currency" => currency } } }
  end
end

LIVE_PRICES = [
  ["USA", "USD", "USA-5.99", "5.99", nil, false],
  ["DEU", "EUR", "DEU-6.99", "6.99", nil, false],
  ["UKR", "USD", "UKR-6.99", "6.99", nil, false]
].freeze

def experiment_a_options(**extra)
  {
    product: "com.alike.app.pro.monthly", bundle_id: "com.alike.app", base_territory: "USA", base_price: "9.99",
    overrides: [["USA", BigDecimal("8.99")]], start_date: D_DAY, preserve_current_price: true, apply: false
  }.merge(extra)
end

class SchedulePriceTest < Minitest::Test
  def run_schedule(client, **extra)
    io = StringIO.new
    plan = schedule_subscription_price(client, experiment_a_options(**extra), today: TODAY, io: io)
    [plan, io.string]
  end

  def test_dry_run_plans_the_owner_decision_and_writes_nothing
    client = StubClient.new(prices: LIVE_PRICES)
    plan, output = run_schedule(client)

    assert_empty client.writes
    assert_equal %w[create create create], plan.map { |entry| entry[:action] }
    assert_includes output, "USA USD current=5.99 new=8.99 (override) start=2026-11-26 preserveCurrentPrice=true action=create"
    assert_includes output, "DEU EUR current=6.99 new=9.99 start=2026-11-26 preserveCurrentPrice=true action=create"
    assert_includes output, "UKR USD current=6.99 new=11.99 start=2026-11-26 preserveCurrentPrice=true action=create"
    assert_includes output, "summary territories=3 create=3 unchanged=0 conflict=0"
  end

  def test_apply_posts_one_price_per_territory_with_the_documented_fields
    client = StubClient.new(prices: LIVE_PRICES)
    run_schedule(client, apply: true)

    assert_equal 3, client.writes.length
    method, path, body = client.writes.find { |write| write[2].dig(:data, :relationships, :territory, :data, :id) == "USA" }
    assert_equal :post, method
    assert_equal "/v1/subscriptionPrices", path
    assert_equal({ startDate: "2026-11-26", preserveCurrentPrice: true }, body.dig(:data, :attributes))
    assert_equal "USA-8.99", body.dig(:data, :relationships, :subscriptionPricePoint, :data, :id)
    assert_equal "sub-monthly", body.dig(:data, :relationships, :subscription, :data, :id)
  end

  def test_rerun_after_apply_is_unchanged
    scheduled = LIVE_PRICES + [
      ["USA", "USD", "USA-8.99", "8.99", D_DAY, true],
      ["DEU", "EUR", "DEU-9.99", "9.99", D_DAY, true],
      ["UKR", "USD", "UKR-11.99", "11.99", D_DAY, true]
    ]
    client = StubClient.new(prices: scheduled)
    plan, output = run_schedule(client, apply: true)

    assert_empty client.writes
    assert_equal %w[unchanged unchanged unchanged], plan.map { |entry| entry[:action] }
    assert_includes output, "summary territories=3 create=0 unchanged=3 conflict=0"
  end

  def test_a_different_scheduled_change_is_a_conflict_and_nothing_is_written
    scheduled = LIVE_PRICES + [["DEU", "EUR", "DEU-9.99", "9.99", "2026-12-01", true]]
    client = StubClient.new(prices: scheduled)

    error = assert_raises(RuntimeError) { run_schedule(client, apply: true) }
    assert_match(/1 territory conflict\(s\); nothing written.*DEU/, error.message)
    assert_empty client.writes
  end

  def test_a_scheduled_row_with_another_preserved_value_is_unchanged_with_a_warning
    scheduled = LIVE_PRICES + [["USA", "USD", "USA-8.99", "8.99", D_DAY, false]]
    client = StubClient.new(prices: scheduled)
    plan, output = run_schedule(client, apply: true)

    assert_equal "unchanged", plan.find { |entry| entry[:territory] == "USA" }[:action]
    assert_includes output, "live preserved=false, check the preserve choice"
    assert_equal 2, client.writes.length
  end

  def test_a_missing_price_point_names_the_nearest_ones
    client = StubClient.new(prices: LIVE_PRICES)
    error = assert_raises(RuntimeError) { run_schedule(client, overrides: [["USA", BigDecimal("8.49")]]) }
    assert_match(/USA has no price point at 8.49; nearest: 8.99/, error.message)
  end

  def test_an_override_for_a_territory_that_is_not_sold_fails_before_any_write
    client = StubClient.new(prices: LIVE_PRICES)
    error = assert_raises(RuntimeError) do
      run_schedule(client, apply: true, overrides: [["USA", BigDecimal("8.99")], ["XYZ", BigDecimal("1.99")]])
    end
    assert_match(/not sold.*XYZ/, error.message)
    assert_empty client.writes
  end

  def test_start_date_must_be_in_the_future_and_preserve_must_be_chosen
    client = StubClient.new(prices: LIVE_PRICES)
    assert_raises(RuntimeError) { run_schedule(client, start_date: TODAY.iso8601) }
    assert_raises(RuntimeError) { run_schedule(client, preserve_current_price: nil) }
    assert_empty client.writes
  end

  def test_snapshot_then_prices_file_restores_the_old_prices
    Dir.mktmpdir do |dir|
      snapshot = File.join(dir, "monthly.json")
      run_schedule(StubClient.new(prices: LIVE_PRICES), snapshot_path: snapshot)
      saved = JSON.parse(File.read(snapshot))
      assert_equal({ "pricePointId" => "DEU-6.99", "customerPrice" => "6.99", "currency" => "EUR" }, saved.dig("prices", "DEU"))

      after_d = LIVE_PRICES + [
        ["USA", "USD", "USA-8.99", "8.99", "2026-11-26", true],
        ["DEU", "EUR", "DEU-9.99", "9.99", "2026-11-26", true],
        ["UKR", "USD", "UKR-11.99", "11.99", "2026-11-26", true]
      ]
      client = StubClient.new(prices: after_d)
      io = StringIO.new
      options = experiment_a_options(prices_file: snapshot, start_date: "2027-02-12", apply: true)
      schedule_subscription_price(client, options, today: Date.new(2027, 2, 11), io: io)

      assert_includes io.string, "USA USD current=8.99 new=5.99 (file) start=2027-02-12 preserveCurrentPrice=true action=create"
      assert_equal 3, client.writes.length
    end
  end

  def test_cancel_deletes_only_the_rows_scheduled_for_that_date
    scheduled = LIVE_PRICES + [["USA", "USD", "USA-8.99", "8.99", D_DAY, true], ["DEU", "EUR", "DEU-9.99", "9.99", "2026-12-01", true]]
    client = StubClient.new(prices: scheduled)
    io = StringIO.new
    cancel_subscription_price(client, experiment_a_options, today: TODAY, io: io)
    assert_empty client.writes
    assert_includes io.string, "summary delete=1"

    cancel_subscription_price(client, experiment_a_options(apply: true), today: TODAY, io: io)
    assert_equal [[:delete, "/v1/subscriptionPrices/row3"]], client.writes
  end
end

def win_back_options(**extra)
  {
    product: "com.alike.app.pro.monthly", bundle_id: "com.alike.app", base_territory: "USA", base_price: "1.99",
    overrides: [], offer_id: "alike.winback.monthly.1", reference_name: "Win back monthly 1",
    offer_mode: "PAY_AS_YOU_GO", duration: "ONE_MONTH", period_count: 1, paid_months: 1, since_min: 1, since_max: nil,
    wait_months: nil, start_date: D_DAY, end_date: nil, priority: "NORMAL", promotion_intent: "NOT_PROMOTED", apply: false
  }.merge(extra)
end

class WinBackOfferTest < Minitest::Test
  def run_upload(client, **extra)
    io = StringIO.new
    action = upload_win_back_offer(client, win_back_options(**extra), today: TODAY, io: io)
    [action, io.string]
  end

  def test_dry_run_prints_the_prices_and_writes_nothing
    client = StubClient.new(prices: LIVE_PRICES)
    action, output = run_upload(client)

    assert_equal "create", action
    assert_empty client.writes
    assert_includes output, "USA USD offer_price=1.99 (base)"
    assert_includes output, "DEU EUR offer_price=1.99"
    assert_includes output, "UKR USD offer_price=2.49"
    assert_includes output, "summary territories=3 live_offers=0 action=create"
  end

  def test_apply_posts_the_offer_with_inline_prices
    client = StubClient.new(prices: LIVE_PRICES)
    run_upload(client, apply: true)

    assert_equal 1, client.writes.length
    _, path, body = client.writes.first
    assert_equal "/v1/winBackOffers", path
    attributes = body.dig(:data, :attributes)
    assert_equal "alike.winback.monthly.1", attributes[:offerId]
    assert_equal({ minimum: 1 }, attributes[:customerEligibilityTimeSinceLastSubscribedInMonths])
    refute attributes.key?(:endDate)
    refute attributes.key?(:customerEligibilityWaitBetweenOffersInMonths)
    assert_equal 3, body[:included].length
    usa = body[:included].find { |price| price.dig(:relationships, :territory, :data, :id) == "USA" }
    assert_equal "USA-1.99", usa.dig(:relationships, :subscriptionPricePoint, :data, :id)
    assert_equal body.dig(:data, :relationships, :prices, :data).map { |ref| ref[:id] }.sort, body[:included].map { |price| price[:id] }.sort
  end

  def test_same_offer_live_is_unchanged
    live_attributes = {
      "referenceName" => "Win back monthly 1", "offerId" => "alike.winback.monthly.1", "duration" => "ONE_MONTH",
      "offerMode" => "PAY_AS_YOU_GO", "periodCount" => 1, "customerEligibilityPaidSubscriptionDurationInMonths" => 1,
      "customerEligibilityTimeSinceLastSubscribedInMonths" => { "minimum" => 1, "maximum" => nil },
      "startDate" => D_DAY, "priority" => "NORMAL", "promotionIntent" => "NOT_PROMOTED"
    }
    live_prices = { "wb1" => { "USA" => "USA-1.99", "DEU" => "DEU-1.99", "UKR" => "UKR-2.49" } }
    client = StubClient.new(prices: LIVE_PRICES, win_back_offers: [{ "id" => "wb1", "attributes" => live_attributes }],
                            win_back_prices: live_prices)
    action, = run_upload(client, apply: true)

    assert_equal "unchanged", action
    assert_empty client.writes

    error = assert_raises(RuntimeError) { run_upload(client, apply: true, base_price: "9.99") }
    assert_match(/price DEU: "DEU-1.99" -> "DEU-9.99"/, error.message)

    error = assert_raises(RuntimeError) { run_upload(client, apply: true, wait_months: 6) }
    assert_match(/customerEligibilityWaitBetweenOffersInMonths: nil -> 6/, error.message)
    assert_empty client.writes
  end

  def test_an_override_for_a_territory_that_is_not_sold_fails
    client = StubClient.new(prices: LIVE_PRICES.reject { |row| row[0] == "UKR" })
    error = assert_raises(RuntimeError) { run_upload(client, apply: true, overrides: [["UKR", BigDecimal("2.49")]]) }
    assert_match(/not sold.*UKR/, error.message)
    assert_empty client.writes
  end

  def test_same_offer_id_with_other_values_is_a_conflict
    live = { "id" => "wb1", "attributes" => { "offerId" => "alike.winback.monthly.1", "duration" => "TWO_MONTHS" } }
    client = StubClient.new(prices: LIVE_PRICES, win_back_offers: [live])
    error = assert_raises(RuntimeError) { run_upload(client, apply: true) }

    assert_match(/exists with different values; nothing written/, error.message)
    assert_match(/duration: "TWO_MONTHS" -> "ONE_MONTH"/, error.message)
    assert_empty client.writes
  end

  def test_invalid_or_missing_parameters_fail_before_any_request
    client = StubClient.new(prices: LIVE_PRICES)
    assert_raises(RuntimeError) { run_upload(client, duration: "SEVEN_DAYS") }
    assert_raises(RuntimeError) { run_upload(client, paid_months: 30) }
    assert_raises(RuntimeError) { run_upload(client, end_date: "2026-11-27") }
    error = assert_raises(RuntimeError) { run_upload(client, offer_id: nil, since_min: nil) }
    assert_match(/--offer-id, --since-min/, error.message)
    assert_empty client.writes
  end
end

class OptionParsingTest < Minitest::Test
  def test_experiment_a_command_line
    argv = %w[schedule-subscription-price --product com.alike.app.pro.monthly --base-territory USA --base-price 9.99
              --override USA=8.99 --start-date 2026-11-26 --preserve-current-price]
    command, options, = parse_options(argv)

    assert_equal "schedule-subscription-price", command
    assert_equal [["USA", BigDecimal("8.99")]], options[:overrides]
    assert_equal true, options[:preserve_current_price]
    assert_equal false, options[:apply]
  end
end
