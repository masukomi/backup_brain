require "nokogiri"
require "date"
# Josh O'Rourke figured out the nice recursive loop &
# folder handling for this
# https://joshorourke.com/2012/06/28/parsing-bookmarks-with-nokogiri/

module BackupBrain
  class HtmlBookmarkReader
    include Enumerable
    extend BackupBrain::ArchiveTools
    def initialize(html:, user:, create: true, tags: [])
      @html   = html
      @create = create
      @user   = user
      @tags   = tags
    end

    def each
      doc  = Nokogiri::HTML(@html)
      node = doc.at_xpath("//html/body")
      traverse(node, "/") { |b| yield b }
    end

    private

    def traverse(node, path, &block)
      anchors = node.search("./dt//a")
      folder_names = node.search("./dt/h3")
      folder_items = node.search("./dl")

      # the &.strip stuff is because i'm paranoid
      # and don't trust other developers ability
      # to read a spec + there isn't actually a spec.
      anchors.each do |anchor|
        url = anchor["href"]&.strip
        next if url.blank?
        # intentionally NOT setting created_at because
        # it results in the new bookmarks being at "random"
        # places in a user's history. It looks as if nothing's been imported.
        # created_at = parse_date(anchor["add_date"])
        # updated at is just going to get overwritten when the archive is added
        # updated_at = parse_date(anchor["last_modified"])
        title = anchor.text&.strip
        title = I18n.t("bookmarks.default_title_for_blank") if title.blank?

        next if Bookmark.where(url: url).count > 0
        unless HtmlBookmarkReader.url_potentially_good?(url)
          Rails.logger.info("skipping import of #{url}")
          next
        end
        params = {
          url: url,
          title: title,
          tags: @tags,
          # created_at: created_at,
          # updated_at: updated_at,
          user: @user
        }
        if @create
          yield Bookmark.create(params)
        else
          yield Bookmark.new(params)
        end
      end

      folder_items.size.times do |i|
        folder_name = folder_names[i]
        folder_item = folder_items[i]
        next_path   = folder_name.nil? ? path : [path, folder_name].join("/")
        traverse(folder_item, next_path, &block)
      end
    end

    def parse_date(maybe_date)
      return nil if maybe_date.blank? || !maybe_date.is_a?(String)
      maybe_date.strip!
      # the default is apparently to use epoch second timestamps
      return Time.zone.at(maybe_date.to_i).to_datetime if /^\d+$/.match?(maybe_date)
      begin
        DateTime.parse(maybe_date)
      rescue
        nil
      end
    rescue
      nil
    end
  end
end
