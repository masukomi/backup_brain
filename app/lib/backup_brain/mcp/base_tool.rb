module BackupBrain
  module Mcp
    # Shared plumbing for the MCP tools: permission checks against the
    # calling ApiKey, record lookups that treat "forbidden" and "missing"
    # alike, and JSON text responses.
    class BaseTool < MCP::Tool
      class << self
        # @param [MCP::ServerContext, Hash] server_context
        # @return [ApiKey, nil]
        def api_key(server_context)
          context_value(server_context, :api_key)
        end

        # @return [String] e.g. "https://bb.example.com"
        def base_url(server_context)
          context_value(server_context, :base_url).to_s
        end

        # @param [String] action - "read" or "write"
        # @param [Class] klass - Bookmark or Note
        # @return [Boolean]
        def permitted?(server_context, action, klass)
          key = api_key(server_context)
          key.present? && key.permits?(action, klass)
        end

        # @return [String] the permission string the key would need
        def permission_name(action, klass)
          "#{action}:#{BackupBrain::ModelPaths.path_string(klass)}"
        end

        # Finds a record the caller is allowed to read. Anything they can't
        # see, for whatever reason, is reported as not found so a caller
        # can't probe for the existence of private records.
        #
        # @param [Class] klass - Bookmark or Note
        # @param [String] id
        # @return [Mongoid::Document, nil]
        def find_readable(server_context, klass, id)
          return nil unless permitted?(server_context, "read", klass)
          klass.find(id)
        rescue Mongoid::Errors::DocumentNotFound, BSON::Error::InvalidObjectId
          nil
        end

        # @param [Hash, Array] payload - serialized as JSON in a text block
        # @return [MCP::Tool::Response]
        def json_response(payload)
          MCP::Tool::Response.new([{type: "text", text: JSON.pretty_generate(payload)}])
        end

        # @param [String] message
        # @return [MCP::Tool::Response] flagged as an error
        def error_response(message)
          MCP::Tool::Response.new([{type: "text", text: message}], error: true)
        end

        def permission_error(action, klass)
          error_response(
            I18n.t("api.errors.insufficient_permissions",
              permission: permission_name(action, klass))
          )
        end

        def not_found_error
          error_response(I18n.t("api.errors.not_found"))
        end

        # Cuts text down to max_characters, when one was given.
        #
        # @return [Array(String, Boolean)] the (possibly shortened) text and
        #         whether anything was cut off
        def truncate(text, max_characters)
          return [text, false] if text.nil? || max_characters.nil? || text.length <= max_characters
          [text[0, max_characters], true]
        end

        private

        # The gem wraps the hash we hand MCP::Server in a ServerContext that
        # forwards unknown methods to it, but tests may pass the bare hash.
        def context_value(server_context, name)
          if server_context.respond_to?(:[])
            server_context[name]
          else
            server_context.public_send(name)
          end
        end
      end
    end
  end
end
