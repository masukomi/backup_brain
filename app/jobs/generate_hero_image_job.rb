require "base64"
require "fileutils"
require "digest"

class GenerateHeroImageJob < ApplicationJob
  include BackupBrain::ArchiveTools
  include BackupBrain::ImageGenerationHelpers

  GEMINI_TEXT_MODEL = "gemini-2.5-flash"
  GEMINI_IMAGE_MODEL = "gemini-2.5-flash-image"

  # XXX FIXME: replace with latest successful version
  DEFAULT_PROMPT = <<~PROMPT.strip
    You are helping generate prompts for an AI image generator that must strictly comply with Google's Generative AI Prohibited Use Policy. The prompt you generate must be two paragraphs at most.

    Read the following audio transcript. Determine the number of characters in the scene. Pay special attention to gender markers to determine the gender of the characters. If you are unsure about the gender of a character describe them as being androgynous.  Determine what activities they are describing or participating in, any physical or emotional dynamic between them, and any notable objects or setting details in the scene.

    Before generating the image prompt, apply the following single content rule:
    - If the content depicts or describes nudity or exposed body parts, represent the
        people as clothed in contextually appropriate attire instead, preserving as much
        of the scene's mood, physical closeness, and emotional dynamic as possible.

    Then write a concise image generation prompt suitable for that visually represents the content.

    Focus on the most important concrete visual elements and tonal words. Use descriptive but simple language. Do not include meta-commentary, explanation, or headings. Output only the image prompt itself.

    Start the prompt with instructions to produce a square image with a modern manga style.

  PROMPT

  queue_as :low_priority

  # @param bookmark_id [String] BSON ObjectId string of the parent bookmark
  # @param archive_id [String] BSON ObjectId string of the archive to generate an image for
  def perform(bookmark_id:, archive_id:)
    unless enabled?
      Rails.logger.warn("GenerateHeroImageJob: generate_audio_hero_images is disabled, skipping")
      return false
    end

    api_key = fetch_api_key
    if api_key.blank?
      Rails.logger.warn("GenerateHeroImageJob: gemini_api_key setting is not set, skipping")
      return false
    end

    bookmark, archive = load_bookmark_and_archive(bookmark_id, archive_id)
    return false unless bookmark && archive

    image_prompt = generate_prompt(bookmark, archive, api_key: api_key)
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

  # Returns the generated image prompt for a given bookmark/archive.
  # Useful for testing prompt quality from the Rails console:
  #   GenerateHeroImageJob.new.generate_prompt(bookmark, archive)
  def generate_prompt(bookmark, archive, api_key: fetch_api_key)
    guidance = begin Setting.get_value_of_key("audio_transcript_image_prompt_guidance").to_s rescue DEFAULT_PROMPT
    end
    content = get_content_for_archive(archive)
    raise "No Content in Archive" if content.blank?
    generate_image_prompt(api_key, guidance, content)
  end

  # Generates an image from the given prompt and saves it to output_path.
  # Returns the output path on success, nil on failure.
  # Useful for testing image generation from the Rails console:
  #   GenerateHeroImageJob.new.generate_image_for("anime style, ...", output_path: "/tmp/test.png")
  def generate_image_file(prompt, api_key: fetch_api_key, output_path: "/tmp/test_hero_image.png")
    raise "No API Key" if api_key.blank?
    image_data = generate_image(api_key, prompt)
    return nil unless image_data
    File.binwrite(output_path, image_data)
    output_path
  end

  private

  def fetch_api_key
    Setting.get_value_of_key("gemini_api_key").to_s.strip rescue nil
  end

  def enabled?
    Setting.get_value_of_key("generate_audio_hero_images") == true rescue false
  end

  def load_bookmark_and_archive(bookmark_id, archive_id)
    bookmark = Bookmark.find(bookmark_id)
    archive = bookmark.archives.find { |a| a._id.to_s == archive_id }
    unless archive
      Rails.logger.warn("GenerateHeroImageJob: archive #{archive_id} not found on bookmark #{bookmark_id}")
      return [nil, nil]
    end
    [bookmark, archive]
  rescue
    Rails.logger.warn("GenerateHeroImageJob: bookmark #{bookmark_id} not found")
    [nil, nil]
  end

  GEMINI_API_BASE = "https://generativelanguage.googleapis.com/v1beta/models"

  def gemini_generate_content(api_key, model, payload)
    response = HTTParty.post(
      "#{GEMINI_API_BASE}/#{model}:generateContent",
      query: {key: api_key},
      body: payload.to_json,
      headers: {"Content-Type" => "application/json"},
      timeout: 120
    )
    response.parsed_response
  end

  def generate_image_prompt_with_gemini(api_key, guidance, content)
    result = gemini_generate_content(api_key, GEMINI_TEXT_MODEL, {
      contents: [{parts: [{text: "#{guidance}\n\n--- Content ---\n\n#{content}"}]}]
    })

    if result.is_a?(Hash) && result.dig("error")
      handle_gemini_api_error(result["error"], "prompt generation")
      return nil
    end

    prompt = result.dig("candidates", 0, "content", "parts", 0, "text")&.strip
    if prompt.blank?
      prompt_feedback = result.dig("promptFeedback")
      if prompt_feedback.present?
        Rails.logger.error("GenerateHeroImageJob: Gemini returned no text for image prompt: #{prompt_feedback.inspect}")
      else
        Rails.logger.error("GenerateHeroImageJob: Gemini returned no text for image prompt. No feedback provided.")
      end
      return nil
    end
    prompt
  rescue => e
    handle_gemini_exception(e, "gemini prompt generation")
    nil
  end

  def generate_image_prompt_with_ollama(guidance, content)
    # these two settings are guaranteed present by virtue of the fact
    # that enable_local_ollama was set to true
    Setting.get_value_of_key("ollama_model")
    Setting.get_value_of_key("ollama_url")
    full_prompt = "#{guidance}\n\n--- Content ---\n\n#{content}"

    uri = URI("#{OLLAMA_URL}/api/generate")
    http = Net::HTTP.new(uri.host, uri.port)
    http.read_timeout = 300

    request = Net::HTTP::Post.new(uri.path, "Content-Type" => "application/json")
    request.body = {model: OLLAMA_MODEL, prompt: full_prompt, stream: false}.to_json
    response = http.request(request)
    result = JSON.parse(response.body)

    if result["error"]
      handle_ollama_api_error(result["error"])
      return nil
    end

    result["response"]
  rescue Errno::ECONNREFUSED => e
    handle_ollama_connection_error(e)
    nil
  end

  def generate_image_prompt(api_key, guidance, content)
    if Setting.get_value_of_key("enable_local_ollama") == true
      generate_image_prompt_with_ollama(guidance, content)
    else
      generate_image_prompt_with_gemini(api_key, guidance, content)
    end
  rescue => e
    handle_gemini_exception(e, "prompt generation")
    nil
  end

  def generate_image(api_key, image_prompt)
    result = gemini_generate_content(api_key, GEMINI_IMAGE_MODEL, {
      contents: [{parts: [{text: image_prompt}]}],
      generationConfig: {responseModalities: ["IMAGE"]}
    })

    if result.is_a?(Hash) && result.dig("error")
      handle_gemini_api_error(result["error"], "image generation")
      return nil
    end

    b64 = result.dig("candidates", 0, "content", "parts", 0, "inlineData", "data")
    if b64.blank?
      Rails.logger.warn("GenerateHeroImageJob: Gemini returned no image data")
      return nil
    end
    Base64.strict_decode64(b64)
  rescue => e
    handle_gemini_exception(e, "image generation")
    nil
  end

  def handle_ollama_connection_error(error)
    Rails.logger.warn("GenerateHeroImageJob: Ollama connection refused. Is it running? #{error}")
  end

  def handle_ollama_api_error(error_message)
    Rails.logger.warn("GenerateHeroImageJob: Ollama API error #{error}")
  end

  def handle_gemini_api_error(error_body, context)
    code = error_body["code"].to_i
    message = error_body["message"].to_s
    if code == 429
      retry_delay = parse_retry_delay_from_error(error_body)
      handle_rate_limit(retry_delay)
    else
      Rails.logger.warn("GenerateHeroImageJob: Gemini API error #{code} during #{context}: #{message.truncate(200)}")
    end
  end

  def handle_gemini_exception(error, context)
    if error.respond_to?(:response) && error.response
      status = error.response[:status]
      body = error.response[:body].to_s
      if status == 429 # Quota Exceeded
        retry_delay = begin
          parsed = JSON.parse(body)
          parse_retry_delay_from_error(parsed["error"] || {})
        rescue
          60
        end
        handle_rate_limit(retry_delay)
      else
        Rails.logger.warn("GenerateHeroImageJob: Gemini API #{status} during #{context}: #{body.truncate(500)}")
      end
    else
      Rails.logger.warn("GenerateHeroImageJob: error during #{context}: #{error.message.to_s.truncate(200)}")
    end
  end

  # rubocop:disable Rails/SkipsModelValidations
  def handle_rate_limit(retry_delay = 60)
    retry_at = Time.current + retry_delay.seconds
    count = Delayed::Job.where(handler: /GenerateHeroImageJob/).update_all(run_at: retry_at)
    Rails.logger.warn("GenerateHeroImageJob: rate limited — rescheduled #{count} pending instances to #{retry_at}")
  end
  # rubocop:enable Rails/SkipsModelValidations

  def parse_retry_delay_from_error(error_body)
    details = error_body["details"] || []
    delay_str = details.filter_map { |d| d["retryDelay"] }.first.to_s
    (delay_str =~ /(\d+)/) ? $1.to_i : 60
  end
end
