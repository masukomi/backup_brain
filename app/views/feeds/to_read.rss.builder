xml.instruct! :xml, version: "1.0", encoding: "UTF-8"
xml.rss "version" => "2.0" do
  xml.channel do
    xml.title       t("feeds.to_read.title")
    xml.link        root_url
    xml.description t("feeds.to_read.description")
    xml.language    "en-us"

    @bookmarks.each do |bookmark|
      archive = bookmark.sorted_archives.first
      description = if archive&.string_data.present?
        @valid_secret_key ?
          add_secret_key_to_archive_urls(archive.string_data, @secret_key) :
          archive.string_data
      else
        I18n.t("archives.notes.no_archive", url: bookmark.url,
          error: if bookmark.last_archive_attempt_failed?
                   bookmark.failed_archive_attempts.last.status_code
                 else
                   I18n.t("archives.errors.unknown_error_code")
                 end)
      end

      xml.item do
        xml.title   bookmark.title
        xml.link    bookmark.url
        xml.description { xml.cdata! description }
        xml.pubDate bookmark.created_at.rfc2822
        xml.guid    bookmark.id.to_s
      end
    end
  end
end
