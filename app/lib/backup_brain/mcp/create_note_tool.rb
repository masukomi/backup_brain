module BackupBrain
  module Mcp
    # Creates a new note. Needs the write:notes permission.
    class CreateNoteTool < BaseTool
      tool_name "create_note"
      description I18n.t("mcp.tools.create_note.description")
      input_schema(
        properties: {
          markdown: {type: "string", description: I18n.t("mcp.tools.create_note.params.markdown")},
          title: {type: "string", description: I18n.t("mcp.tools.create_note.params.title")},
          tags: {
            type: "array",
            items: {type: "string"},
            description: I18n.t("mcp.tools.create_note.params.tags")
          },
          private: {type: "boolean", description: I18n.t("mcp.tools.create_note.params.private")},
          sensitive: {type: "boolean", description: I18n.t("mcp.tools.create_note.params.sensitive")}
        },
        required: ["markdown"]
      )
      annotations(read_only_hint: false, destructive_hint: false, idempotent_hint: false, open_world_hint: false)

      class << self
        def call(markdown:, title: nil, tags: [], private: true, sensitive: false, server_context:)
          return permission_error("write", Note) unless permitted?(server_context, "write", Note)

          note = Note.new(
            string_data: markdown,
            title: title.presence,
            tags: Tag.split_tags(Array(tags)),
            private: private,
            sensitive: sensitive
          )
          unless note.save
            return error_response(
              I18n.t("mcp.errors.validation_failed", errors: note.errors.full_messages.join("; "))
            )
          end

          json_response(
            id: note.id.to_s,
            title: note.title,
            tags: note.tags,
            private: note.private,
            sensitive: note.sensitive,
            created_at: note.created_at&.iso8601,
            app_url: "#{base_url(server_context)}/notes/#{note.id}"
          )
        end
      end
    end
  end
end
