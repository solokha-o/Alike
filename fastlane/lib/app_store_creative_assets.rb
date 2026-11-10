require "digest"
require "json"
require "net/http"
require "uri"

# Upload creative assets (Product Page Header, Search Results) to the App Store
# Connect Asset Library and place them on one App Store version's localizations.
#
# `deliver` knows nothing about the Asset Library, so this talks to the API
# directly. The manifest comes from tools/generate_app_store_creative_assets.py.
#
# Safety rules, all enforced here rather than by convention:
# - Nothing is deleted or archived: no DELETE request exists in this file.
# - A localization that already has a placement of that type is left alone,
#   even when it holds a different asset; it is reported as `occupied`.
# - An image whose referenceName (placement, copy key, content hash) is already
#   in the library is reused, so a re-run uploads nothing new.
# - Without `apply: true` the run only reads and prints the plan.
# - Nothing submits for review or publishes.
module AppStoreCreativeAssets
  Error = Class.new(StandardError)

  API_HOST = "api.appstoreconnect.apple.com".freeze
  PLACEMENT_TYPES = {
    "header" => "PRODUCT_PAGE_HEADER_ASSET",
    "search" => "APP_STORE_SEARCH_RESULTS_ASSET"
  }.freeze
  PLACEMENT_GROUP = "DEFAULT_PROFILE".freeze
  CATEGORY = "CREATIVE_ASSETS".freeze
  # An image in one of these states cannot be reused. AWAITING_UPLOAD is a
  # reservation whose bytes never arrived (a killed or failed run); reusing it
  # would wait forever, so a fresh reservation is made instead.
  UNUSABLE_STATES = %w[FAILED ARCHIVED AWAITING_UPLOAD].freeze
  # States in which an image is processed and can be placed.
  READY_STATES = %w[PREPARE_FOR_SUBMISSION READY_FOR_REVIEW WAITING_FOR_REVIEW IN_REVIEW ACCEPTED APPROVED].freeze
  # Version states that take new placements. ASC refuses them on a version in
  # review (WAITING_FOR_REVIEW returned 409 STATE_ERROR.INVALID_STATE on
  # 2026-11-10), and on a live version they would need Publish, which this tool
  # never does. In any other state the images still go to the library.
  PLACEABLE_VERSION_STATES = %w[
    PREPARE_FOR_SUBMISSION DEVELOPER_REJECTED REJECTED METADATA_REJECTED
  ].freeze

  module_function

  def reference_name(placement, entry)
    "alike-#{placement}-#{entry.fetch('copy')}-#{entry.fetch('sha256')[0, 12]}"
  end

  # Pure planning step, tested offline.
  #   manifest       {"en-US" => {"header" => {"path", "sha256", "copy"}, ...}}
  #   localizations  {"en-US" => "<appStoreVersionLocalization id>"}
  #   existing       {["en-US", "header"] => "<image id>" or nil}
  # Returns one row per (locale, placement).
  def plan(manifest:, localizations:, existing:)
    rows = []
    (manifest.keys | localizations.keys).sort.each do |locale|
      PLACEMENT_TYPES.each_key do |placement|
        entry = manifest.dig(locale, placement)
        row = { locale: locale, placement: placement, localization_id: localizations[locale] }
        if entry.nil?
          rows << row.merge(action: :no_asset)
          next
        end
        row[:reference_name] = reference_name(placement, entry)
        row[:path] = entry.fetch("path")
        row[:sha256] = entry.fetch("sha256")
        row[:action] =
          if localizations[locale].nil?
            :no_localization
          elsif existing[[locale, placement]]
            :occupied
          else
            :create
          end
        rows << row
      end
    end
    rows
  end

  class Api
    def initialize(token_provider, http: nil)
      @token_provider = token_provider
      @http = http
    end

    def get(path, query = {})
      request(Net::HTTP::Get, path, query: query)
    end

    def post(path, body)
      request(Net::HTTP::Post, path, body: body)
    end

    def patch(path, body)
      request(Net::HTTP::Patch, path, body: body)
    end

    def put_part(operation, bytes)
      uri = URI(operation.fetch("url"))
      request = Net::HTTP.const_get(operation.fetch("method").capitalize).new(uri)
      Array(operation["requestHeaders"]).each { |header| request[header.fetch("name")] = header.fetch("value") }
      request.body = bytes
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") { |http| http.request(request) }
      raise Error, "upload part failed: HTTP #{response.code}" unless response.code.to_i.between?(200, 299)
    end

    private

    def request(klass, path, query: {}, body: nil)
      uri = URI::HTTPS.build(host: API_HOST, path: path, query: query.empty? ? nil : URI.encode_www_form(query))
      request = klass.new(uri)
      request["Authorization"] = "Bearer #{@token_provider.call}"
      if body
        request["Content-Type"] = "application/json"
        request.body = JSON.generate(body)
      end
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(request) }
      parsed =
        begin
          response.body.to_s.empty? ? {} : JSON.parse(response.body)
        rescue JSON::ParserError
          raise Error, "#{klass::METHOD} #{path} -> HTTP #{response.code} (non-JSON body)"
        end
      unless response.code.to_i.between?(200, 299)
        detail = Array(parsed["errors"]).map { |e| [e["code"], e["detail"]].compact.join(": ") }.join("; ")
        raise Error, "#{klass::METHOD} #{path} -> HTTP #{response.code} #{detail}"
      end
      parsed
    end
  end

  class Runner
    def initialize(api:, root:, out: $stdout, poll_seconds: 5, poll_limit: 120)
      @api = api
      @root = root
      @out = out
      @poll_seconds = poll_seconds
      @poll_limit = poll_limit
    end

    def run(app_id:, version:, manifest_path:, apply: false)
      manifest = JSON.parse(File.read(manifest_path))
      version_id, state = find_version(app_id, version)
      placeable = PLACEABLE_VERSION_STATES.include?(state)
      localizations = localizations_of(version_id)
      library_id = @api.get("/v1/apps/#{app_id}/assetLibrary").dig("data", "id") || raise(Error, "app has no asset library")
      existing = existing_placements(localizations)
      rows = AppStoreCreativeAssets.plan(manifest: manifest, localizations: localizations, existing: existing)
      unless placeable
        # Say it in the plan, before anyone confirms: this version takes no
        # placements, so the run can only fill the library.
        rows.each { |row| row[:action] = :upload_only if row[:action] == :create }
        @out.puts("#{version} is #{state}: no placements possible; apply uploads to the Asset Library only. " \
                  "Placements need a version in #{PLACEABLE_VERSION_STATES.join(', ')}.")
      end
      print_plan(version, rows)
      return rows unless apply

      pending = rows.select { |row| %i[create upload_only].include?(row[:action]) }
      verify_files!(pending)
      # Upload every image first, so a refused placement never leaves the
      # library half filled; then place, only where the version allows it.
      image_ids = {}
      pending.each { |row| image_ids[row[:reference_name]] ||= find_or_upload_image(library_id, row) }
      pending.each do |row|
        if row[:action] == :create
          place(row, image_ids.fetch(row[:reference_name]))
          row[:action] = :created
        else
          row[:action] = :uploaded_only
        end
      end
      print_plan(version, rows)
      rows
    end

    private

    def find_version(app_id, version)
      data = @api.get("/v1/apps/#{app_id}/appStoreVersions",
                      "filter[versionString]" => version, "filter[platform]" => "IOS")["data"]
      raise Error, "App Store version #{version} not found" if data.nil? || data.empty?

      state = data.first.dig("attributes", "appVersionState") || data.first.dig("attributes", "appStoreState")
      @out.puts("Version #{version}: #{state}")
      [data.first["id"], state]
    end

    def localizations_of(version_id)
      data = @api.get("/v1/appStoreVersions/#{version_id}/appStoreVersionLocalizations", "limit" => "50")["data"]
      data.each_with_object({}) { |item, map| map[item.dig("attributes", "locale")] = item["id"] }
    end

    def existing_placements(localizations)
      localizations.each_with_object({}) do |(locale, id), map|
        PLACEMENT_TYPES.each do |placement, type|
          data = @api.get("/v1/appStoreVersionLocalizations/#{id}/placements",
                          "filter[placementType]" => type)["data"]
          map[[locale, placement]] = data&.first&.dig("relationships", "image", "data", "id") || data&.first&.dig("id")
        end
      end
    end

    # A manifest from an earlier render must not name different bytes: the
    # referenceName carries the hash, so a mismatch would upload or reuse the
    # wrong image under it. Checked before the first write.
    def verify_files!(rows)
      rows.uniq { |row| row[:path] }.each do |row|
        path = File.join(@root, row[:path])
        raise Error, "missing #{row[:path]}; re-run the generator" unless File.file?(path)

        actual = Digest::SHA256.file(path).hexdigest
        next if actual == row[:sha256]

        raise Error, "#{row[:path]} does not match manifest.json (#{actual[0, 12]} != #{row[:sha256][0, 12]}); re-run the generator"
      end
    end

    def find_or_upload_image(library_id, row)
      found = @api.get("/v1/appAssetLibraries/#{library_id}/images",
                       "filter[referenceName]" => row[:reference_name])["data"].to_a
      reusable = found.find { |item| !UNUSABLE_STATES.include?(item.dig("attributes", "state")) }
      if reusable
        @out.puts("  reuse #{row[:reference_name]} (#{reusable.dig('attributes', 'state')})")
        return wait_until_processed(reusable["id"])
      end

      path = File.join(@root, row[:path])
      bytes = File.binread(path)
      reservation = @api.post("/v1/appAssetLibraryImages", {
        "data" => {
          "type" => "appAssetLibraryImages",
          "attributes" => {
            "fileName" => "#{row[:reference_name]}.png",
            "fileSize" => bytes.bytesize,
            "category" => CATEGORY,
            "referenceName" => row[:reference_name]
          },
          "relationships" => { "assetLibrary" => { "data" => { "type" => "appAssetLibraries", "id" => library_id } } }
        }
      })["data"]
      Array(reservation.dig("attributes", "uploadOperations")).each do |operation|
        offset = operation.fetch("offset").to_i
        @api.put_part(operation, bytes.byteslice(offset, operation.fetch("length").to_i))
      end
      @api.patch("/v1/appAssetLibraryImages/#{reservation['id']}", {
        "data" => { "type" => "appAssetLibraryImages", "id" => reservation["id"], "attributes" => { "uploaded" => true } }
      })
      @out.puts("  uploaded #{row[:reference_name]} (#{bytes.bytesize} bytes)")
      wait_until_processed(reservation["id"])
    end

    def wait_until_processed(image_id)
      @poll_limit.times do
        attributes = @api.get("/v1/appAssetLibraryImages/#{image_id}")["data"]["attributes"]
        state = attributes["state"]
        raise Error, "image #{image_id} failed: #{attributes['stateDetails'].inspect}" if state == "FAILED"
        return image_id if READY_STATES.include?(state)

        @out.puts("  image #{image_id}: unknown state #{state}, still waiting") unless %w[AWAITING_UPLOAD UPLOAD_COMPLETE].include?(state)
        sleep(@poll_seconds)
      end
      raise Error, "image #{image_id} still processing after #{@poll_limit * @poll_seconds}s"
    end

    def place(row, image_id)
      @api.post("/v1/appAssetLibraryPlacements", {
        "data" => {
          "type" => "appAssetLibraryPlacements",
          "attributes" => { "placementType" => PLACEMENT_TYPES.fetch(row[:placement]), "placementGroup" => PLACEMENT_GROUP },
          "relationships" => {
            "image" => { "data" => { "type" => "appAssetLibraryImages", "id" => image_id } },
            "appStoreVersionLocalization" => {
              "data" => { "type" => "appStoreVersionLocalizations", "id" => row[:localization_id] }
            }
          }
        }
      })
      @out.puts("  placed #{row[:placement]} on #{row[:locale]}")
    end

    def print_plan(version, rows)
      @out.puts("Creative assets for #{version}:")
      rows.each do |row|
        @out.puts(format("  %-8s %-7s %-16s %s", row[:locale], row[:placement], row[:action], row[:reference_name]))
      end
    end
  end
end
