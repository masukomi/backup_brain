module FeedsHelper
  def add_secret_key_to_archive_urls(text, secret_key)
    return text if secret_key.blank?
    text.gsub(%r{(/archives/[^\s\)"'\]]+)}) do |match|
      "#{match}?secret_key=#{CGI.escape(secret_key)}"
    end
  end

  def archive_url_with_secret_key(url, secret_key)
    return url if secret_key.blank? || !url.start_with?("/archives")
    "#{url}?secret_key=#{CGI.escape(secret_key)}"
  end
end
