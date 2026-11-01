module BackupBrain
  module Mcp
    # Full text search across bookmarks and notes via Meilisearch.
    # Results are summaries: enough to decide which records are worth
    # fetching with get_bookmark / get_note, without the archive text.
    class SearchTool < BaseTool
      TYPES = %w[bookmarks notes].freeze
      DEFAULT_LIMIT = 20
      MAX_LIMIT = 100
      NOTE_EXCERPT_LENGTH = 200
      BOOKMARK_METADATA_ATTRIBUTES = %w[title description tags url].freeze

      tool_name "search"
      description I18n.t("mcp.tools.search.description")
      input_schema(
        properties: {
          query: {type: "string", description: I18n.t("mcp.tools.search.params.query")},
          types: {
            type: "array",
            items: {type: "string", enum: TYPES},
            description: I18n.t("mcp.tools.search.params.types")
          },
          tags: {
            type: "array",
            items: {type: "string"},
            description: I18n.t("mcp.tools.search.params.tags")
          },
          search_archives: {type: "boolean", description: I18n.t("mcp.tools.search.params.search_archives")},
          limit: {
            type: "integer", minimum: 1, maximum: MAX_LIMIT,
            description: I18n.t("mcp.tools.search.params.limit", default_limit: DEFAULT_LIMIT, max: MAX_LIMIT)
          }
        },
        required: ["query"]
      )
      annotations(read_only_hint: true, idempotent_hint: true, open_world_hint: false)

      class << self
        def call(query:, types: TYPES, tags: [], search_archives: false, limit: DEFAULT_LIMIT, server_context:)
          query, inline_tags = Tag.extract_tags_from_string(query.to_s)
          tags = Tag.split_tags(Array(tags) + inline_tags)
          return error_response(I18n.t("search.missing_query")) if query.blank? && tags.blank?

          limit = limit.to_i.clamp(1, MAX_LIMIT)
          wanted = Array(types).map(&:to_s).uniq & TYPES
          wanted = TYPES if wanted.empty?

          payload = {query: query, tags: tags, denied: []}
          wanted.each do |type|
            klass = (type == "bookmarks") ? Bookmark : Note
            unless permitted?(server_context, "read", klass)
              payload[:denied] << permission_name("read", klass)
              next
            end
            records = find_records(klass, query, tags, limit, search_archives)
            payload[type.to_sym] = records.map { |r| summarize(r, server_context) }
          end
          json_response(payload)
        rescue MeiliSearch::ApiError => e
          error_response(I18n.t("api.errors.search_unavailable", error: e.message))
        end

        private

        # @return [Array<Mongoid::Document>] in Meilisearch's relevance order
        def find_records(klass, query, tags, limit, search_archives)
          options = {limit: limit, offset: 0}
          options[:filter] = "tags IN [#{tags.join(", ")}]" if tags.present?
          options[:attributes_to_search_on] = if klass == Note
            Note::QUERYABLE_ATTRIBUTES
          elsif !search_archives
            BOOKMARK_METADATA_ATTRIBUTES
          end
          options.compact!

          ids = klass.search(query, options: options, ids_only: true, filtered_by_class: true)["matches"]
          ids = ids.map(&:to_s)
          records = klass.where(:id.in => ids)
          records = records.tagged_with_all(tags) if tags.present?
          records.sort_by { |r| ids.index(r.id.to_s) || ids.size }
        end

        def summarize(record, server_context)
          case record
          when Bookmark then summarize_bookmark(record, server_context)
          else summarize_note(record, server_context)
          end
        end

        def summarize_bookmark(bookmark, server_context)
          {
            type: "bookmark",
            id: bookmark.id.to_s,
            title: bookmark.title,
            url: bookmark.url,
            description: bookmark.description,
            tags: bookmark.tags,
            private: bookmark.private,
            has_archive: bookmark.latest_archive("text/markdown").present?,
            has_transcription: bookmark.latest_transcription.present?,
            created_at: bookmark.created_at&.iso8601,
            app_url: "#{base_url(server_context)}/bookmarks/#{bookmark.id}"
          }
        end

        def summarize_note(note, server_context)
          {
            type: "note",
            id: note.id.to_s,
            title: note.title,
            excerpt: note.string_data.to_s.truncate(NOTE_EXCERPT_LENGTH),
            tags: note.tags,
            private: note.private,
            created_at: note.created_at&.iso8601,
            updated_at: note.updated_at&.iso8601,
            app_url: "#{base_url(server_context)}/notes/#{note.id}"
          }
        end
      end
    end
  end
end
