#!/usr/bin/env ruby
# frozen_string_literal: true

require "bigdecimal"
require "date"
require "digest/md5"
require "json"
require "net/http"
require "openssl"
require "optparse"
require "time"
require "uri"

STDOUT.sync = true

ROOT_DIR = File.expand_path("..", __dir__)
DEFAULT_METADATA_PATH = File.join(ROOT_DIR, "build", "generated", "store_upload", "iap_metadata", "app_store_connect_iap_metadata.json")
DEFAULT_ENV_PATH = File.join(ROOT_DIR, ".env")
SCREENSHOT_PATH_ENV_KEY = "ALIKE_IAP_REVIEW_SCREENSHOT_PATH"
API_BASE = "https://api.appstoreconnect.apple.com"
PRIMARY_LOCALE = "en-US"

class ApiError < StandardError
  attr_reader :status, :body

  def initialize(status, body)
    @status = status
    @body = body
    super("App Store Connect API returned HTTP #{status}: #{body}")
  end
end

def load_env_file(path)
  return unless File.file?(path)

  File.readlines(path, chomp: true).each do |line|
    stripped = line.strip
    next if stripped.empty? || stripped.start_with?("#")
    next unless stripped.include?("=")

    key, value = stripped.split("=", 2)
    key = key.strip
    value = value.strip
    value = value[1..-2] if (value.start_with?('"') && value.end_with?('"')) || (value.start_with?("'") && value.end_with?("'"))
    ENV[key] = value if ENV[key].to_s.empty?
  end
end

def require_env(key)
  value = ENV[key]
  raise "#{key} is required" if value.to_s.empty?

  value
end

class AppStoreConnectClient
  OPEN_TIMEOUT = 20
  READ_TIMEOUT = 60
  WRITE_TIMEOUT = 60

  def initialize
    @token = build_token
  end

  def get(path)
    request("GET", path)
  end

  def get_optional(path)
    get(path)
  rescue ApiError => e
    raise unless e.status == "404"

    nil
  end

  def post(path, body)
    request("POST", path, body)
  end

  def patch(path, body)
    request("PATCH", path, body)
  end

  def delete(path)
    request("DELETE", path)
  end

  def paged(path)
    records = []
    current = path

    loop do
      response = get(current)
      records.concat(response.fetch("data", []))
      next_url = response.dig("links", "next")
      break unless next_url

      current = next_url.delete_prefix(API_BASE)
    end

    records
  end

  # Same as `paged`, but keeps the `included` resources, which `prices` and
  # `equalizations` need for the territory currency and the customer price.
  def paged_with_included(path)
    records = []
    included = []
    current = path

    loop do
      response = get(current)
      records.concat(response.fetch("data", []))
      included.concat(response.fetch("included", []))
      next_url = response.dig("links", "next")
      break unless next_url

      current = next_url.delete_prefix(API_BASE)
    end

    { data: records, included: included }
  end

  def upload_operation(operation, bytes)
    uri = URI(operation.fetch("url"))
    request = Net::HTTP::Put.new(uri)
    operation.fetch("requestHeaders", []).each do |header|
      request[header.fetch("name")] = header.fetch("value")
    end
    offset = operation.fetch("offset")
    length = operation.fetch("length")
    request.body = bytes.byteslice(offset, length)

    response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT, write_timeout: WRITE_TIMEOUT) do |http|
      http.request(request)
    end
    return if response.is_a?(Net::HTTPSuccess)

    raise ApiError.new(response.code, response.body.to_s)
  end

  private

  # Required here, not at the top of the file, so the offline tests can load
  # the planners with the system Ruby, which has no jwt gem.
  def build_token
    require "jwt"
    key_id = require_env("APP_STORE_CONNECT_KEY_ID")
    issuer_id = require_env("APP_STORE_CONNECT_ISSUER_ID")
    key_material = private_key_material
    private_key = OpenSSL::PKey::EC.new(key_material)
    payload = {
      iss: issuer_id,
      exp: Time.now.to_i + 20 * 60,
      aud: "appstoreconnect-v1"
    }
    JWT.encode(payload, private_key, "ES256", { kid: key_id, typ: "JWT" })
  end

  def private_key_material
    key_path = ENV["APP_STORE_CONNECT_API_KEY_PATH"]
    return File.read(File.expand_path(key_path)) unless key_path.to_s.empty?

    content = require_env("APP_STORE_CONNECT_API_KEY_CONTENT")
    if ENV["APP_STORE_CONNECT_API_KEY_IS_BASE64"] == "true"
      content = content.unpack1("m")
    end
    content
  end

  def request(method, path, body = nil)
    uri = URI("#{API_BASE}#{path}")
    request_class = {
      "GET" => Net::HTTP::Get,
      "POST" => Net::HTTP::Post,
      "PATCH" => Net::HTTP::Patch,
      "DELETE" => Net::HTTP::Delete
    }.fetch(method)
    request = request_class.new(uri)
    request["Authorization"] = "Bearer #{@token}"
    request["Content-Type"] = "application/json" if body
    request.body = JSON.generate(body) if body

    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT, write_timeout: WRITE_TIMEOUT) do |http|
      http.request(request)
    end
    parsed = response.body.to_s.empty? ? {} : JSON.parse(response.body)
    return parsed if response.is_a?(Net::HTTPSuccess) || response.is_a?(Net::HTTPNoContent)

    raise ApiError.new(response.code, parsed)
  rescue JSON::ParserError
    raise ApiError.new(response.code, response.body.to_s)
  end
end

def app_id_for(client, bundle_id)
  query = URI.encode_www_form("filter[bundleId]" => bundle_id, "limit" => 1)
  records = client.get("/v1/apps?#{query}").fetch("data")
  raise "No App Store Connect app found for bundle id #{bundle_id}" if records.empty?

  records.first.fetch("id")
end

def localizations_by_locale(records)
  records.to_h { |record| [record.fetch("attributes").fetch("locale"), record] }
end

def payload_by_product_id(items)
  items.to_h { |item| [item.fetch("productID"), item] }
end

def payload_locales(item)
  item.fetch("localizations", []).map { |localization| localization.fetch("locale") }
end

# upload-localizations counts HTTP 400/409/422 on any non-primary locale as
# skipped and still exits 0, so a run that landed nothing looks the same as a
# run that landed everything. `status` is where that gets caught: report the
# live locales against the ones the payload carries and name what is missing,
# rather than printing a bare count a reader has to know the expected value of.
# The expectation comes from the payload, so adding a locale to the StoreKit
# file moves this check with it.
def localization_summary(expected_locales, live_records)
  live = live_records.map { |record| record.fetch("attributes").fetch("locale") }
  missing = expected_locales - live
  unexpected = live - expected_locales
  summary = "#{live.length}/#{expected_locales.length}"
  summary += " missing=#{missing.join(",")}" unless missing.empty?
  summary += " unexpected=#{unexpected.join(",")}" unless unexpected.empty?
  summary
