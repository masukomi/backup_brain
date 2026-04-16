require "uri"
require "tempfile"
require "open3"
require "digest"

class ArchiveSocialMediaAccountJob < ArchiveUrlJob
  MAX_THREAD_COUNT = 10

  queue_as :low_priority # :default

  # @param social_media_account_id [String|NilClass|BSON::ObjectId::Mongoid::Criteria]
  #        Pass in a single social_media_account id to archive images for just that social media account,
  #        or NilClass to archive images on all social_media_accounts that don't already have archived images.
  # @param replace_archived_images [TrueClass|FalseClass]
  #        if false this will not attempt to replace
  #        previously archived images. If true it will attempt
  #        to get the latest version.
  # @param replace_description [TrueClass|FalseClass]
  #        if false this will not attempt to replace
  #        contents of the description field. If true it will attempt
  #        to get the latest version from the account's profile
  def perform(social_media_account_id:, replace_archived_images: true, replace_description: true, avatar_url: nil, header_url: nil)
    process_social_media_account(
      social_media_account_id: social_media_account_id,
      replace_archived_images: replace_archived_images,
      replace_description: replace_description,
      avatar_url: avatar_url,
      header_url: header_url
    )
  end

  # @return [Bookmark, nil] the bookmark if it was archived, nil if it wasn't
  def process_social_media_account(social_media_account_id:,
    replace_archived_images: true,
    replace_description: true,
    replace_username: true,
    avatar_url: nil,
    header_url: nil)
    sma = begin
      SocialMediaAccount.find(social_media_account_id)
    rescue
      Rails.logger.info("Unable to find SocialMediaAccount with id: \"#{social_media_account_id}\"")
      nil
    end
    return false unless sma
    if !SocialMediaAccount.supported_service?(sma.service)
      Rails.logger.info("SocialMediaAccount with id: \"#{social_media_account_id}\" has unsupported service: #{sma.service}")
      # leave it to the user to populate it themself
      return false
    end

    begin
      if sma.username.blank? || replace_username
        Rails.logger.debug("replacing username with remote username")
        sma.description = sma.remote_username
      end
      if sma.description.blank? || replace_description
        Rails.logger.debug("replacing description with remote description")
        sma.description = sma.remote_description
      end
      if sma.avatar_image_path.blank? || replace_archived_images
        url = avatar_url.presence || sma.avatar_image_url
        Rails.logger.debug("Attempting to download avatar image with url: \"#{url}\"")
        if url.present?
          sma.avatar_image_path = download_asset(
            sma,
            url,
            asset_label: "avatar image",
            to_path: sma.default_avatar_image_path
          )
        end
      end
      if sma.header_image_path.blank? || replace_archived_images
        url = header_url.presence || sma.header_image_url
        Rails.logger.debug("Attempting to download header image with url: \"#{url}\"")
        if url.present?
          sma.header_image_path = download_asset(
            sma,
            url,
            asset_label: "header image",
            to_path: sma.default_header_image_path
          )
        end
      end
      if sma.preferred &&
          sma.avatar_image_path &&
          sma.person.present? &&
          (sma.person.avatar_image_path != sma.avatar_image_path)

        # overwrite that crap with our hotness!
        sma.person.avatar_image_path = sma.avatar_image_path
        sma.person.save
      end
      Rails.logger.debug("SocialMediaAccount.changed? #{sma.changed?}")
      sma.save if sma.changed?
    rescue BackupBrain::Errors::UnarchivableUrl => e
      Rails.logger.error(e.message)
      begin
        tempfile.close
      rescue
        nil
      end
      nil
    end
  rescue Net::ReadTimeout, Net::OpenTimeout, Errno::ETIMEDOUT
    # 599 Network Connect Timeout Error
    record_failed_attempt(sma, 599, should_raise: false)
  rescue => e
    Rails.logger.warn("couldn't update / archive Social Media info from #{sma.profile_url} - #{e.message}")

    nil
  end
end
