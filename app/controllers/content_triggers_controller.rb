class ContentTriggersController < ApplicationController
  before_action :authenticate_user!
  before_action :set_content_trigger, only: %i[edit update destroy]

  def index
    @content_triggers = ContentTrigger.all.order_by(name: :asc)
  end

  def new
    @content_trigger = ContentTrigger.new
  end

  def edit
  end

  def create
    @content_trigger = ContentTrigger.new(split_params)
    if @content_trigger.save
      flash_message(:notice, t("content_triggers.creation_success"))
      redirect_to content_triggers_path
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @content_trigger.update(split_params)
      flash_message(:notice, t("content_triggers.update_success"))
      redirect_to content_triggers_path
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @content_trigger.destroy
    flash_message(:notice, t("content_triggers.deletion_success"))
    redirect_to content_triggers_path, status: :see_other
  end

  private

  def set_content_trigger
    @content_trigger = ContentTrigger.find(params[:id])
  end

  def content_trigger_params
    params.require(:content_trigger).permit(
      :name, :simple_triggers, :case_insensitive,
      :mark_as_private, :mark_as_sensitive, :mark_to_read
    )
  end

  def split_params
    tags = params.dig(:content_trigger, :tags).to_s.split.uniq
    simple_triggers = params.dig(:content_trigger, :simple_triggers)
      .to_s.split(/,\s+/).map(&:strip).compact_blank.uniq
    content_trigger_params.merge(tags: tags, simple_triggers: simple_triggers)
  end
end