end

def load_payload(path)
  JSON.parse(File.read(path))
end

def group_payload(payload)
  groups = payload.fetch("subscriptionGroups")
  raise "Expected exactly one subscription group in #{DEFAULT_METADATA_PATH}" unless groups.length == 1

  groups.first
end

def app_subscription_groups(client, app_id)
  client.paged("/v1/apps/#{app_id}/subscriptionGroups?limit=200")
end

def group_localizations(client, group_id)
  client.paged("/v1/subscriptionGroups/#{group_id}/subscriptionGroupLocalizations?limit=200")
end

def subscriptions(client, group_id)
  client.paged("/v1/subscriptionGroups/#{group_id}/subscriptions?limit=200")
end

def subscription_localizations(client, subscription_id)
  client.paged("/v1/subscriptions/#{subscription_id}/subscriptionLocalizations?limit=200")
end

def in_app_purchases(client, app_id)
  client.paged("/v1/apps/#{app_id}/inAppPurchasesV2?limit=200")
end

def in_app_purchase_localizations(client, iap_id)
  client.paged("/v2/inAppPurchases/#{iap_id}/inAppPurchaseLocalizations?limit=200")
end

def subscription_introductory_offers(client, subscription_id)
  client.paged("/v1/subscriptions/#{subscription_id}/introductoryOffers?limit=200&include=territory")
end

# App Store Connect requires an introductory offer to name a territory, so the
# offer has to be created once per storefront. The subscription's own price
# territories are exactly the storefronts where it can be sold, which makes
# them the right scope; the app has no availableTerritories relationship in
# this API version.
def subscription_price_territories(client, subscription_id)
  client
    .paged("/v1/subscriptions/#{subscription_id}/prices?limit=200&include=territory")
    .map { |price| price.dig("relationships", "territory", "data", "id") }
    .compact
    .uniq
    .sort
end

def subscription_review_screenshot(client, subscription_id)
  response = client.get_optional("/v1/subscriptions/#{subscription_id}/appStoreReviewScreenshot")
  response unless response&.fetch("data").nil?
end

def iap_review_screenshot(client, iap_id)
  response = client.get_optional("/v2/inAppPurchases/#{iap_id}/appStoreReviewScreenshot")
  response unless response&.fetch("data").nil?
end

def find_live_group(groups, expected_reference_name)
  groups.find { |group| group.dig("attributes", "referenceName") == expected_reference_name } || groups.first
end

def create_localization_payload(type:, attributes:, relationship_name:, related_type:, related_id:)
  {
    data: {
      type: type,
      attributes: attributes,
      relationships: {
        relationship_name => {
          data: {
            type: related_type,
            id: related_id
          }
        }
      }
    }
  }
end

def update_localization_payload(type:, id:, attributes:)
  {
    data: {
      type: type,
      id: id,
      attributes: attributes
    }
  }
end

def upsert_localizations(client:, current:, desired:, create_path:, update_path_prefix:, type:, relationship_name:, related_type:, related_id:, label:)
  existing = localizations_by_locale(current)
  created = 0
  updated = 0
  unchanged = 0
  skipped = []

  desired.each do |entry|
    locale = entry.fetch("locale")
    create_attributes = {
      locale: locale,
      name: entry.fetch("displayName")
    }
    create_attributes[:description] = entry.fetch("description") unless entry.fetch("description", "").empty?
    update_attributes = create_attributes.reject { |key, _| key == :locale }

    current_record = existing[locale]
    if current_record
      current_attributes = current_record.fetch("attributes")
      if update_attributes.all? { |key, value| current_attributes[key.to_s] == value }
        unchanged += 1
        next
      end

      client.patch(
        "#{update_path_prefix}/#{current_record.fetch("id")}",
        update_localization_payload(type: type, id: current_record.fetch("id"), attributes: update_attributes)
      )
      updated += 1
    else
      client.post(
        create_path,
        create_localization_payload(
          type: type,
          attributes: create_attributes,
          relationship_name: relationship_name,
          related_type: related_type,
          related_id: related_id
        )
      )
      created += 1
    end
  rescue ApiError => e
    if locale != PRIMARY_LOCALE && %w[400 409 422].include?(e.status)
      skipped << "#{locale}: HTTP #{e.status}"
      next
    end

    raise "#{label} #{locale} failed: #{e.message}"
  end

  puts "#{label}: created=#{created} updated=#{updated} unchanged=#{unchanged} skipped=#{skipped.length}"
  puts "  skipped #{skipped.join(", ")}" unless skipped.empty?
end

def live_state(client, payload)
  app_id = app_id_for(client, payload.fetch("appIdentifier"))
  group = find_live_group(app_subscription_groups(client, app_id), group_payload(payload).fetch("referenceName"))
  raise "No subscription group found in App Store Connect" unless group

  {
    app_id: app_id,
    group: group,
    group_localizations: group_localizations(client, group.fetch("id")),
    subscriptions: subscriptions(client, group.fetch("id")),
    iaps: in_app_purchases(client, app_id)
  }
end

def print_status(client, payload)
  state = live_state(client, payload)
  puts "app_id=#{state.fetch(:app_id)} bundle_id=#{payload.fetch("appIdentifier")}"

  group = state.fetch(:group)
  group_locs = state.fetch(:group_localizations)
  group_locale_summary = localization_summary(payload_locales(group_payload(payload)), group_locs)
  puts "subscription_group=#{group.fetch("id")} referenceName=#{group.dig("attributes", "referenceName")} localizations=#{group_locale_summary}"

  expected_subscriptions = payload_by_product_id(payload.fetch("subscriptions"))
  state.fetch(:subscriptions).each do |subscription|
    id = subscription.fetch("id")
    attrs = subscription.fetch("attributes")
    product_id = attrs.fetch("productId")
    next unless expected_subscriptions.key?(product_id)

    locs = subscription_localizations(client, id)
    screenshot = subscription_review_screenshot(client, id)
    screenshot_state = screenshot&.dig("data", "attributes", "assetDeliveryState", "state") || "missing"
    screenshot_errors = screenshot&.dig("data", "attributes", "assetDeliveryState", "errors")
    screenshot_warnings = screenshot&.dig("data", "attributes", "assetDeliveryState", "warnings")
    # One offer exists per territory, so collapse them to distinct shapes with
    # a territory count instead of printing 175 identical lines.
    offers = subscription_introductory_offers(client, id)
    offer_summary = if offers.empty?
                      "none"
                    else
                      offers
                        .group_by do |offer|
                          a = offer.fetch("attributes")
                          "#{a["offerMode"]}/#{a["duration"]}x#{a["numberOfPeriods"]}"
                        end
                        .map { |shape, group| "#{shape}(#{group.length} territories)" }
                        .join(",")
                    end
    locale_summary = localization_summary(payload_locales(expected_subscriptions.fetch(product_id)), locs)
    puts "subscription=#{product_id} id=#{id} state=#{attrs["state"]} localizations=#{locale_summary} review_screenshot=#{screenshot_state} introductory_offer=#{offer_summary}"
    puts "  screenshot_errors=#{JSON.generate(screenshot_errors)}" if screenshot_errors
    puts "  screenshot_warnings=#{JSON.generate(screenshot_warnings)}" if screenshot_warnings
  end

  expected_iaps = payload_by_product_id(payload.fetch("consumables", []))
  state.fetch(:iaps).each do |iap|
    id = iap.fetch("id")
    attrs = iap.fetch("attributes")
    product_id = attrs.fetch("productId")
    next unless expected_iaps.key?(product_id)

    locs = in_app_purchase_localizations(client, id)
    screenshot = iap_review_screenshot(client, id)
    screenshot_state = screenshot&.dig("data", "attributes", "assetDeliveryState", "state") || "missing"
    screenshot_errors = screenshot&.dig("data", "attributes", "assetDeliveryState", "errors")
    screenshot_warnings = screenshot&.dig("data", "attributes", "assetDeliveryState", "warnings")
    puts "iap=#{product_id} id=#{id} state=#{attrs["state"]} localizations=#{locs.length} review_screenshot=#{screenshot_state}"
    puts "  screenshot_errors=#{JSON.generate(screenshot_errors)}" if screenshot_errors
    puts "  screenshot_warnings=#{JSON.generate(screenshot_warnings)}" if screenshot_warnings
  end
