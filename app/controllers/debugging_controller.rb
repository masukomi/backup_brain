class DebuggingController < ApplicationController
  def echo
    render json: params
  end
end
