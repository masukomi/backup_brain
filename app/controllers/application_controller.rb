class ApplicationController < ActionController::Base
  include Pagy::Backend
  VALID_ALTERNATE_LAYOUTS = %w[webextension]

  before action :set_layout

  protected

  def set_layout
    if params[:layout].present? && VALID_ALTERNATE_LAYOUTS.include?(params[:layout])
      layout params[:layout]
    end
  end
end
