class FailedArchiveAttempt
  include Mongoid::Document
  include Mongoid::Timestamps
  field :status_code, type: Integer
  embedded_in :bookmark

  def link_details
    if status_code.is_a?(Integer) && status_code < 600
      {
        status_code: status_code,
        url: "https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/#{status_code}",
        title: I18n.t("bookmarks.error_code_link", code: status_code)
      }
    elsif status_code
      {
        status_code: status_code,
        url: nil,
        title: I18n.t("errors.archives.custom_code_#{status_code}")
      }
    else
      {
        status_code: "???",
        url: nil,
        title: I18n.t("errors.archives.custom_code_unknown")
      }
    end
  end
end