end

def upload_localizations(client, payload)
  state = live_state(client, payload)
  group = state.fetch(:group)
  local_group = group_payload(payload)

  upsert_localizations(
    client: client,
    current: state.fetch(:group_localizations),
    desired: local_group.fetch("localizations"),
    create_path: "/v1/subscriptionGroupLocalizations",
    update_path_prefix: "/v1/subscriptionGroupLocalizations",
    type: "subscriptionGroupLocalizations",
    relationship_name: "subscriptionGroup",
    related_type: "subscriptionGroups",
    related_id: group.fetch("id"),
    label: "subscription_group_localizations"
  )

  subscriptions_by_product = payload_by_product_id(payload.fetch("subscriptions"))
  state.fetch(:subscriptions).each do |subscription|
    product_id = subscription.dig("attributes", "productId")
    local_subscription = subscriptions_by_product[product_id]
    next unless local_subscription

    upsert_localizations(
      client: client,
      current: subscription_localizations(client, subscription.fetch("id")),
      desired: local_subscription.fetch("localizations"),
      create_path: "/v1/subscriptionLocalizations",
      update_path_prefix: "/v1/subscriptionLocalizations",
      type: "subscriptionLocalizations",
      relationship_name: "subscription",
      related_type: "subscriptions",
      related_id: subscription.fetch("id"),
      label: "subscription_localizations #{product_id}"
    )
  end

  iaps_by_product = payload_by_product_id(payload.fetch("consumables", []))
  state.fetch(:iaps).each do |iap|
    product_id = iap.dig("attributes", "productId")
    local_iap = iaps_by_product[product_id]
    next unless local_iap

    upsert_localizations(
      client: client,
      current: in_app_purchase_localizations(client, iap.fetch("id")),
      desired: local_iap.fetch("localizations"),
      create_path: "/v1/inAppPurchaseLocalizations",
      update_path_prefix: "/v1/inAppPurchaseLocalizations",
      type: "inAppPurchaseLocalizations",
      relationship_name: "inAppPurchaseV2",
      related_type: "inAppPurchases",
      related_id: iap.fetch("id"),
      label: "iap_localizations #{product_id}"
    )
  end
end

def create_screenshot(client:, path:, create_path:, related_name:, related_type:, related_id:, screenshot_type:, update_path_prefix:)
  bytes = File.binread(path)
  response = client.post(
    create_path,
    {
      data: {
        type: screenshot_type,
        attributes: {
          fileName: File.basename(path),
          fileSize: bytes.bytesize
        },
        relationships: {
          related_name => {
            data: {
              type: related_type,
              id: related_id
            }
          }
        }
      }
    }
  )
  screenshot = response.fetch("data")
  screenshot.fetch("attributes").fetch("uploadOperations").each do |operation|
    client.upload_operation(operation, bytes)
  end
  checksum = Digest::MD5.hexdigest(bytes)
  client.patch(
    "#{update_path_prefix}/#{screenshot.fetch("id")}",
    {
      data: {
        type: screenshot_type,
        id: screenshot.fetch("id"),
        attributes: {
          uploaded: true,
          sourceFileChecksum: checksum
        }
      }
    }
  )
  screenshot.fetch("id")
end

def delete_failed_screenshot(client, screenshot, delete_path_prefix, label)
  return false unless screenshot

  state = screenshot.dig("data", "attributes", "assetDeliveryState", "state")
  return false unless state == "FAILED"

  id = screenshot.fetch("data").fetch("id")
  client.delete("#{delete_path_prefix}/#{id}")
  puts "#{label}: deleted failed screenshot #{id}"
  true
end

def create_introductory_offer_payload(subscription_id:, territory_id:, offer:)
  {
    data: {
      type: "subscriptionIntroductoryOffers",
      attributes: {
        duration: offer.fetch("duration"),
        offerMode: offer.fetch("offerMode"),
        numberOfPeriods: offer.fetch("numberOfPeriods")
      },
      relationships: {
        subscription: {
          data: { type: "subscriptions", id: subscription_id }
        },
        territory: {
          data: { type: "territories", id: territory_id }
        }
      }
    }
  }
end

def introductory_offer_matches?(live_attributes, desired)
  %w[duration offerMode numberOfPeriods].all? do |key|
    live_attributes[key] == desired.fetch(key)
  end
end

