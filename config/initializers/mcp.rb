# The MCP (Model Context Protocol) server is served by McpController at /mcp.
# The tools live in app/lib/backup_brain/mcp/.
MCP.configure do |config|
  config.exception_reporter = ->(exception, _server_context) {
    Rails.logger.error("MCP: #{exception.class}: #{exception.message}")
  }
end
