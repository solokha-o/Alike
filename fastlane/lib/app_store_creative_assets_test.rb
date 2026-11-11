# Offline test for the creative-asset uploader. No network: a stub API records
# every request, so "a dry run writes nothing" and "an occupied slot is left
# alone" are assertions, not claims.
#
#   ruby fastlane/lib/app_store_creative_assets_test.rb
require "minitest/autorun"
require "fileutils"
require "stringio"
require "tmpdir"
require_relative "app_store_creative_assets"

class StubApi
  attr_reader :calls

  def initialize(occupied: [], library_images: {}, version_state: "PREPARE_FOR_SUBMISSION", image_states: [], operations: nil)
    @occupied = occupied
    @library_images = library_images
    @version_state = version_state
    @image_states = image_states.dup
    @operations = operations || [{ "method" => "PUT", "url" => "https://upload.example/part", "offset" => 0, "length" => 3 }]
    @calls = []
    @next_id = 0
  end

  def get(path, query = {})
    @calls << [:get, path, query]
    case path
    when %r{/appStoreVersions\z}
      { "data" => [{ "id" => "v1", "attributes" => { "appStoreState" => @version_state } }] }
    when %r{/appStoreVersionLocalizations\z}
      { "data" => [{ "id" => "loc-en", "attributes" => { "locale" => "en-US" } },
                   { "id" => "loc-uk", "attributes" => { "locale" => "uk" } }] }
    when %r{/assetLibrary\z}
      { "data" => { "id" => "lib" } }
    when %r{/placements\z}
      locale_id = path.split("/")[3]
      type = query["filter[placementType]"]
      taken = @occupied.include?([locale_id, type])
      { "data" => taken ? [{ "id" => "p-old", "relationships" => { "image" => { "data" => { "id" => "img-old" } } } }] : [] }
    when %r{/images\z}
      { "data" => Array(@library_images[query["filter[referenceName]"]]) }
    when %r{/appAssetLibraryImages/}
      { "data" => { "attributes" => { "state" => @image_states.shift || "PREPARE_FOR_SUBMISSION" } } }
    else
      raise "unexpected GET #{path}"
    end
  end

  def post(path, body)
    @calls << [:post, path, body]
    @next_id += 1
    { "data" => { "id" => "new-#{@next_id}", "attributes" => { "uploadOperations" => @operations } } }
  end

  def patch(path, body)
    @calls << [:patch, path, body]
    {}
  end

  def put_part(operation, bytes)
    @calls << [:put, operation["url"], bytes]
  end

  def writes
    @calls.reject { |call| call.first == :get }
  end
end

