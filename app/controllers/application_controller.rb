class ApplicationController < ActionController::Base
  include Pagy::Backend
  VALID_ALTERNATE_LAYOUTS = %w[application webextension]
  layout :get_layout

  before_action :set_layout

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
end
