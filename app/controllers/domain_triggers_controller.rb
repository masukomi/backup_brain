class DomainTriggersController < ApplicationController
  before_action :authenticate_user!
  before_action :set_domain_trigger, only: %i[edit update destroy]

  def index
    @domain_triggers = DomainTrigger.all.order_by(domain: :asc)
  end

  def new
    @domain_trigger = DomainTrigger.new
  end

  def edit
  end

  def create
    @domain_trigger = DomainTrigger.new(split_tag_params)
    if @domain_trigger.save
      flash_message(:notice, t("domain_triggers.creation_success"))
      redirect_to domain_triggers_path
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @domain_trigger.update(split_tag_params)
      flash_message(:notice, t("domain_triggers.update_success"))
      redirect_to domain_triggers_path
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @domain_trigger.destroy
    flash_message(:notice, t("domain_triggers.deletion_success"))
    redirect_to domain_triggers_path, status: :see_other
  end

  private

  def set_domain_trigger
    @domain_trigger = DomainTrigger.find(params[:id])
  end

  def domain_trigger_params
    params.require(:domain_trigger).permit(:domain, :mark_as_private, :mark_as_sensitive, :mark_to_read)
  end

  def split_tag_params
    tags = params.dig(:domain_trigger, :tags).to_s.split.uniq
    domain_trigger_params.merge(tags: tags)
  end
end
