require "base64"

# One resolver for the App Store Connect API key, because the Fastfile has two
# consumers that disagree about Base64: the `app_store_connect_api_key` action
# takes `is_key_content_base64` and decodes for itself, while
# `Spaceship::ConnectAPI.auth` has no such option and hands `key:` straight to
# `OpenSSL::PKey::EC.new`. A Base64 key passed to the second one raises before
# a lane reaches App Store Connect, so the decoding happens here instead.
module AppStoreAPICredentials
  class MissingCredential < StandardError; end

  Resolved = Struct.new(:key_id, :issuer_id, :key_filepath, :key_content, :key_content_base64, keyword_init: true) do
    # Options for the `app_store_connect_api_key` action, which decodes the
    # content itself when told the flag.
    def action_options(duration: 1200, in_house: false)
      options = {
        key_id: key_id,
        issuer_id: issuer_id,
        duration: duration,
        in_house: in_house
      }

      if key_filepath
        options[:key_filepath] = key_filepath
      else
        options[:key_content] = key_content
        options[:is_key_content_base64] = key_content_base64
      end

      options
    end

    # Options for `Spaceship::ConnectAPI.auth`, which cannot decode: the key is
    # already PEM here.
    def spaceship_auth_options
      options = { key_id: key_id, issuer_id: issuer_id }

      if key_filepath
        options[:filepath] = File.expand_path(key_filepath)
      else
        options[:key] = decoded_key_content
      end

      options
    end

    def decoded_key_content
      key_content_base64 ? Base64.decode64(key_content) : key_content
    end
  end

  module_function

  def resolve(env = ENV)
    key_id = env["APP_STORE_CONNECT_KEY_ID"].to_s
    issuer_id = env["APP_STORE_CONNECT_ISSUER_ID"].to_s
    key_filepath = env["APP_STORE_CONNECT_API_KEY_PATH"].to_s
    key_content = env["APP_STORE_CONNECT_API_KEY_CONTENT"].to_s
    key_content_base64 = env["APP_STORE_CONNECT_API_KEY_IS_BASE64"].to_s == "true"

    raise MissingCredential, "APP_STORE_CONNECT_KEY_ID is required" if key_id.empty?
    raise MissingCredential, "APP_STORE_CONNECT_ISSUER_ID is required" if issuer_id.empty?

    if key_filepath.empty? && key_content.empty?
      raise MissingCredential, "APP_STORE_CONNECT_API_KEY_PATH or APP_STORE_CONNECT_API_KEY_CONTENT is required"
    end

    Resolved.new(
      key_id: key_id,
      issuer_id: issuer_id,
      key_filepath: key_filepath.empty? ? nil : key_filepath,
      key_content: key_content.empty? ? nil : key_content,
      key_content_base64: key_content_base64
    )
  end
end
