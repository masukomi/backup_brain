# lib/pinboard_importer.rb

module BackupBrain
  class PinboardImporter < BackupBrain::UploadImporter
    extend BackupBrain::ArchiveTools
    def self.import(json:, user:, create: true, tags: [])
      raw_json = get_text(json)
      PinboardImporter.new(json: raw_json, user: user, create: create, tags: tags).process
    end

    def initialize(json:, user:, create: true, tags: [])
      @json   = json.is_a?(String) ? JSON.parse(json) : json
      @user   = user
      @create = create
      @tags   = tags
    end

    def process
      bookmarks = []
      @json.each do |bookmark_data|
        # existing_bookmark = Bookmark.where(url: bookmark_data["href"]).first
        # if existing_bookmark.nil?
        next if Bookmark.where(url: bookmark_data["href"]).count > 0
        unless PinboardImporter.url_potentially_good?(bookmark_data["href"])
          Rails.logger.info("skipping import of #{bookmark_data["href"]}")
          next
        end
        (Tag.split_tags(bookmark_data["tags"]) + @tags)
          .uniq
          .map { |t| t.strip.downcase.gsub(/\s+/, "_") }
        params = {
          url: bookmark_data["href"],
          title: bookmark_data["description"],
          description: bookmark_data["extended"],
          created_at: bookmark_data["time"],
          private: bookmark_data["shared"] != "yes",
          to_read: bookmark_data["toread"] == "yes",
          tags:
        }
        bookmarks << if @create
          Bookmark.create(params)
        else
          Bookmark.new(params)
        end
        # else
        #   existing_bookmark.update(
        #     title:       bookmark_data["description"],
        #     description: bookmark_data["extended"],
        #     created_at:  bookmark_data["time"],
        #     private:     bookmark_data["shared"] != "yes",
        #     to_read:     bookmark_data["toread"] == "yes",
        #     tags:        Tag.split_tags(bookmark_data["tags"]) + @tags
        #   )

        #   bookmarks << existing_bookmark
        # end
      end
      bookmarks
    rescue => e
      Rails.logger.info("#{e.message} when importing #{bookmark_data["href"]}")
      raise e
    end
  end
end
