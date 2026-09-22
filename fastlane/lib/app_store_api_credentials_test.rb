# Offline test for the API key resolver. No network, no fastlane runner: the
# assertions below are what "the Base64 flag reaches Spaceship" means, since the
# lane failure it guards against happens at OpenSSL parse time, before any
# request leaves the machine.
#
#   ruby fastlane/lib/app_store_api_credentials_test.rb
require "minitest/autorun"
require "openssl"
require_relative "app_store_api_credentials"

class AppStoreAPICredentialsTest < Minitest::Test
  PEM = OpenSSL::PKey::EC.generate("prime256v1").to_pem

  def env(overrides = {})
    {
      "APP_STORE_CONNECT_KEY_ID" => "KEYID",
      "APP_STORE_CONNECT_ISSUER_ID" => "ISSUER"
    }.merge(overrides)
  end

  def test_base64_content_reaches_spaceship_decoded
    resolved = AppStoreAPICredentials.resolve(env(
      "APP_STORE_CONNECT_API_KEY_CONTENT" => Base64.strict_encode64(PEM),
      "APP_STORE_CONNECT_API_KEY_IS_BASE64" => "true"
    ))

    key = resolved.spaceship_auth_options[:key]
    assert_equal(PEM, key)
    # The regression: the encoded content used to arrive here and raise.
    OpenSSL::PKey::EC.new(key)
  end

  def test_base64_content_keeps_the_flag_for_the_action
    encoded = Base64.strict_encode64(PEM)
    options = AppStoreAPICredentials.resolve(env(
      "APP_STORE_CONNECT_API_KEY_CONTENT" => encoded,
      "APP_STORE_CONNECT_API_KEY_IS_BASE64" => "true"
    )).action_options

    assert_equal(encoded, options[:key_content])
    assert_equal(true, options[:is_key_content_base64])
    refute(options.key?(:key_filepath))
  end

  def test_plain_content_is_passed_through
    resolved = AppStoreAPICredentials.resolve(env("APP_STORE_CONNECT_API_KEY_CONTENT" => PEM))

    assert_equal(PEM, resolved.spaceship_auth_options[:key])
    assert_equal(false, resolved.action_options[:is_key_content_base64])
  end

  def test_filepath_wins_and_is_expanded
    resolved = AppStoreAPICredentials.resolve(env(
      "APP_STORE_CONNECT_API_KEY_PATH" => "~/keys/AuthKey.p8",
      "APP_STORE_CONNECT_API_KEY_CONTENT" => Base64.strict_encode64(PEM),
      "APP_STORE_CONNECT_API_KEY_IS_BASE64" => "true"
    ))

    auth = resolved.spaceship_auth_options
    assert_equal(File.expand_path("~/keys/AuthKey.p8"), auth[:filepath])
    refute(auth.key?(:key))
    assert_equal("~/keys/AuthKey.p8", resolved.action_options[:key_filepath])
    refute(resolved.action_options.key?(:key_content))
  end

  def test_missing_credentials_are_reported
    assert_raises(AppStoreAPICredentials::MissingCredential) do
      AppStoreAPICredentials.resolve(env("APP_STORE_CONNECT_KEY_ID" => ""))
    end

    assert_raises(AppStoreAPICredentials::MissingCredential) do
      AppStoreAPICredentials.resolve(env("APP_STORE_CONNECT_ISSUER_ID" => ""))
    end

    # The gap the old `connect_api_login!` had: no key at all reached Spaceship
    # as `key: nil` instead of a readable error.
    assert_raises(AppStoreAPICredentials::MissingCredential) do
      AppStoreAPICredentials.resolve(env)
    end
  end
end
