class PrivacyController < ApplicationController
  before_action :authenticate_user!

  def hide_private
    cookies[:hide_private] = {value: "true", httponly: true}
    redirect_back fallback_location: root_path
  end

  def show_private
    cookies.delete(:hide_private)
    redirect_back fallback_location: root_path
  end
end
