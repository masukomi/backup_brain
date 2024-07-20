# lib/html_importer.rb
require "nokogiri"
require_relative "html_bookmark_reader"

module BackupBrain
  class HtmlImporter < BackupBrain::UploadImporter
    def self.import(html:, user:, create: true, tags: [])
      raw_xml = get_text(html)
      HtmlImporter.new(html: raw_xml, user: user, create: create, tags: tags).process
    end

    def initialize(html:, user:, create: true, tags: [])
      raise ArgumentError.new("html must be a string.") unless html.is_a? String
      @html   = html
      @user   = user
      @create = create
      @tags   = tags
    end

    def process
      HtmlBookmarkReader.new(
        html: @html,
        user: @user,
        create: @create,
        tags: @tags
      ).to_a
    end
  end
end
