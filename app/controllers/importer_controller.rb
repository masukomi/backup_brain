class ImporterController < ApplicationController
  before_action :authenticate_user!

  def index
  end

  def import
    if params[:uploaded_file].nil?
      flash_message(:error, t("importer.no_file_error"))
      redirect_to action: "index"
      return
    end
    if params[:file_flavor].blank?
      flash_message(:error, t("importer.choose_file_flavor_error"))
      redirect_to action: "index"
      return
    end

    begin
      file_data = params[:uploaded_file].tempfile.read
    rescue => e
      flash_message(:error, t("importer.unreadable_file_error", error: e.message))
      redirect_to action: "index"
      return
    end

    # I don't think nil is possible, but just in case...
    if file_data.nil? || file_data == ""
      flash_message(:error, t("importer.no_file_error"))
      redirect_to action: "index"
    else
      begin
        tags = Bookmark.split_tags(params[:tags]&.strip || "")
        bookmarks = if params[:file_flavor] == "html"
          BackupBrain::HtmlImporter.import(
            html: file_data,
            user: current_user,
            create: true,
            tags: tags
          )
        else
          BackupBrain::PinboardImporter.import(
            json: file_data,
            user: current_user,
            # create: true,
            create: false,
            tags: tags
          )
        end
        flash_message(:notice, t("importer.success_message", count: bookmarks.size))
        redirect_to bookmarks_path
      rescue => e
        flash_message(:error, e.message)
        redirect_to action: "index"
      end
    end
  end
end