# A price point relationship is only required for the paid offer modes, so
# FREE_TRIAL needs nothing beyond the subscription and the territory.
def upload_introductory_offers(client, payload)
  state = live_state(client, payload)
  expected = payload_by_product_id(payload.fetch("subscriptions"))

  state.fetch(:subscriptions).each do |subscription|
    attrs = subscription.fetch("attributes")
    product_id = attrs.fetch("productId")
    local = expected[product_id]
    next unless local

    subscription_id = subscription.fetch("id")
    desired = local["introductoryOffer"]
    live = subscription_introductory_offers(client, subscription_id)

    if desired.nil?
      puts "introductory_offer #{product_id}: none configured locally, #{live.length} live, left alone"
      next
    end

    live_by_territory = live.to_h do |offer|
      [offer.dig("relationships", "territory", "data", "id"), offer]
    end
    territories = subscription_price_territories(client, subscription_id)
    raise "introductory_offer #{product_id}: no price territories found" if territories.empty?

    created = 0
    unchanged = 0
    conflicts = []

    territories.each do |territory_id|
      current = live_by_territory[territory_id]
      if current
        if introductory_offer_matches?(current.fetch("attributes"), desired)
          unchanged += 1
        else
          # Never stack a second offer or delete an existing one: a live offer
          # that does not match is a decision for a human in App Store Connect.
          conflicts << "#{territory_id}=#{current.fetch("attributes").slice("offerMode", "duration", "numberOfPeriods")}"
        end
        next
      end

      client.post(
        "/v1/subscriptionIntroductoryOffers",
        create_introductory_offer_payload(
          subscription_id: subscription_id,
          territory_id: territory_id,
          offer: desired
        )
      )
      created += 1
    end

    puts "introductory_offer #{product_id} " \
         "#{desired.fetch("offerMode")}/#{desired.fetch("duration")}x#{desired.fetch("numberOfPeriods")}: " \
         "territories=#{territories.length} created=#{created} unchanged=#{unchanged} conflicts=#{conflicts.length}"

    unless conflicts.empty?
      raise "introductory_offer #{product_id}: #{conflicts.length} territory offer(s) differ from the local " \
            "configuration #{desired.slice("offerMode", "duration", "numberOfPeriods")}; resolve them in App " \
            "Store Connect. #{conflicts.first(10).join(", ")}"
    end
  end
end

def upload_review_screenshots(client, payload, screenshot_path)
  if screenshot_path.to_s.empty?
    raise "No review screenshot given: pass --screenshot PATH or set #{SCREENSHOT_PATH_ENV_KEY}"
  end
  raise "Review screenshot not found: #{screenshot_path}" unless File.file?(screenshot_path)

  state = live_state(client, payload)

  subscriptions_by_product = payload_by_product_id(payload.fetch("subscriptions"))
  state.fetch(:subscriptions).each do |subscription|
    product_id = subscription.dig("attributes", "productId")
    next unless subscriptions_by_product.key?(product_id)
    existing_screenshot = subscription_review_screenshot(client, subscription.fetch("id"))
    deleted = delete_failed_screenshot(
      client,
      existing_screenshot,
      "/v1/subscriptionAppStoreReviewScreenshots",
      "subscription_review_screenshot #{product_id}"
    )
    next if existing_screenshot && !deleted

    id = create_screenshot(
      client: client,
      path: screenshot_path,
      create_path: "/v1/subscriptionAppStoreReviewScreenshots",
      related_name: "subscription",
      related_type: "subscriptions",
      related_id: subscription.fetch("id"),
      screenshot_type: "subscriptionAppStoreReviewScreenshots",
      update_path_prefix: "/v1/subscriptionAppStoreReviewScreenshots"
    )
    puts "subscription_review_screenshot #{product_id}: created #{id}"
  end

  iaps_by_product = payload_by_product_id(payload.fetch("consumables", []))
  state.fetch(:iaps).each do |iap|
    product_id = iap.dig("attributes", "productId")
    next unless iaps_by_product.key?(product_id)
    existing_screenshot = iap_review_screenshot(client, iap.fetch("id"))
    deleted = delete_failed_screenshot(
      client,
      existing_screenshot,
      "/v1/inAppPurchaseAppStoreReviewScreenshots",
      "iap_review_screenshot #{product_id}"
    )
    next if existing_screenshot && !deleted

    id = create_screenshot(
      client: client,
      path: screenshot_path,
      create_path: "/v1/inAppPurchaseAppStoreReviewScreenshots",
      related_name: "inAppPurchaseV2",
      related_type: "inAppPurchases",
      related_id: iap.fetch("id"),
      screenshot_type: "inAppPurchaseAppStoreReviewScreenshots",
      update_path_prefix: "/v1/inAppPurchaseAppStoreReviewScreenshots"
    )
    puts "iap_review_screenshot #{product_id}: created #{id}"
  end
end

# ---------------------------------------------------------------------------
# Subscription price changes and win-back offers
#
# Both commands follow the same rules (Notion card "Пейвол Стор"):
# - Without --apply they only read and print the plan. Nothing is written.
# - A re-run is safe: what already matches is reported as unchanged.
# - A conflict is named and never overwritten; with any conflict, --apply
#   writes nothing at all.
# - Nothing is deleted.
#
# Territory IDs are the App Store Connect alpha-3 codes: USA, DEU, UKR.
# ---------------------------------------------------------------------------

DATE_PATTERN = /\A\d{4}-\d{2}-\d{2}\z/.freeze

def parse_iso_date(value, label)
  raise "#{label} must be YYYY-MM-DD, got #{value.inspect}" unless value.to_s.match?(DATE_PATTERN)

  Date.iso8601(value)
rescue ArgumentError
  raise "#{label} is not a valid date: #{value.inspect}"
end

def parse_price(value, label)
  raise "#{label} must be a decimal price such as 9.99, got #{value.inspect}" unless value.to_s.match?(/\A\d+(\.\d+)?\z/)

  BigDecimal(value)
end

# "USA=8.99" -> ["USA", BigDecimal("8.99")]
def parse_territory_override(value)
  territory, price = value.to_s.split("=", 2)
  raise "--override must be TERRITORY=PRICE (for example USA=8.99), got #{value.inspect}" if territory.to_s.empty? || price.to_s.empty?

  [territory.upcase, parse_price(price, "--override #{territory}")]
end

def format_price(value)
  return "-" if value.nil?

  value.to_s("F").then { |text| text.include?(".") ? text.sub(/(\.\d)\z/, "\\10") : "#{text}.00" }
end

def find_subscription(client, app_id, product_id)
  app_subscription_groups(client, app_id).each do |group|
    found = subscriptions(client, group.fetch("id")).find { |subscription| subscription.dig("attributes", "productId") == product_id }
    return found if found
  end
  raise "No subscription with product id #{product_id} in App Store Connect"
end

def included_index(included, type)
  included.select { |record| record.fetch("type") == type }.to_h { |record| [record.fetch("id"), record] }
end

# All price points of one subscription in one territory, keyed by customer
# price. GET /v1/subscriptions/{id}/pricePoints, filter[territory] (limit 8000).
def territory_price_points(client, subscription_id, territory_id)
  query = URI.encode_www_form("filter[territory]" => territory_id, "limit" => 8000)
  client
    .paged("/v1/subscriptions/#{subscription_id}/pricePoints?#{query}")
    .map { |point| { id: point.fetch("id"), price: BigDecimal(point.dig("attributes", "customerPrice")) } }
end

def price_point_for(client, subscription_id, territory_id, price)
  points = territory_price_points(client, subscription_id, territory_id)
  match = points.find { |point| point.fetch(:price) == price }
  return match.fetch(:id) if match

  nearby = points.map { |point| point.fetch(:price) }.sort_by { |candidate| (candidate - price).abs }.first(3)
  raise "#{territory_id} has no price point at #{format_price(price)}; nearest: #{nearby.map { |p| format_price(p) }.join(", ")}"
end

