require "json"
require "paint"
require "whirly"

namespace :importer do
  desc "Import JSON exported bookmarks from Pinboard.in"
  task :pinboard_import, [:path] => :environment do |t, args|
    # Check if the file path is provided
    # If not, print the usage and exit
    if !args[:path]
      puts Paint["Usage: rake importer:pinboard_import[relative/path/to/exported.json]", :red]
      exit
    elsif !File.exist? args[:path]
      puts Paint["⚠ File doesn't exist", :red]
      puts Paint["Usage: rake importer:pinboard_import[relative/path/to/exported.json]", :red]
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

    counter = 0
    Whirly.configure spinner: "dots"
    Whirly.start do
      data_hash.each do |bookmark_data|
        counter += 1

        # Create a new Bookmark object with the data from the hash
        begin
          existing_bookmark = Bookmark.where(url: bookmark_data["href"]).first
          if !existing_bookmark
            Whirly.status = "importing #{sprintf("%7d", counter)}: #{bookmark_data["href"]}"
            Bookmark.create(
              url: bookmark_data["href"],
              title: bookmark_data["description"],
              description: bookmark_data["extended"],
              created_at: bookmark_data["time"],
              private: bookmark_data["shared"] == "yes",
              to_read: bookmark_data["toread"] == "yes",
              tags: bookmark_data["tags"].split(" ")
            )
          else
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
          Whirly.status = "Oh No! Error! #{e.message} from #{bookmark_data["href"]}"
          sleep 2
        end
      end # END data_hash.each
    end # END Whirly.start
  end # END task
end # END namespace
