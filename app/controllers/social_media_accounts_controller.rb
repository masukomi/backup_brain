class SocialMediaAccountsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_person

  def new
    @social_media_account = @person.social_media_accounts.build
  end

  def create
    profile_url = sma_params[:profile_url]
    existing    = SocialMediaAccount.where(profile_url: profile_url).first if profile_url.present?

    if existing
      existing.assign_attributes(sma_params.except(:profile_url))
      existing.person = @person
      @social_media_account = existing
    else
      @social_media_account = @person.social_media_accounts.build(sma_params)
      if @person.social_media_accounts.size == 1
        @social_media_account.preferred = true
        # if the new one is the only one it's going to be the preferred one.
      end
      if @social_media_account.profile_url
        @social_media_account.service = SocialMediaAccount.query_service_type(@social_media_account.profile_url)
        # if there isn't one the .save will fail and list any other errors
      end
    end

    if @social_media_account.save
      if SocialMediaAccount.supported_service?(@social_media_account.service)
        flash_message(:notice, t("social_media_accounts.creation_success_supported"))
      else
        flash_message(:notice, t("social_media_accounts.creation_success_unsupported"))
      end
      redirect_to @person
    else
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    @social_media_account = @person.social_media_accounts.find(params[:id])
    @social_media_account.destroy
    flash_message(:notice, t("social_media_accounts.deletion_success"))
    redirect_to @person, status: :see_other
  end

  private

  def set_person
    @person = Person.find(params[:person_id])
  end

  def sma_params
    params.require(:social_media_account).permit(:profile_url, :preferred, :type)
  end
end
