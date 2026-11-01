class S3BucketsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_s3_bucket, only: %i[edit update destroy]

  def index
    @s3_buckets = S3Bucket.all.order_by(primary: :desc, nickname: :asc)
  end

  def new
    @s3_bucket = S3Bucket.new
  end

  def edit
  end

  def create
    @s3_bucket = S3Bucket.new(s3_bucket_params)
    if @s3_bucket.save
      flash_message(:notice, t("s3_buckets.creation_success"))
      redirect_to s3_buckets_path
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @s3_bucket.update(update_params)
      flash_message(:notice, t("s3_buckets.update_success"))
      redirect_to s3_buckets_path
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @s3_bucket.destroy
    flash_message(:notice, t("s3_buckets.deletion_success"))
    redirect_to s3_buckets_path, status: :see_other
  end

  private

  def set_s3_bucket
    @s3_bucket = S3Bucket.find(params[:id])
  end

  def s3_bucket_params
    params.require(:s3_bucket).permit(
      :nickname, :enabled, :primary, :endpoint, :region, :name,
      :access_key_id, :secret_access_key, :key_prefix,
      :presigned_url_expiry, :path_style_urls
    )
  end

  # The edit form never shows the stored secret, so a blank secret on
  # update means "keep the one you have".
  def update_params
    permitted = s3_bucket_params
    permitted.delete(:secret_access_key) if permitted[:secret_access_key].blank?
    permitted
  end
end
