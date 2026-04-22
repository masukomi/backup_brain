class AdministrationController < ApplicationController
  before_action :authenticate_user!

  def index
  end

  def themes
    @theme_names   = Setting.get_value_of_key("theme_names") || ["default"]
    @current_theme = cookies[:bb_theme].presence || "default"
  end

  def set_theme
    allowed = Setting.get_value_of_key("theme_names") || ["default"]
    theme   = params[:theme]
    if allowed.include?(theme)
      cookies[:bb_theme] = {value: theme, httponly: true}
    end
    redirect_to administration_themes_path
  end
end
