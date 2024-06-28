require "net/http"
require "uri"
require "readability"
require "reverse_markdown"

class ArchiveUrlJob < ApplicationJob
  include BackupBrain::ArchiveTools
  queue_as :archiving

  # it seems ridiculous that i have to specify all the effing tags
  # in order to get it to just give me the core content.
  # NOTE: THESE ARE ALL THE TAGS THAT MARKDOWN SUPPORTS
  READABILITY_TAGS = %w[
    div
    p br
    img
    a
    strong em i b
    h1 h2 h3 h4 h5 h6
    blockquote
    ol ul li
    dd dt
    code pre tt

    table
  ]

  queue_as :low_priority # :default

  def perform(bookmark_id:)
    bookmark = begin
      Bookmark.find(bookmark_id)
    rescue
      nil
    end
    return unless bookmark

    response = download(bookmark.url)
    core_content = get_core_content(response.body)
    markdown = ReverseMarkdown.convert(core_content, unknown_tags: :bypass)
    bookmark.archives << Archive.new(
      mime_type: "text/markdown",
      string_data: markdown
    )
    bookmark.save!
  rescue => e
    Rails.logger.warn("couldn't archive #{bookmark.url} - #{e.message}")
  end

  def get_core_content(full_html)
    Readability::Document.new(
      full_html,
      remove_empty_nodes: true,
      min_image_width: 200,
      ignore_image_format: [],
      tags: READABILITY_TAGS,
      attributes: %w[src href]
    )
      .content
      .gsub(/<\/p><p>/i, "</p>\n<p>")
  end

  def download(url)
    downloadable, error_code = url_downloadable?(url, include_code: true)
    raise BackupBrain::Errors::UnarchivableUrl.new("Remote server prevented download. Status code: #{error_code}") unless downloadable
    response = HTTParty.get(url,
      verify: false,
      timeout: 5,
      headers: {"User-Agent" => "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/104.0.5112.79 Safari/537.36"})
    if response.code < 400
      response
    else
      Rails.logger.warn("Failed to download #{url} - #{response.code}")
      raise UnarchivableUrl("Failed to download #{url} - #{response.code}")
    end
  end
end
