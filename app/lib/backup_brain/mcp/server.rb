module BackupBrain
  module Mcp
    # Builds the MCP::Server that McpController hands each request to.
    # The server is stateless: every request carries its own API key,
    # which the tools read back out of server_context.
    module Server
      NAME = "backup_brain".freeze
      VERSION = "1.0.0".freeze

      TOOLS = [
        SearchTool,
        GetBookmarkTool,
        GetNoteTool,
        CreateNoteTool
      ].freeze

      # @param [ApiKey] api_key - the authenticated key making the request
      # @param [String] base_url - scheme + host (+ port) of this instance,
      #        used to build links back to records
      # @return [MCP::Server]
      def self.build(api_key:, base_url:)
        MCP::Server.new(
          name: NAME,
          version: VERSION,
          instructions: I18n.t("mcp.server.instructions"),
          tools: TOOLS,
          server_context: {api_key: api_key, base_url: base_url}
        )
      end
    end
  end
end
