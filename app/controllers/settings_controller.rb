class SettingsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_admin_enabled
  before_action :set_setting, only: %i[show edit update destroy]

  # GET /settings or /settings.json
  def index
    @settings = if !@setting_administration_enabled
      Setting.where(visible: true).order([:lookup_key, :asc])
    else
      Setting.order([:lookup_key, :asc])
    end
  end

  # GET /settings/1 or /settings/1.json
  def show
  end

  # NOTE: More security could be added,
  # but there's not really a point.
  # You can't see ANY of these endpoints if you're
  # not logged in, and if you really want to
  # create a setting that nothing uses,
  # or muck with the value of an existing one,
  # well… it's YOUR instance. You won't hurt
  # anyone else & you probably won't hurt your
  # data.

  # GET /settings/new
  def new
    @setting = Setting.new(value: {value: nil})
  end

  # GET /settings/1/edit
  def edit
  end

  # PATCH/PUT /settings/1 or /settings/1.json
  def update
    cleaned_params = clean_params(@setting, setting_params)
    respond_to do |format|
      if @setting.update(cleaned_params)
        flash_message(:notice, I18n.t("settings.update_success"))
        format.html { redirect_to settings_url }
        format.json { render :show, status: :ok, location: @setting }
      else
        @setting.errors.each do |error|
          flash_message(:error, I18n.t("settings.errors.validation_error", attribute: error.attribute, problem: error.type))
        end
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @setting.errors, status: :unprocessable_entity }
      end
    rescue JSON::ParserError
      flash_message(:error, I18n.t("settings.errors.invalid_json"))
      format.html { redirect_to edit_setting_url(@setting) }
      format.json { render json: @setting.errors, status: :unprocessable_entity }
    end
  end

  # DELETE /settings/1 or /settings/1.json
  def destroy
    @setting.destroy

    respond_to do |format|
      format.html { redirect_to settings_url, notice: I18n.t("deletion_success") }
      format.json { head :no_content }
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_setting
    @setting = Setting.find(params[:id])
  end

  # Only allow a list of trusted parameters through.
  def setting_params
    params.require(:setting).permit(:lookup_key, :summary, :description, :value, :value_type)
  end

  def clean_params(setting, params_hash)
    # # first the value type
    value_type = params_hash[:value_type]
    params_hash[:value_type] = value_type.present? ? value_type.to_sym : setting.value_type

    # and then the value
    raw_value = params_hash[:value]
    params_hash[:value] = if raw_value.is_a?(ActionController::Parameters)
      raw_value.to_unsafe_h.transform_keys(&:to_sym)
    elsif raw_value.to_s.strip.present?
      {value: JSON.parse(raw_value.to_s.strip)}
    else
      {value: nil}
    end
    params_hash
    # symbolified = {}
    # params_hash.each do | key, val|
    #   symbolified[key.to_sym] = val
    # end
    # symbolified
  end

  # 🤫 Sssshhhh is secret 1337 k0ntrol! No tell secret!
  def set_admin_enabled
    false # FIXME fix handling of value_type before removing this
    # @setting_administration_enabled = ENV.fetch("ENABLE_SETTINGS_ADMINISTRATION", "false") == "true"
  end
end
