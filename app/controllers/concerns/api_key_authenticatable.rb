# Authenticates requests for the raw (machine readable) response formats
# via an `Authorization: Bearer <key>` header.
#
# Ordinary html requests are never touched by this - they continue to
# rely on Devise sessions.
module ApiKeyAuthenticatable
  extend ActiveSupport::Concern

  # the formats that are answered to api clients rather than browsers
  RAW_FORMATS = %i[json md].freeze

  included do
    attr_reader :current_api_key

    # An api client has no session to carry a CSRF token in. This is
    # deliberately narrow: forgery protection still applies to every
    # request made with a signed in session, which is the only thing
    # a CSRF attack has to work with.
    skip_before_action :verify_authenticity_token, if: :csrf_exempt?, raise: false
  end

  protected

  def raw_format?
    RAW_FORMATS.include?(request.format.symbol)
  end

  # true when the caller presented *some* token, valid or not.
  # Used to decide whether to authenticate by key or by session.
  def api_key_request?
    request.authorization.to_s.match?(/\A(Token|Bearer)\s/i)
  end

  def csrf_exempt?
    api_key_request? || (raw_format? && !user_signed_in?)
  end

  # Optional authentication: sets current_api_key when a valid key is
  # presented, and fails the request when an *invalid* one is. Callers
  # with no key at all pass through, and get whatever public records
  # an anonymous visitor would.
  def authenticate_api_key
    return true unless api_key_request?

    key = ApiKey.authenticate(authenticate_with_http_token { |token, _options| token })
    return render_api_error(:unauthorized, t("api.errors.invalid_key")) if key.nil?

    @current_api_key = key
  end

  # Mandatory authentication. Renders an error & returns false when the
  # request can't proceed. Returning false from a before_action doesn't
  # halt the chain, but rendering does.
  #
  # @param [Class] for_model - the model the caller needs access to
  # @param [String] action - "read" or "write"
  def require_api_key!(for_model:, action: "read")
    presented = authenticate_with_http_token { |token, _options| token }
    return render_api_error(:unauthorized, t("api.errors.missing_key")) if presented.blank?

    key = ApiKey.authenticate(presented)
    return render_api_error(:unauthorized, t("api.errors.invalid_key")) if key.nil?

    unless key.permits?(action, for_model)
      return render_api_error(
        :forbidden,
        t("api.errors.insufficient_permissions",
          permission: "#{action}:#{BackupBrain::ModelPaths.path_string(for_model)}")
      )
    end

    @current_api_key = key
  end

  # Writes accept either an api key or a signed in user, so the same
  # endpoint serves the web UI and api clients.
  def authenticate_user_or_api_key!(for_model:, action: "write")
    # a raw request from a browserless client has no session to fall back
    # on, so tell it what's missing instead of handing it Devise's html
    if api_key_request? || (raw_format? && !user_signed_in?)
      return require_api_key!(for_model: for_model, action: action)
    end
    authenticate_user!
  end

  # @param [Class] klass - the model being read
  def api_key_can_read?(klass)
    current_api_key.present? && current_api_key.permits?("read", klass)
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