# Apple's equivalent price in every other territory for one base price point.
# GET /v1/subscriptionPricePoints/{id}/equalizations, include=territory.
# Returns { "DEU" => { id:, price:, currency: } }.
def equalized_price_points(client, price_point_id)
  query = URI.encode_www_form("include" => "territory", "limit" => 8000)
  response = client.paged_with_included("/v1/subscriptionPricePoints/#{price_point_id}/equalizations?#{query}")
  territories = included_index(response.fetch(:included), "territories")
  response.fetch(:data).to_h do |point|
    territory_id = point.dig("relationships", "territory", "data", "id")
    [territory_id, {
      id: point.fetch("id"),
      price: BigDecimal(point.dig("attributes", "customerPrice")),
      currency: territories.dig(territory_id, "attributes", "currency")
    }]
  end
end

# The desired price point in every territory: the base price in the base
# territory, Apple's equalization everywhere else, then the overrides.
# Returns { "USA" => { id:, price:, currency:, source: "base"|"equalized"|"override" } }.
def desired_price_points(client, subscription_id:, base_territory:, base_price:, overrides:)
  base_id = price_point_for(client, subscription_id, base_territory, base_price)
  desired = equalized_price_points(client, base_id).transform_values { |point| point.merge(source: "equalized") }
  desired[base_territory] = { id: base_id, price: base_price, currency: desired.dig(base_territory, :currency), source: "base" }

  overrides.each do |territory_id, price|
    point_id = price_point_for(client, subscription_id, territory_id, price)
    desired[territory_id] = { id: point_id, price: price, currency: desired.dig(territory_id, :currency), source: "override" }
  end
  desired
end

# Every price row of a subscription: the current one and any scheduled one per
# territory. GET /v1/subscriptions/{id}/prices,
# include=subscriptionPricePoint,territory. Returns
# { "USA" => [{ id:, start_date:, preserved:, point_id:, price:, currency: }] }.
def subscription_price_rows(client, subscription_id)
  query = URI.encode_www_form("include" => "subscriptionPricePoint,territory", "limit" => 200)
  response = client.paged_with_included("/v1/subscriptions/#{subscription_id}/prices?#{query}")
  points = included_index(response.fetch(:included), "subscriptionPricePoints")
  territories = included_index(response.fetch(:included), "territories")

  response.fetch(:data).group_by { |row| row.dig("relationships", "territory", "data", "id") }.transform_values do |rows|
    rows.map do |row|
      point_id = row.dig("relationships", "subscriptionPricePoint", "data", "id")
      territory_id = row.dig("relationships", "territory", "data", "id")
      start = row.dig("attributes", "startDate")
      customer_price = points.dig(point_id, "attributes", "customerPrice")
      {
        id: row.fetch("id"),
        start_date: start ? Date.iso8601(start) : nil,
        preserved: row.dig("attributes", "preserved"),
        point_id: point_id,
        price: customer_price ? BigDecimal(customer_price) : nil,
        currency: territories.dig(territory_id, "attributes", "currency")
      }
    end
  end
end

# The row in effect today: the latest start date that is not in the future.
# A row with no start date has been in effect since the product was created.
def current_price_row(rows, today)
  rows
    .reject { |row| row[:start_date] && row[:start_date] > today }
    .max_by { |row| row[:start_date] || Date.new(0) }
end

# Pure planner: no network. One entry per territory the subscription is sold
# in, with action create | unchanged | conflict.
def plan_subscription_price_change(price_rows:, desired:, start_date:, preserve_current_price:, today:)
  price_rows.keys.sort.map do |territory_id|
    rows = price_rows.fetch(territory_id)
    current = current_price_row(rows, today)
    scheduled = rows.select { |row| row[:start_date] && row[:start_date] > today }
    target = desired[territory_id]
    entry = {
      territory: territory_id,
      currency: current&.fetch(:currency) || target&.fetch(:currency),
      current_price: current&.fetch(:price),
      new_price: target&.fetch(:price),
      source: target&.fetch(:source),
      point_id: target&.fetch(:id)
    }

    if target.nil?
      next entry.merge(action: "conflict", reason: "no desired price point for this territory")
    end

    # Apple does not document whether `preserved` echoes preserveCurrentPrice,
    # so a row with the same date and price point matches; a different
    # `preserved` value is printed for a human to check, never rewritten.
    matching = scheduled.find { |row| row[:start_date] == start_date && row[:point_id] == target.fetch(:id) }
    others = scheduled - [matching]

    if !others.empty?
      found = others.map { |row| "#{format_price(row[:price])} from #{row[:start_date]} preserved=#{row[:preserved].inspect}" }.join("; ")
      entry.merge(action: "conflict", reason: "another price change is already scheduled: #{found}")
    elsif matching
      reason = "already scheduled"
      if !matching[:preserved].nil? && matching[:preserved] != preserve_current_price
        reason += "; live preserved=#{matching[:preserved]}, check the preserve choice in App Store Connect"
      end
      entry.merge(action: "unchanged", reason: reason)
    elsif current && current[:point_id] == target.fetch(:id)
      entry.merge(action: "unchanged", reason: "already the current price")
    else
      entry.merge(action: "create")
    end
  end
end

def subscription_price_payload(subscription_id:, territory_id:, point_id:, start_date:, preserve_current_price:)
  {
    data: {
      type: "subscriptionPrices",
      attributes: {
        startDate: start_date.iso8601,
        preserveCurrentPrice: preserve_current_price
      },
      relationships: {
        subscription: { data: { type: "subscriptions", id: subscription_id } },
        subscriptionPricePoint: { data: { type: "subscriptionPricePoints", id: point_id } },
        territory: { data: { type: "territories", id: territory_id } }
      }
    }
  }
end

def print_price_plan(plan, start_date:, preserve_current_price:, io:)
  plan.each do |entry|
    line = "#{entry[:territory]} #{entry[:currency] || "?"} current=#{format_price(entry[:current_price])} " \
           "new=#{format_price(entry[:new_price])}"
    line += " (#{entry[:source]})" if entry[:source] && entry[:source] != "equalized"
    line += " start=#{start_date} preserveCurrentPrice=#{preserve_current_price} action=#{entry[:action]}"
    line += " reason=#{entry[:reason]}" if entry[:reason]
    io.puts(line)
  end
  counts = plan.group_by { |entry| entry[:action] }.transform_values(&:length)
  io.puts "summary territories=#{plan.length} create=#{counts.fetch("create", 0)} " \
          "unchanged=#{counts.fetch("unchanged", 0)} conflict=#{counts.fetch("conflict", 0)}"
end

# The current price of every territory, for a rollback after the change has
# started: feed this file back with --prices-file.
def price_snapshot(product_id, price_rows, today)
  {
    "productId" => product_id,
    "capturedOn" => today.iso8601,
    "prices" => price_rows.keys.sort.to_h do |territory_id|
      row = current_price_row(price_rows.fetch(territory_id), today)
      [territory_id, { "pricePointId" => row&.fetch(:point_id), "customerPrice" => format_price(row&.fetch(:price)), "currency" => row&.fetch(:currency) }]
    end
  }
