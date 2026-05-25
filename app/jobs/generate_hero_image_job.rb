require "net/http"
require "json"
require "base64"
require "fileutils"
require "digest"

class GenerateHeroImageJob < ApplicationJob
  include BackupBrain::ArchiveTools
  include BackupBrain::ImageGenerationHelpers

  GEMINI_TEXT_URL  = "https://generativelanguage.googleapis.com/v1beta/models/" \
                     "gemini-2.5-flash:generateContent"
  GEMINI_IMAGE_URL = "https://generativelanguage.googleapis.com/v1beta/models/" \
                     "gemini-2.5-flash-image:generateContent"

  DEFAULT_PROMPT = <<~PROMPT.strip
    You are helping generate prompts for an AI image generator. The prompt you generate
    must be two paragraphs at most and it must begin with stylization instructions.
    You do not need to use complete sentences.

    Given the following text from a web page archive or audio transcript,
    identify the key subjects, themes, people, objects, and setting described.
    Then write a concise image generation prompt suitable for
    producing a anime or illustration-style hero image that visually
    represents the content. Focus on the most important concrete visual elements
    and tonal words. Use descriptive but simple language. Do not include
    meta-commentary or explanation — output only the image prompt itself.
  PROMPT

  queue_as :low_priority

  # @param bookmark_id [String] BSON ObjectId string of the parent bookmark
  # @param archive_id [String] BSON ObjectId string of the archive to generate an image for
  def perform(bookmark_id:, archive_id:)
    unless enabled?
      Rails.logger.warn("GenerateHeroImageJob: generate_audio_hero_images is disabled, skipping")
      return false
    end

    api_key = Setting.get_value_of_key("gemini_api_key").to_s.strip rescue nil

    if api_key.blank?
      Rails.logger.warn("GenerateHeroImageJob: gemini_api_key setting is not set, skipping")
      return false
    end

    guidance = Setting.get_value_of_key("image_prompt_guidance").to_s rescue DEFAULT_PROMPT

    bookmark = begin
      Bookmark.find(bookmark_id)
    rescue
      Rails.logger.warn("GenerateHeroImageJob: bookmark #{bookmark_id} not found")
      return false
    end

    archive = bookmark.archives.find { |a| a._id.to_s == archive_id }
    unless archive
      Rails.logger.warn("GenerateHeroImageJob: archive #{archive_id} not found on bookmark #{bookmark_id}")
      return false
    end

    content = get_content_for_archive(archive)
    if content.blank?
      Rails.logger.warn("GenerateHeroImageJob: archive #{archive_id} has no usable text content")
      return false
    end

    image_prompt = generate_image_prompt(api_key, guidance, content)
    return false unless image_prompt

    image_data = generate_image(api_key, image_prompt)
    return false unless image_data

    store_image(bookmark, archive, image_data)
    bookmark.save!
    Rails.logger.info("GenerateHeroImageJob: hero image generated for archive #{archive_id}")
    true
  rescue => e
    Rails.logger.warn("GenerateHeroImageJob: unexpected error for archive #{archive_id}: #{e.message}")
    false
  end

  private

  def enabled?
    Setting.get_value_of_key("generate_audio_hero_images") == true
  rescue
    false
  end

  def generate_image_prompt(api_key, guidance, content)
    body = {
      contents: [{parts: [{text: "#{guidance}\n\n--- Content ---\n\n#{content}"}]}]
    }
    response = gemini_post(GEMINI_TEXT_URL, api_key, body)
    return nil unless response

    prompt = response.dig("candidates", 0, "content", "parts", 0, "text")&.strip
    if prompt.blank?
      Rails.logger.warn("GenerateHeroImageJob: Gemini returned no text for image prompt")
      return nil
    end
    prompt
  end

  def generate_image(api_key, image_prompt)
    body = {
      contents: [{parts: [{text: image_prompt}]}],
      generationConfig: {responseModalities: ["IMAGE"]}
    }
    response = gemini_post(GEMINI_IMAGE_URL, api_key, body)
    return nil unless response

    b64 = response.dig("candidates", 0, "content", "parts", 0, "inlineData", "data")
    if b64.blank?
      Rails.logger.warn("GenerateHeroImageJob: Gemini returned no image data")
      return nil
    end
    Base64.strict_decode64(b64)
  end

  def gemini_post(base_url, api_key, body)
    uri = URI("#{base_url}?key=#{api_key}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.read_timeout = 120

    request = Net::HTTP::Post.new(uri.request_uri, "Content-Type" => "application/json")
    request.body = body.to_json

    raw = http.request(request)

    if raw.code.to_i == 429
      handle_rate_limit(raw)
      return nil
    end

    unless raw.code.to_i < 300
      Rails.logger.warn("GenerateHeroImageJob: Gemini API returned #{raw.code}: #{raw.body.to_s.truncate(200)}")
      return nil
    end

    JSON.parse(raw.body)
  rescue JSON::ParserError => e
    Rails.logger.warn("GenerateHeroImageJob: failed to parse Gemini response: #{e.message}")
    nil
  end

  # rubocop:disable Rails/SkipsModelValidations
  def handle_rate_limit(response)
    retry_delay = parse_retry_delay(response)
    retry_at = Time.current + retry_delay.seconds
    count = Delayed::Job.where(handler: /GenerateHeroImageJob/).update_all(run_at: retry_at)
    Rails.logger.warn("GenerateHeroImageJob: rate limited — rescheduled #{count} pending instances to #{retry_at}")
  end
  # rubocop:enable Rails/SkipsModelValidations

  def parse_retry_delay(response)
    header_val = response["Retry-After"].to_s.strip
    return header_val.to_i if header_val.match?(/\A\d+\z/)

    body = begin
      JSON.parse(response.body)
    rescue
      {}
    end
    details = body.dig("error", "details") || []
    delay_str = details.filter_map { |d| d["retryDelay"] }.first.to_s
    delay_str.match(/(\d+)/) ? $1.to_i : 60
  end
end
