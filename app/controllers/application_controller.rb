class ApplicationController < ActionController::Base
  include Pagy::Backend
  VALID_ALTERNATE_LAYOUTS = %w[application webextension]
  layout :get_layout

  before_action :set_layout
  before_action :set_user_count
  before_action :configure_permitted_devise_params, if: :devise_controller?

  def flash_message(type, text)
    generic_flash_message(flash, type, text)
  end

  def inline_flash_message(type, text)
    generic_flash_message((@inline_flash ||= {}), type, text)
  end

  protected

  def generic_flash_message(hash, type, text)
    hash[type] ||= []
    if text.present? && hash[type].exclude?(text)
      # was accidentally getting duplicate hash messages
      hash[type] << text
    end
  end

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
