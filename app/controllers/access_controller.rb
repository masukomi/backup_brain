class AccessController < ApplicationController
  before_action :authenticate_user!
  before_action :set_secret_key, only: [:show_secret_key, :destroy_secret_key, :rename_secret_key, :rename_secret_key_form]
  before_action :set_api_key,    only: [:destroy_api_key,    :rename_api_key,    :rename_api_key_form]

  def index
    @secret_keys = SecretKey.all.order_by(name: :asc)
    @api_keys    = ApiKey.all.order_by(name: :asc)
  end

  def new_secret_key
    @secret_key = SecretKey.new
  end

  def create_secret_key
    @secret_key = SecretKey.new(secret_key_params)
    if @secret_key.save
      flash_message(:notice, t("access.secret_keys.creation_success"))
      redirect_to show_secret_key_path(@secret_key)
    else
      render :new_secret_key, status: :unprocessable_entity
    end
  end

  def show_secret_key
    # @secret_key set by before_action
  end

  def destroy_secret_key
    @secret_key.destroy
    flash_message(:notice, t("access.secret_keys.deletion_success"))
    redirect_to access_path, status: :see_other
  end

  def rename_secret_key_form
    # renders rename_secret_key.html.erb
  end

  def rename_secret_key
    if @secret_key.update(secret_key_rename_params)
      flash_message(:notice, t("access.secret_keys.rename_success"))
      redirect_to access_path
    else
      render :rename_secret_key, status: :unprocessable_entity
    end
  end

  def new_api_key
    @api_key = ApiKey.new
  end

  def create_api_key
    @api_key = ApiKey.new(api_key_params)
    if @api_key.save
      @new_key_value = @api_key.key
      flash_message(:notice, t("access.api_keys.creation_success"))
      render :create_api_key_success
    else
      render :new_api_key, status: :unprocessable_entity
    end
  end

  def destroy_api_key
    @api_key.destroy
    flash_message(:notice, t("access.api_keys.deletion_success"))
    redirect_to access_path, status: :see_other
  end

  def rename_api_key_form
    # renders rename_api_key.html.erb
  end

  def rename_api_key
    if @api_key.update(api_key_rename_params)
      flash_message(:notice, t("access.api_keys.rename_success"))
      redirect_to access_path
    else
      render :rename_api_key, status: :unprocessable_entity
    end
  end

  private

  def set_secret_key
    @secret_key = SecretKey.find(params[:id])
  end

  def set_api_key
    @api_key = ApiKey.find(params[:id])
  end

  def secret_key_params
    params.require(:secret_key).permit(:name, permissions: [])
  end

  def secret_key_rename_params
    params.require(:secret_key).permit(:name)
  end

  def api_key_params
    params.require(:api_key).permit(:name, :expiration_date, permissions: [])
  end

  def api_key_rename_params
    params.require(:api_key).permit(:name)
  end
end