end

def desired_from_prices_file(path)
  prices = JSON.parse(File.read(path)).fetch("prices")
  empty = prices.select { |_, entry| entry["pricePointId"].nil? }.keys
  raise "#{path} has no price point for: #{empty.sort.join(", ")}" unless empty.empty?

  prices.to_h do |territory_id, entry|
    [territory_id, { id: entry.fetch("pricePointId"), price: BigDecimal(entry.fetch("customerPrice")), currency: entry["currency"], source: "file" }]
  end
end

def schedule_subscription_price(client, options, today: Date.today, io: $stdout)
  product_id = options.fetch(:product)
  start_date = parse_iso_date(options.fetch(:start_date), "--start-date")
  raise "--start-date must be after today (#{today}); App Store Connect's first available date is tomorrow" unless start_date > today

  preserve = options.fetch(:preserve_current_price)
  raise "Pass --preserve-current-price or --no-preserve-current-price; the choice moves existing subscribers" if preserve.nil?

  app_id = app_id_for(client, options.fetch(:bundle_id))
  subscription_id = find_subscription(client, app_id, product_id).fetch("id")
  price_rows = subscription_price_rows(client, subscription_id)
  raise "#{product_id} has no price rows in App Store Connect" if price_rows.empty?

  unsold = options.fetch(:overrides).map(&:first) - price_rows.keys
  raise "Territories not sold for #{product_id}: #{unsold.sort.join(", ")}; check the codes (alpha-3, such as USA)" unless unsold.empty?

  if options[:snapshot_path]
    File.write(options[:snapshot_path], JSON.pretty_generate(price_snapshot(product_id, price_rows, today)) + "\n")
    io.puts "snapshot written to #{options[:snapshot_path]}"
  end

  desired = if options[:prices_file]
              desired_from_prices_file(options[:prices_file])
            else
              base_territory = options.fetch(:base_territory) { raise "--base-territory is required without --prices-file" }.upcase
              base_price = parse_price(options.fetch(:base_price) { raise "--base-price is required without --prices-file" }, "--base-price")
              desired_price_points(client, subscription_id: subscription_id, base_territory: base_territory,
                                           base_price: base_price, overrides: options.fetch(:overrides))
            end

  unsold = (options[:prices_file] ? desired.keys : []) - price_rows.keys
  raise "Territories not sold for #{product_id}: #{unsold.sort.join(", ")}; check the codes (alpha-3, such as USA)" unless unsold.empty?

  io.puts "subscription=#{product_id} id=#{subscription_id} mode=#{options[:apply] ? "apply" : "dry-run"}"
  plan = plan_subscription_price_change(price_rows: price_rows, desired: desired, start_date: start_date,
                                        preserve_current_price: preserve, today: today)
  print_price_plan(plan, start_date: start_date, preserve_current_price: preserve, io: io)

  conflicts = plan.select { |entry| entry[:action] == "conflict" }
  unless conflicts.empty?
    raise "#{conflicts.length} territory conflict(s); nothing written. Resolve them in App Store Connect: " \
          "#{conflicts.first(10).map { |entry| entry[:territory] }.join(", ")}"
  end
  return plan unless options[:apply]

  created = 0
  plan.select { |entry| entry[:action] == "create" }.each do |entry|
    client.post("/v1/subscriptionPrices", subscription_price_payload(
      subscription_id: subscription_id, territory_id: entry[:territory], point_id: entry[:point_id],
      start_date: start_date, preserve_current_price: preserve
    ))
    created += 1
  rescue ApiError => e
    raise "#{entry[:territory]} failed after #{created} created: #{e.message}. Re-run: created rows show as unchanged."
  end
  io.puts "applied created=#{created}"
  plan
end

# Rollback before the start date: delete the scheduled rows for that date.
# DELETE /v1/subscriptionPrices/{id}. Rows already in effect are never touched.
def cancel_subscription_price(client, options, today: Date.today, io: $stdout)
  product_id = options.fetch(:product)
  start_date = parse_iso_date(options.fetch(:start_date), "--start-date")
  raise "--start-date #{start_date} is not in the future; a price in effect cannot be cancelled, schedule the old price instead" unless start_date > today

  app_id = app_id_for(client, options.fetch(:bundle_id))
  subscription_id = find_subscription(client, app_id, product_id).fetch("id")
  rows = subscription_price_rows(client, subscription_id).flat_map do |territory_id, territory_rows|
    territory_rows.select { |row| row[:start_date] == start_date }.map { |row| row.merge(territory: territory_id) }
  end

  io.puts "subscription=#{product_id} id=#{subscription_id} mode=#{options[:apply] ? "apply" : "dry-run"}"
  rows.sort_by { |row| row[:territory] }.each do |row|
    io.puts "#{row[:territory]} #{row[:currency] || "?"} scheduled=#{format_price(row[:price])} start=#{start_date} action=delete"
  end
  io.puts "summary delete=#{rows.length}"
  return rows unless options[:apply]

  rows.each { |row| client.delete("/v1/subscriptionPrices/#{row[:id]}") }
  io.puts "applied deleted=#{rows.length}"
  rows
end

WIN_BACK_DURATIONS = %w[THREE_DAYS ONE_WEEK TWO_WEEKS ONE_MONTH TWO_MONTHS THREE_MONTHS SIX_MONTHS ONE_YEAR].freeze
WIN_BACK_MODES = %w[PAY_AS_YOU_GO PAY_UP_FRONT FREE_TRIAL].freeze
WIN_BACK_PRIORITIES = %w[HIGH NORMAL].freeze
WIN_BACK_PROMOTION_INTENTS = %w[NOT_PROMOTED USE_AUTO_GENERATED_ASSETS].freeze
WIN_BACK_PAID_MONTHS = ((1..24).to_a + [36, 48, 60]).freeze

