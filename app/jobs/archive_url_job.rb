require "net/http"
require "uri"
require "readability"
require "reverse_markdown"

class UnarchivableUrl < StandardError; end

class ArchiveUrlJob < ApplicationJob
  include BackupBrain::ArchiveTools

  # it seems ridiculous that i have to specify all the effing tags
  # in order to get it to just give me the core content.
  # note: these are all the tags that markdown supports
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
  ]

  queue_as :low_priority # :default

  # args contains
  # bookmark
  def perform(*bookmarks)
    bookmark = bookmarks.first
    response = download(bookmark.url)
    core_content = get_core_content(response.body)
    markdown = ReverseMarkdown.convert core_content
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
    ).content.gsub(/<\/p><p>/i, "</p>\n<p>")
  end

  def download(url)
    raise UnarchivableUrl("Server says no: #{url}") unless url_downloadable?(url)
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
  # def fetch(uri_str, limit = 10)
  #   # You should choose better exception.
  #   raise ArgumentError, "HTTP redirect too deep" if limit == 0

  #   url = URI.parse(uri_str)
  #   req = Net::HTTP::Get.new(url.path, {"User-Agent" => "Mozilla/5.0 (etc...)"})
  #   response = Net::HTTP.start(url.host, url.port, use_ssl: true) { |http| http.request(req) }
  #   case response
  #   when Net::HTTPSuccess     then response
  #   when Net::HTTPRedirection then fetch(response["location"], limit - 1)
  #   else
  #     response.error!
  #   end
  #   response
  # end
end