class AppStoreCreativeAssetsTest < Minitest::Test
  def setup
    @root = Dir.mktmpdir
    Dir.mkdir(File.join(@root, "out"))
    %w[en uk].each do |key|
      %w[header search].each { |placement| File.binwrite(File.join(@root, "out", "#{placement}-#{key}.png"), "png") }
    end
    @manifest_path = File.join(@root, "manifest.json")
    write_manifest
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def entry(key)
    %w[header search].each_with_object({}) do |placement, map|
      path = "out/#{placement}-#{key}.png"
      map[placement] = { "path" => path, "sha256" => Digest::SHA256.file(File.join(@root, path)).hexdigest, "copy" => key }
    end
  end

  def write_manifest
    @manifest = { "en-US" => entry("en"), "en-GB" => entry("en"), "uk" => entry("uk") }
    File.write(@manifest_path, JSON.generate(@manifest))
  end

  def runner(api)
    AppStoreCreativeAssets::Runner.new(api: api, root: @root, out: StringIO.new, poll_seconds: 0)
  end

  def test_plan_marks_missing_localization_and_occupied_slot
    rows = AppStoreCreativeAssets.plan(
      manifest: @manifest,
      localizations: { "en-US" => "loc-en", "uk" => "loc-uk", "fr-FR" => "loc-fr" },
      existing: { ["uk", "search"] => "img-old" }
    )
    actions = rows.map { |row| [row[:locale], row[:placement], row[:action]] }
    assert_includes actions, ["en-GB", "header", :no_localization]
    assert_includes actions, ["uk", "search", :occupied]
    assert_includes actions, ["uk", "header", :create]
    assert_includes actions, ["fr-FR", "header", :no_asset]
  end

  def test_reference_name_changes_with_content
    first = AppStoreCreativeAssets.reference_name("header", "copy" => "en", "sha256" => "a" * 64)
    second = AppStoreCreativeAssets.reference_name("header", "copy" => "en", "sha256" => "c" * 64)
    refute_equal first, second
    assert_equal "alike-header-en-aaaaaaaaaaaa", first
  end

  def test_dry_run_writes_nothing
    api = StubApi.new
    runner(api).run(app_id: "app", version: "1.7.2", manifest_path: @manifest_path)
    assert_empty api.writes
  end

  def test_apply_uploads_each_reference_once_and_skips_occupied
    api = StubApi.new(occupied: [["loc-uk", "APP_STORE_SEARCH_RESULTS_ASSET"]])
    rows = runner(api).run(app_id: "app", version: "1.7.2", manifest_path: @manifest_path, apply: true)

    reservations = api.writes.select { |call| call[0] == :post && call[1] == "/v1/appAssetLibraryImages" }
    placements = api.writes.select { |call| call[0] == :post && call[1] == "/v1/appAssetLibraryPlacements" }
    assert_equal 3, reservations.size, "en header, en search, uk header"
    assert_equal 3, placements.size
    assert(reservations.all? { |call| call[2]["data"]["attributes"]["category"] == "CREATIVE_ASSETS" })
    assert_equal :occupied, rows.find { |row| row[:locale] == "uk" && row[:placement] == "search" }[:action]
    refute(api.calls.any? { |call| call.first == :delete })
  end

  def test_apply_reuses_an_image_already_in_the_library
    reference = AppStoreCreativeAssets.reference_name("header", @manifest["en-US"]["header"])
    api = StubApi.new(library_images: { reference => [{ "id" => "img-existing", "attributes" => { "state" => "PREPARE_FOR_SUBMISSION" } }] })
    runner(api).run(app_id: "app", version: "1.7.2", manifest_path: @manifest_path, apply: true)

    header_placement = api.writes.find do |call|
      call[1] == "/v1/appAssetLibraryPlacements" &&
        call[2]["data"]["attributes"]["placementType"] == "PRODUCT_PAGE_HEADER_ASSET" &&
        call[2]["data"]["relationships"]["appStoreVersionLocalization"]["data"]["id"] == "loc-en"
    end
    assert_equal "img-existing", header_placement[2]["data"]["relationships"]["image"]["data"]["id"]
  end

  def test_apply_on_a_version_in_review_uploads_but_does_not_place
    api = StubApi.new(version_state: "WAITING_FOR_REVIEW")
    rows = runner(api).run(app_id: "app", version: "1.7.2", manifest_path: @manifest_path, apply: true)
    refute(api.writes.any? { |call| call[1] == "/v1/appAssetLibraryPlacements" })
    assert_equal 4, api.writes.count { |call| call[1] == "/v1/appAssetLibraryImages" }
    assert(rows.select { |row| row[:localization_id] && row[:path] }.all? { |row| row[:action] == :uploaded_only })
  end

  def test_apply_on_a_live_version_without_approved_images_uploads_only
    %w[READY_FOR_DISTRIBUTION READY_FOR_SALE].each do |state|
      api = StubApi.new(version_state: state)
      rows = runner(api).run(app_id: "app", version: "1.7.2", manifest_path: @manifest_path, apply: true)
      refute(api.writes.any? { |call| call[1] == "/v1/appAssetLibraryPlacements" }, state)
      assert_equal 4, api.writes.count { |call| call[1] == "/v1/appAssetLibraryImages" }, state
      assert(rows.select { |row| row[:localization_id] && row[:path] }.all? { |row| row[:action] == :uploaded_only }, state)
    end
  end

  def test_apply_on_a_live_version_places_only_approved_images
    approved = AppStoreCreativeAssets.reference_name("header", @manifest["en-US"]["header"])
    pending = AppStoreCreativeAssets.reference_name("search", @manifest["en-US"]["search"])
    api = StubApi.new(version_state: "READY_FOR_DISTRIBUTION", library_images: {
      approved => [{ "id" => "img-approved", "attributes" => { "state" => "APPROVED" } }],
      pending => [{ "id" => "img-pending", "attributes" => { "state" => "WAITING_FOR_REVIEW" } }]
    }, image_states: %w[APPROVED])
    rows = runner(api).run(app_id: "app", version: "1.7.2", manifest_path: @manifest_path, apply: true)
    placed = api.writes.select { |call| call[1] == "/v1/appAssetLibraryPlacements" }
                .map { |call| call[2]["data"]["relationships"]["image"]["data"]["id"] }
    assert_equal ["img-approved"], placed
    assert_includes rows.map { |row| [row[:locale], row[:placement], row[:action]] }, ["en-US", "search", :uploaded_only]
  end

  def test_a_live_version_places_the_approved_image_not_a_sibling
    reference = AppStoreCreativeAssets.reference_name("header", @manifest["en-US"]["header"])
    api = StubApi.new(version_state: "READY_FOR_DISTRIBUTION", library_images: {
      reference => [{ "id" => "img-in-review", "attributes" => { "state" => "WAITING_FOR_REVIEW" } },
                    { "id" => "img-approved", "attributes" => { "state" => "APPROVED" } }]
    })
    runner(api).run(app_id: "app", version: "1.7.2", manifest_path: @manifest_path, apply: true)
    placed = api.writes.select { |call| call[1] == "/v1/appAssetLibraryPlacements" }
                .map { |call| call[2]["data"]["relationships"]["image"]["data"]["id"] }
    assert_equal ["img-approved"], placed
    lookups = api.calls.count { |call| call[0] == :get && call[2]["filter[referenceName]"] == reference }
    assert_equal 1, lookups
  end

  def test_all_images_upload_before_the_first_placement
    api = StubApi.new(version_state: "PREPARE_FOR_SUBMISSION")
    runner(api).run(app_id: "app", version: "1.8.0", manifest_path: @manifest_path, apply: true)
    paths = api.writes.map { |call| call[1] }
    last_upload = paths.rindex("/v1/appAssetLibraryImages")
    first_place = paths.index("/v1/appAssetLibraryPlacements")
    assert_operator last_upload, :<, first_place
  end

  def test_dry_run_on_a_live_version_without_approved_images_promises_nothing
    api = StubApi.new(version_state: "READY_FOR_DISTRIBUTION")
    rows = runner(api).run(app_id: "app", version: "1.7.1", manifest_path: @manifest_path)
    refute_empty rows
    assert_empty api.writes
    assert(rows.none? { |row| row[:action] == :create }, "plan must not promise placements")
    assert(rows.any? { |row| row[:action] == :upload_only })
  end

  def test_a_stale_reservation_is_not_reused
    reference = AppStoreCreativeAssets.reference_name("header", @manifest["en-US"]["header"])
    api = StubApi.new(library_images: { reference => [{ "id" => "img-stale", "attributes" => { "state" => "AWAITING_UPLOAD" } }] })
    runner(api).run(app_id: "app", version: "1.7.2", manifest_path: @manifest_path, apply: true)
    placed = api.writes.select { |call| call[1] == "/v1/appAssetLibraryPlacements" }
                .map { |call| call[2]["data"]["relationships"]["image"]["data"]["id"] }
    refute_includes placed, "img-stale"
  end

  def test_multi_part_upload_sends_each_slice
    File.binwrite(File.join(@root, "out", "header-en.png"), "abcdef")
    write_manifest
    operations = [
      { "method" => "PUT", "url" => "https://upload.example/1", "offset" => 0, "length" => 4 },
      { "method" => "PUT", "url" => "https://upload.example/2", "offset" => 4, "length" => 2 }
    ]
    api = StubApi.new(operations: operations)
    runner(api).run(app_id: "app", version: "1.7.2", manifest_path: @manifest_path, apply: true)
    parts = api.calls.select { |call| call.first == :put }.first(2).map(&:last)
    assert_equal %w[abcd ef], parts
  end

  def test_waits_through_processing_and_unknown_states
    api = StubApi.new(image_states: %w[UPLOAD_COMPLETE SOMETHING_NEW PREPARE_FOR_SUBMISSION])
    rows = runner(api).run(app_id: "app", version: "1.7.2", manifest_path: @manifest_path, apply: true)
    assert(rows.any? { |row| row[:action] == :created })
  end

  def test_failed_processing_raises
    api = StubApi.new(image_states: %w[FAILED])
    assert_raises(AppStoreCreativeAssets::Error) do
      runner(api).run(app_id: "app", version: "1.7.2", manifest_path: @manifest_path, apply: true)
    end
    refute(api.writes.any? { |call| call[1] == "/v1/appAssetLibraryPlacements" })
  end

  def test_a_stale_manifest_stops_before_any_write
    File.binwrite(File.join(@root, "out", "search-uk.png"), "changed")
    api = StubApi.new
    assert_raises(AppStoreCreativeAssets::Error) do
      runner(api).run(app_id: "app", version: "1.7.2", manifest_path: @manifest_path, apply: true)
    end
    assert_empty api.writes
  end
end
