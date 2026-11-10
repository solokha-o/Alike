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

  def initialize(occupied: [], library_images: {})
    @occupied = occupied
    @library_images = library_images
    @calls = []
    @next_id = 0
  end

  def get(path, query = {})
    @calls << [:get, path, query]
    case path
    when %r{/appStoreVersions\z}
      { "data" => [{ "id" => "v1", "attributes" => { "appStoreState" => "WAITING_FOR_REVIEW" } }] }
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
      { "data" => { "attributes" => { "state" => "PREPARE_FOR_SUBMISSION" } } }
    else
      raise "unexpected GET #{path}"
    end
  end

  def post(path, body)
    @calls << [:post, path, body]
    @next_id += 1
    { "data" => { "id" => "new-#{@next_id}", "attributes" => { "uploadOperations" => [
      { "method" => "PUT", "url" => "https://upload.example/part", "offset" => 0, "length" => 3 }
    ] } } }
  end

  def patch(path, body)
    @calls << [:patch, path, body]
    {}
  end

  def put_part(operation, bytes)
    @calls << [:put, operation["url"], bytes.bytesize]
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
    @manifest = {
      "en-US" => entry("en"), "en-GB" => entry("en"), "uk" => entry("uk")
    }
    @manifest_path = File.join(@root, "manifest.json")
    File.write(@manifest_path, JSON.generate(@manifest))
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def entry(key)
    {
      "header" => { "path" => "out/header-#{key}.png", "sha256" => "a" * 64, "copy" => key },
      "search" => { "path" => "out/search-#{key}.png", "sha256" => "b" * 64, "copy" => key }
    }
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
end
