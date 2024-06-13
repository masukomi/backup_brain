require "json"
require "paint"
require "whirly"

namespace :importer do
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

  desc "Import JSON exported bookmarks from Pinboard.in"
  task :pinboard_import, [:path, :start_at] => :environment do |t, args|
    # Check if the file path is provided
    # If not, print the usage and exit
    if !args[:path]
      puts Paint["Usage: rake importer:pinboard_import[relative/path/to/exported.json,1]", :red]
      exit
    elsif !File.exist? args[:path]
      puts Paint["⚠ File doesn't exist", :red]
      puts Paint["Usage: rake importer:pinboard_import[relative/path/to/exported.json,1]", :red]
      exit
    end
    file = File.read(args[:path])
    data_hash = JSON.parse(file)
    # data_hash should contain an array of hashes.
    # Each hash should look like this:
    #     {
    #       "href":"https:\/\/vpsdata.shop\/bambulab-x1c\/18",
    #       "description":"optional - the text for the link",
    #       "extended":"optional - the detailed description of the link",
    #       "meta":"4e63d2fb9ab4fc2bd38788a1fadd9815",
    #       "hash":"b02eb5702daea73732b2d99ac441f887",
    #       "time":"2024-06-09T16:43:35Z",
    #       "shared":"yes",
    #       "toread":"no",
    #       "tags":"3dprinting hardware"
    #     }

    counter  = 0
    failures = 0
    updates  = 0
    skipped  = 0
    start_at = args[:start_at].to_i || 1
    puts Paint["Skipping all bookmarks prior to number #{start_at}", :yellow]
    Whirly.configure spinner: "dots"
    Whirly.start do
      data_hash.each do |bookmark_data|
        counter += 1

        next if counter < start_at

        # Create a new Bookmark object with the data from the hash
        begin
          existing_bookmark = Bookmark.where(url: bookmark_data["href"]).first
          if !existing_bookmark
            unless url_potentially_good?(bookmark_data["href"])
              skipped += 1
              Whirly.status = Paint["skipping #{sprintf("%7d", counter)}: #{bookmark_data["href"]}", :yellow]
              next
            end
            Whirly.status = "importing #{sprintf("%7d", counter)}: #{bookmark_data["href"]}"
            Bookmark.create(
              url: bookmark_data["href"],
              title: bookmark_data["description"],
              description: bookmark_data["extended"],
              created_at: bookmark_data["time"],
              private: bookmark_data["shared"] != "yes",
              to_read: bookmark_data["toread"] == "yes",
              tags: bookmark_data["tags"].split(" ")
            )
          else
            updates += 1
            Whirly.status = "updating #{sprintf("%7d", counter)}: #{bookmark_data["href"]}"
            existing_bookmark.update(
              title: bookmark_data["description"],
              description: bookmark_data["extended"],
              created_at: bookmark_data["time"],
              private: bookmark_data["shared"] == "yes",
              to_read: bookmark_data["toread"] == "yes",
              tags: bookmark_data["tags"].split(" ")
            )

          end
        rescue => e
          failures += 1
          Whirly.status = "Oh No! Error! #{e.message} from #{bookmark_data["href"]}"
          sleep 2
        end
      end # END data_hash.each
    end # END Whirly.start
    puts "Successfully imported: #{counter - failures} bookmarks."
    if updates > 0
      puts "Updated #{updates} bookmarks."
    end
    if skipped > 0
      puts "Skipped #{skipped} bookmarks."
    end
    if failures > 0
      puts "BUT, there were also #{failures} errors along the way. 😭"
    end
  end # END task
end # END namespace
