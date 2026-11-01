# Serves the MCP (Model Context Protocol) server over Streamable HTTP
# at /mcp. Every request must carry an API key as a Bearer token. The
# tools (app/lib/backup_brain/mcp/) check that key's permissions.
#
# The server is stateless: there are no sessions and no server-initiated
# messages, so GET (SSE streams) and DELETE (session teardown) answer 405,
# which the MCP spec allows.
class McpController < ApplicationController
  # MCP clients have no session to carry a CSRF token in. A missing
  # key answers 401 below rather than tripping forgery protection.
  skip_before_action :verify_authenticity_token
  before_action :require_mcp_key

  def handle
    server = BackupBrain::Mcp::Server.build(
      api_key: current_api_key,
      base_url: request.base_url
    )
    body = server.handle_json(request.raw_post)
    # notifications get no response
    return head :accepted if body.nil?
    render json: body
  end

  def not_supported
    head :method_not_allowed
  end

  private

  def require_mcp_key
    presented = authenticate_with_http_token { |token, _options| token }
    return render_mcp_error(:unauthorized, t("api.errors.missing_key")) if presented.blank?

    key = ApiKey.authenticate(presented)
    return render_mcp_error(:unauthorized, t("api.errors.invalid_key")) if key.nil?

    @current_api_key = key
  end

  # Auth failures happen before any JSON-RPC request is parsed, so they're
  # plain HTTP errors, which is what the MCP authorization spec expects.
  def render_mcp_error(status, message)
    response.headers["WWW-Authenticate"] = 'Bearer realm="BackupBrain"' if status == :unauthorized
    render json: {error: message}, status: status
    false
  end
end
