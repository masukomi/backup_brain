require "rack/mime"
module BackupBrain
  module ArchiveTools
    ARCHIVES_FOLDER = File.join("archives")
    MISSING_IMAGE_IMAGE_URL = ENV.fetch("MISSING_IMAGE_IMAGE_URL", "/images/icons/missing_image_image.svg")
    ARCHIVE_TIMEOUT = ENV.fetch("ARCHIVE_TIMEOUT", "10").to_i

    # @param mongoid_doc [Mongoid::Document]
    # @return [Dir]
    # @note It's anticipated that the root folder will need to be
    #       different for different document types
    def archive_folder_path_for_doc(mongoid_doc)
      doc_type = mongoid_doc.class.name.downcase.pluralize
      File.join(ARCHIVES_FOLDER, doc_type, mongoid_doc._id.to_s)
    end

    def archive_web_path_for_doc(mongoid_doc)
      doc_type = mongoid_doc.class.name.downcase.pluralize
      ["", "archives", doc_type, mongoid_doc._id.to_s].join("/")
    end

    # DOWNLOAD HELPERS

    def url_downloadable?(url_string, include_code: false)
      begin
        code = HTTParty.head(url_string,
          verify: false,
          timeout: ARCHIVE_TIMEOUT,
          headers: BackupBrain::RequestHeaders.instance.headers_for(url_string)).response.code.to_i
      rescue Socket::ResolutionError
        code = 666 # devilish url
      end

      # Some servers (e.g. CDNs with signed URLs) reject HEAD but accept GET.
      # Fall back to a GET probe when HEAD returns 403.
      if code == 403
        begin
          code = HTTParty.get(url_string,
            verify: false,
            timeout: ARCHIVE_TIMEOUT,
            headers: BackupBrain::RequestHeaders.instance.headers_for(url_string)).response.code.to_i
        rescue
          # keep code as 403
        end
      end

      return (include_code ? [false, 0] : false) if code == 0 # can't happen
      return (include_code ? [true, code] : true) if code < 400
      include_code ? [false, code] : false
    end

    def url_potentially_good?(url_string)
      code = HTTParty.head(url_string,
        verify: false,
        timeout: ARCHIVE_TIMEOUT,
        headers: BackupBrain::RequestHeaders.instance.headers_for(url_string)).response.code.to_i
      return false if code == 0 # theoretically can't happen
      return true if code < 400
      return true if code == 599 # network connect timeout error
      return false if code > 500
      # Things that mean the user can probably access it but we can't
      # 401 unauthorized.
      # 402 payment required.
      # 403 forbidden.
      # 403 REALLY should be false, but it's often used for paywalls
      return true if code > 400 && code < 404
      return true if code == 407 # proxy auth required
      return true if code == 418 # i'm a teapot
      return true if code == 429 # too many requests
      return true if code == 498 # invalid token
      return true if code == 450 # blocked by windows parental controls
      return true if code == 451 # unavailable for legal reasons
      false
    rescue Net::ReadTimeout, Net::OpenTimeout, Errno::ETIMEDOUT
      true # ... maybe?
    rescue
      false
    end
  end
end
