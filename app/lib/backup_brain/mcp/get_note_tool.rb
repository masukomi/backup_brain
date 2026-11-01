module BackupBrain
  module Mcp
    # The full Markdown of one note.
    class GetNoteTool < BaseTool
      tool_name "get_note"
      description I18n.t("mcp.tools.get_note.description")
      input_schema(
        properties: {
          id: {type: "string", description: I18n.t("mcp.tools.get_note.params.id")}
        },
        required: ["id"]
      )
      annotations(read_only_hint: true, idempotent_hint: true, open_world_hint: false)

      class << self
        def call(id:, server_context:)
          return permission_error("read", Note) unless permitted?(server_context, "read", Note)
          note = find_readable(server_context, Note, id)
          return not_found_error if note.nil?

          json_response(
            id: note.id.to_s,
            title: note.title,
            tags: note.tags,
            private: note.private,
            sensitive: note.sensitive,
            mime_type: note.mime_type,
            created_at: note.created_at&.iso8601,
            updated_at: note.updated_at&.iso8601,
            app_url: "#{base_url(server_context)}/notes/#{note.id}",
            markdown: note.string_data
          )
        end
      end
    end
  end
end