# The win-back attributes from the command line, validated against the values
# the API documents for WinBackOfferCreateRequest.Data.Attributes.
def win_back_attributes(options, today)
  required = %i[offer_id reference_name offer_mode duration period_count paid_months since_min start_date]
  missing = required.select { |key| options[key].nil? }
  raise "Missing win-back option(s): #{missing.map { |key| "--#{key.to_s.tr("_", "-")}" }.join(", ")}" unless missing.empty?

  raise "--offer-mode must be one of #{WIN_BACK_MODES.join(", ")}" unless WIN_BACK_MODES.include?(options[:offer_mode])
  raise "--duration must be one of #{WIN_BACK_DURATIONS.join(", ")}" unless WIN_BACK_DURATIONS.include?(options[:duration])
  raise "--priority must be one of #{WIN_BACK_PRIORITIES.join(", ")}" unless WIN_BACK_PRIORITIES.include?(options[:priority])
  unless WIN_BACK_PROMOTION_INTENTS.include?(options[:promotion_intent])
    raise "--promotion-intent must be one of #{WIN_BACK_PROMOTION_INTENTS.join(", ")}"
  end
  raise "--paid-months must be 1-24, 36, 48 or 60" unless WIN_BACK_PAID_MONTHS.include?(options[:paid_months])
  raise "--wait-months must be 2-24" if options[:wait_months] && !(2..24).cover?(options[:wait_months])
  raise "--offer-id allows letters, digits, periods and underscores, up to 100" unless options[:offer_id].match?(/\A[A-Za-z0-9._]{1,100}\z/)
  raise "--reference-name allows letters, digits, spaces, periods and underscores, up to 65" unless options[:reference_name].match?(/\A[A-Za-z0-9 ._]{1,65}\z/)

  start_date = parse_iso_date(options[:start_date], "--start-date")
  raise "--start-date must be after today (#{today})" unless start_date > today

  since = { minimum: options[:since_min] }
  since[:maximum] = options[:since_max] if options[:since_max]
  attributes = {
    referenceName: options[:reference_name],
    offerId: options[:offer_id],
    duration: options[:duration],
    offerMode: options[:offer_mode],
    periodCount: options[:period_count],
    customerEligibilityPaidSubscriptionDurationInMonths: options[:paid_months],
    customerEligibilityTimeSinceLastSubscribedInMonths: since,
    startDate: start_date.iso8601,
    priority: options[:priority],
    promotionIntent: options[:promotion_intent]
  }
  attributes[:customerEligibilityWaitBetweenOffersInMonths] = options[:wait_months]
  attributes[:endDate] = nil
  if options[:end_date]
    end_date = parse_iso_date(options[:end_date], "--end-date")
    raise "--end-date must be at least 3 days after --start-date" if end_date < start_date + 3

    attributes[:endDate] = end_date.iso8601
  end
  attributes
end

# Pure: compare a live win-back offer with the desired attributes. Returns the
# differing keys as "key: live -> desired".
# A nil desired value means "not set" and must be nil (or absent) live too.
def win_back_differences(live_attributes, desired_attributes)
  desired_attributes.each_with_object([]) do |(key, value), differences|
    live_value = live_attributes[key.to_s]
    live_value = live_value.transform_keys(&:to_sym).reject { |_, v| v.nil? } if live_value.is_a?(Hash)
    differences << "#{key}: #{live_value.inspect} -> #{value.inspect}" unless live_value == value
  end
end

# Live price point per territory of one offer. GET /v1/winBackOffers/{id}/prices,
# include=territory,subscriptionPricePoint: without `include` the API returns
# relationship links only, with no ids to compare.
def live_win_back_prices(client, offer_id)
  query = URI.encode_www_form("include" => "territory,subscriptionPricePoint", "limit" => 200)
  client.paged("/v1/winBackOffers/#{offer_id}/prices?#{query}").to_h do |price|
    [price.dig("relationships", "territory", "data", "id"), price.dig("relationships", "subscriptionPricePoint", "data", "id")]
  end
end

# Pure: territories whose live offer price point differs from the desired one.
def win_back_price_differences(live_prices, desired_prices)
  (live_prices.keys | desired_prices.keys).sort.each_with_object([]) do |territory_id, differences|
    live_point = live_prices[territory_id]
    desired_point = desired_prices.dig(territory_id, :id)
    differences << "price #{territory_id}: #{live_point.inspect} -> #{desired_point.inspect}" unless live_point == desired_point
  end
end

# POST /v1/winBackOffers with the prices created inline: each price is an
# `included` winBackOfferPrices resource with a local `${...}` id, linked to a
# territory and a subscription price point.
def win_back_offer_payload(subscription_id:, attributes:, prices:)
  included = prices.keys.sort.map do |territory_id|
    {
      type: "winBackOfferPrices",
      id: "${price-#{territory_id}}",
      relationships: {
        territory: { data: { type: "territories", id: territory_id } },
        subscriptionPricePoint: { data: { type: "subscriptionPricePoints", id: prices.fetch(territory_id).fetch(:id) } }
      }
    }
  end
  {
    data: {
      type: "winBackOffers",
      attributes: attributes.reject { |_, value| value.nil? },
      relationships: {
        subscription: { data: { type: "subscriptions", id: subscription_id } },
        prices: { data: included.map { |price| { type: "winBackOfferPrices", id: price[:id] } } }
      }
    },
    included: included
  }
end

def upload_win_back_offer(client, options, today: Date.today, io: $stdout)
  product_id = options.fetch(:product)
  attributes = win_back_attributes(options, today)

  app_id = app_id_for(client, options.fetch(:bundle_id))
  subscription_id = find_subscription(client, app_id, product_id).fetch("id")
  price_rows = subscription_price_rows(client, subscription_id)
  sold_territories = price_rows.keys.sort

  unsold = options.fetch(:overrides).map(&:first) - sold_territories
  raise "Territories not sold for #{product_id}: #{unsold.sort.join(", ")}; check the codes (alpha-3, such as USA)" unless unsold.empty?

  prices = if attributes[:offerMode] == "FREE_TRIAL"
             {}
           else
             base_territory = options.fetch(:base_territory) { raise "--base-territory is required for a paid offer" }.upcase
             base_price = parse_price(options.fetch(:base_price) { raise "--base-price is required for a paid offer" }, "--base-price")
             desired_price_points(client, subscription_id: subscription_id, base_territory: base_territory,
                                          base_price: base_price, overrides: options.fetch(:overrides))
               .select { |territory_id, _| sold_territories.include?(territory_id) }
               .to_h { |territory_id, point| [territory_id, point.merge(currency: point[:currency] || price_rows.dig(territory_id, 0, :currency))] }
           end

  io.puts "subscription=#{product_id} id=#{subscription_id} mode=#{options[:apply] ? "apply" : "dry-run"}"
  io.puts "win_back_offer offerId=#{attributes[:offerId]} #{attributes[:offerMode]}/#{attributes[:duration]}x#{attributes[:periodCount]} " \
          "paidMonths>=#{attributes[:customerEligibilityPaidSubscriptionDurationInMonths]} " \
          "sinceLastSubscribedMonths=#{attributes[:customerEligibilityTimeSinceLastSubscribedInMonths].values.join("..")} " \
          "waitMonths=#{attributes[:customerEligibilityWaitBetweenOffersInMonths] || "-"} " \
          "start=#{attributes[:startDate]} end=#{attributes[:endDate] || "-"} priority=#{attributes[:priority]} promotion=#{attributes[:promotionIntent]}"
  prices.keys.sort.each do |territory_id|
    price = prices.fetch(territory_id)
    line = "#{territory_id} #{price[:currency] || "?"} offer_price=#{format_price(price[:price])}"
    line += " (#{price[:source]})" unless price[:source] == "equalized"
    io.puts line
  end
  missing = attributes[:offerMode] == "FREE_TRIAL" ? [] : sold_territories - prices.keys
  io.puts "missing_price_territories=#{missing.join(",")}" unless missing.empty?

  live = client.paged("/v1/subscriptions/#{subscription_id}/winBackOffers?limit=200")
  existing = live.find { |offer| offer.dig("attributes", "offerId") == attributes[:offerId] }
  differences = []
  if existing
    differences = win_back_differences(existing.fetch("attributes"), attributes) +
                  win_back_price_differences(live_win_back_prices(client, existing.fetch("id")), prices)
  end
  action = if existing.nil?
             "create"
           elsif differences.empty?
             "unchanged"
           else
             "conflict"
           end
  io.puts "summary territories=#{prices.length} live_offers=#{live.length} action=#{action}"

  if action == "conflict"
    raise "win-back offer #{attributes[:offerId]} exists with different values; nothing written. " \
          "Change it in App Store Connect or pick a new --offer-id: #{differences.join("; ")}"
  end
  raise "#{missing.length} sold territories have no offer price; nothing written: #{missing.first(10).join(", ")}" unless missing.empty?
  return action unless options[:apply] && action == "create"

  response = client.post("/v1/winBackOffers", win_back_offer_payload(subscription_id: subscription_id, attributes: attributes, prices: prices))
  io.puts "applied created=#{response.dig("data", "id")}"
  action
