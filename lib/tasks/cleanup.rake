require "paint"
require "whirly"

namespace :cleanup do
  # defaults to true if response code is ambiguous
  def url_potentially_good?(url_string)
    code = HTTParty.head(url_string,
      verify: false,
      timeout: 5,
      # tell it we're chrome. Yes, this is a real chrome user agent string.
      headers: {"User-Agent" => "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/104.0.5112.79 Safari/537.36"}).response.code.to_i
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
  rescue Net::ReadTimeout, Errno::ETIMEDOUT
    true # ... maybe?
  rescue
    false
  end

  desc "Destroy useless bookmarks"
  task destroy_useless_bookmarks: [:environment] do
    unarchived = Bookmark.where(:archives.exists => false)

    counter = 0
    Whirly.configure spinner: "dots"
    Whirly.start do
      unarchived.each do |bookmark|
        unless url_potentially_good?(bookmark.url)
          counter += 1
          # Whirly.status = Paint["destroying: #{bookmark.title} @ #{bookmark.url}", :green]
          puts Paint["destroying: #{bookmark.title} @ #{bookmark.url}", :yellow]
          #  code = HTTParty.head(bookmark.url).response.code.to_i
          bookmark.destroy
        end
      end
      if counter > 0
        puts "Deleted #{counter} useless bookmarks. So sad. 😭"
      else
        puts "Wow. No useless URLs found! Amazing!"
      end
    end
  end
end
