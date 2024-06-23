class ApplicationController < ActionController::Base
  include Pagy::Backend
  VALID_ALTERNATE_LAYOUTS = %w[application webextension]
  layout :get_layout

  before_action :set_layout
  before_action :set_user_count
  before_action :configure_permitted_devise_params, if: :devise_controller?

  def flash_message(type, text)
    flash[type] ||= []
    if text.present? && flash[type].exclude?(text)
      # was accidentally getting duplicate flash messages
      flash[type] << text
    end
  end

  protected

  def get_layout
    if params[:layout].present? && VALID_ALTERNATE_LAYOUTS.include?(params[:layout])
      params[:layout]
    else
      "application"
    end
  end

  def set_layout
    @layout = get_layout
  end

  def set_user_count
    @user_count = User.count
  end

  def configure_permitted_devise_params
    devise_parameter_sanitizer.permit(:sign_up, keys: [:username])
  end
end
