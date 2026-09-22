# Authenticates requests for the raw (machine readable) response formats
# via an `Authorization: Bearer <key>` header.
#
# HTML requests are never touched by this - they continue to rely on
# Devise sessions.
module ApiKeyAuthenticatable
  extend ActiveSupport::Concern

  # the formats that require an API key
  RAW_FORMATS = %i[json md].freeze

  included do
    attr_reader :current_api_key
  end

  protected

  def raw_format?
    RAW_FORMATS.include?(request.format.symbol)
  end

  # Renders an error & returns false when the request can't proceed.
  # Returning false from a before_action doesn't halt the chain, but
  # rendering does, so failures here stop the request.
  #
  # @param [Class] for_model - the model the caller needs "read" access to
  def require_api_key!(for_model:)
    presented = authenticate_with_http_token { |token, _options| token }
    return render_api_error(:unauthorized, t("api.errors.missing_key")) if presented.blank?

    key = ApiKey.authenticate(presented)
    return render_api_error(:unauthorized, t("api.errors.invalid_key")) if key.nil?

    unless key.permits?("read", for_model)
      return render_api_error(
        :forbidden,
        t("api.errors.insufficient_permissions",
          permission: "read:#{BackupBrain::ModelPaths.path_string(for_model)}")
      )
    end

    @current_api_key = key
  end

  def render_api_error(status, message)
    response.headers["WWW-Authenticate"] = 'Bearer realm="BackupBrain"' if status == :unauthorized
    if request.format.symbol == :md
      render md: "# #{t("api.errors.heading")}\n\n#{message}\n", status: status
    else
      render json: {error: message}, status: status
    end
    false
  end
end
