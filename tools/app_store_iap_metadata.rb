#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest/md5"
require "json"
require "net/http"
require "openssl"
require "optparse"
require "time"
require "uri"
require "jwt"

STDOUT.sync = true

ROOT_DIR = File.expand_path("..", __dir__)
DEFAULT_METADATA_PATH = File.join(ROOT_DIR, "build", "generated", "store_upload", "iap_metadata", "app_store_connect_iap_metadata.json")
DEFAULT_SCREENSHOT_PATH = ENV.fetch("ALIKE_IAP_REVIEW_SCREENSHOT_PATH", "")
DEFAULT_ENV_PATH = File.join(ROOT_DIR, ".env")
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

  def build_token
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
  puts "subscription_group=#{group.fetch("id")} referenceName=#{group.dig("attributes", "referenceName")} localizations=#{group_locs.length}"

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
    puts "subscription=#{product_id} id=#{id} state=#{attrs["state"]} localizations=#{locs.length} review_screenshot=#{screenshot_state}"
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

def upload_review_screenshots(client, payload, screenshot_path)
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

options = {
  metadata_path: DEFAULT_METADATA_PATH,
  screenshot_path: DEFAULT_SCREENSHOT_PATH,
  env_path: DEFAULT_ENV_PATH
}

parser = OptionParser.new do |opts|
  opts.banner = "Usage: bundle exec ruby tools/app_store_iap_metadata.rb [status|upload-localizations|upload-review-screenshots] [options]"
  opts.on("--metadata PATH", "Path to app_store_connect_iap_metadata.json") { |value| options[:metadata_path] = value }
  opts.on("--screenshot PATH", "Path to review screenshot image") { |value| options[:screenshot_path] = value }
  opts.on("--env PATH", "Path to env file with App Store Connect credentials") { |value| options[:env_path] = value }
  opts.on("--no-env", "Do not load .env automatically") { options[:env_path] = nil }
end

command = ARGV.shift || "status"
parser.parse!(ARGV)

unless %w[status upload-localizations upload-review-screenshots].include?(command)
  warn parser
  exit 64
end

load_env_file(options[:env_path]) if options[:env_path]
payload = load_payload(options[:metadata_path])
client = AppStoreConnectClient.new

case command
when "status"
  print_status(client, payload)
when "upload-localizations"
  upload_localizations(client, payload)
when "upload-review-screenshots"
  upload_review_screenshots(client, payload, options[:screenshot_path])
end