end

COMMANDS = %w[
  status upload-localizations upload-introductory-offers upload-review-screenshots
  schedule-subscription-price cancel-subscription-price upload-win-back-offer
].freeze
PRICE_COMMANDS = %w[schedule-subscription-price cancel-subscription-price upload-win-back-offer].freeze

def parse_options(argv)
  # screenshot_path stays nil so the env fallback can be resolved after the .env
  # file is loaded; reading it here would capture the value before load_env_file
  # has had a chance to populate it.
  options = {
    metadata_path: DEFAULT_METADATA_PATH,
    screenshot_path: nil,
    env_path: DEFAULT_ENV_PATH,
    bundle_id: "com.alike.app",
    apply: false,
    overrides: [],
    preserve_current_price: nil,
    priority: "NORMAL",
    promotion_intent: "NOT_PROMOTED"
  }

  parser = OptionParser.new do |opts|
    opts.banner = "Usage: bundle exec ruby tools/app_store_iap_metadata.rb [#{COMMANDS.join("|")}] [options]"
    opts.on("--metadata PATH", "Path to app_store_connect_iap_metadata.json") { |value| options[:metadata_path] = value }
    opts.on("--screenshot PATH", "Path to review screenshot image") { |value| options[:screenshot_path] = value }
    opts.on("--env PATH", "Path to env file with App Store Connect credentials") { |value| options[:env_path] = value }
    opts.on("--no-env", "Do not load .env automatically") { options[:env_path] = nil }
    opts.separator ""
    opts.separator "Price and win-back commands (dry-run unless --apply):"
    opts.on("--product ID", "Subscription product id, e.g. com.alike.app.pro.monthly") { |value| options[:product] = value }
    opts.on("--bundle-id ID", "App bundle id (default com.alike.app)") { |value| options[:bundle_id] = value }
    opts.on("--base-territory CODE", "Base territory, alpha-3 (USA)") { |value| options[:base_territory] = value }
    opts.on("--base-price PRICE", "Base customer price, e.g. 9.99") { |value| options[:base_price] = value }
    opts.on("--override TERRITORY=PRICE", "Replace Apple's equivalent in one territory; repeatable") do |value|
      options[:overrides] << parse_territory_override(value)
    end
    opts.on("--start-date YYYY-MM-DD", "First day of the new price or the offer") { |value| options[:start_date] = value }
    opts.on("--[no-]preserve-current-price", "Existing subscribers keep their price (required for schedule)") do |value|
      options[:preserve_current_price] = value
    end
    opts.on("--prices-file PATH", "Desired price point per territory (a --snapshot file), instead of base and overrides") do |value|
      options[:prices_file] = value
    end
    opts.on("--snapshot PATH", "Write the current price of every territory to PATH") { |value| options[:snapshot_path] = value }
    opts.on("--offer-id ID", "Win-back offer id") { |value| options[:offer_id] = value }
    opts.on("--reference-name NAME", "Win-back reference name") { |value| options[:reference_name] = value }
    opts.on("--offer-mode MODE", WIN_BACK_MODES.join(", ")) { |value| options[:offer_mode] = value }
    opts.on("--duration DURATION", WIN_BACK_DURATIONS.join(", ")) { |value| options[:duration] = value }
    opts.on("--period-count N", Integer, "Number of offer periods") { |value| options[:period_count] = value }
    opts.on("--paid-months N", Integer, "Customer was subscribed at least N months") { |value| options[:paid_months] = value }
    opts.on("--since-min N", Integer, "Subscription ended at least N months ago") { |value| options[:since_min] = value }
    opts.on("--since-max N", Integer, "Subscription ended at most N months ago") { |value| options[:since_max] = value }
    opts.on("--wait-months N", Integer, "Months before the same customer can redeem again (2-24)") { |value| options[:wait_months] = value }
    opts.on("--end-date YYYY-MM-DD", "Last day of the win-back offer") { |value| options[:end_date] = value }
    opts.on("--priority VALUE", WIN_BACK_PRIORITIES.join(", ")) { |value| options[:priority] = value }
    opts.on("--promotion-intent VALUE", WIN_BACK_PROMOTION_INTENTS.join(", ")) { |value| options[:promotion_intent] = value }
    opts.on("--apply", "Write to App Store Connect. Only after the owner says yes.") { options[:apply] = true }
  end

  command = argv.shift || "status"
  parser.parse!(argv)
  [command, options, parser]
end

def main(argv)
  command, options, parser = parse_options(argv)
  unless COMMANDS.include?(command)
    warn parser
    exit 64
  end
  if PRICE_COMMANDS.include?(command) && options[:product].to_s.empty?
    warn "--product is required for #{command}"
    exit 64
  end

  load_env_file(options[:env_path]) if options[:env_path]
  options[:screenshot_path] ||= ENV.fetch(SCREENSHOT_PATH_ENV_KEY, "")
  client = AppStoreConnectClient.new

  case command
  when "schedule-subscription-price"
    schedule_subscription_price(client, options)
    return
  when "cancel-subscription-price"
    cancel_subscription_price(client, options)
    return
  when "upload-win-back-offer"
    upload_win_back_offer(client, options)
    return
  end

  payload = load_payload(options[:metadata_path])
  case command
  when "status"
    print_status(client, payload)
  when "upload-localizations"
    upload_localizations(client, payload)
  when "upload-introductory-offers"
    upload_introductory_offers(client, payload)
  when "upload-review-screenshots"
    upload_review_screenshots(client, payload, options[:screenshot_path])
  end
end

main(ARGV) if $PROGRAM_NAME == __FILE__
