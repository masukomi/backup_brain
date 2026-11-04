module BackupBrain
  module Mcp
    # A bookmark's metadata, the Markdown of its most recent archive,
    # and the most recent completed transcription of its archived media.
    class GetBookmarkTool < BaseTool
      tool_name "get_bookmark"
      description I18n.t("mcp.tools.get_bookmark.description")
      input_schema(
        properties: {
          id: {type: "string", description: I18n.t("mcp.tools.get_bookmark.params.id")},
          include_archive: {type: "boolean", description: I18n.t("mcp.tools.get_bookmark.params.include_archive")},
          include_transcription: {type: "boolean", description: I18n.t("mcp.tools.get_bookmark.params.include_transcription")},
          max_characters: {type: "integer", minimum: 1, description: I18n.t("mcp.tools.get_bookmark.params.max_characters")}
        },
        required: ["id"]
      )
      annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: false)

      class << self
        def call(id:, include_archive: true, include_transcription: true, max_characters: nil, server_context:)
          return permission_error("read", Bookmark) unless permitted?(server_context, "read", Bookmark)
          bookmark = find_readable(server_context, Bookmark, id)
          return not_found_error if bookmark.nil?

          payload = {
            id: bookmark.id.to_s,
            title: bookmark.title,
            url: bookmark.url,
            description: bookmark.description,
            tags: bookmark.tags,
            private: bookmark.private,
            sensitive: bookmark.sensitive,
            to_read: bookmark.to_read,
            created_at: bookmark.created_at&.iso8601,
            app_url: "#{base_url(server_context)}/bookmarks/#{bookmark.id}",
            archive: nil,
            transcription: nil
          }
          payload[:archive] = archive_payload(bookmark, max_characters) if include_archive
          payload[:transcription] = transcription_payload(bookmark, max_characters) if include_transcription
          json_response(payload)
        end

        private

        def archive_payload(bookmark, max_characters)
          archive = bookmark.latest_archive("text/markdown")
          return nil if archive.nil?
          text, truncated = truncate(archive.string_data, max_characters)
          {
            mime_type: archive.mime_type,
            created_at: archive.created_at&.iso8601,
            manually_edited: archive.manually_edited,
            truncated: truncated,
            markdown: text
          }
        end

        def transcription_payload(bookmark, max_characters)
          transcription = bookmark.latest_transcription
          return nil if transcription.nil?
          text, truncated = truncate(transcription.text_without_timestamps, max_characters)
          {
            source: transcription.source,
            media_url: transcription.media_object.web_path,
            media_type: transcription.media_object.simple_type,
            created_at: transcription.created_at&.iso8601,
            truncated: truncated,
            text: text
          }
        end
      end
    end
  end
end
