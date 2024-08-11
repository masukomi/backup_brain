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

    file_data = params[:uploaded_file]&.tempfile&.read

    # I don't think nil is possible, but just in case...
    if file_data.nil? || file_data == ""
      flash_message(:error, t("importer.no_file_error"))
      redirect_to action: "index"
    else
      unless file_matches_flavor?
        flash_message(:error, t("importer.file_flavor_error",
          filename: params[:uploaded_file].original_filename))
        redirect_to action: "index"
        return
      end

      begin
        tags = Tag.split_tags(params[:tags] || "")
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

  private

  def file_matches_flavor?
    filename              = params[:uploaded_file]&.original_filename
    flavor                = params[:file_flavor]
    return false unless filename || flavor

    content_type = params[:uploaded_file]&.content_type

    extension             = File.extname(filename).downcase
    return true if flavor == "html" && (%w[.html .htm].include?(extension) \
                                        || content_type == "text/html")
    return true if flavor == "json" && (%w[.json .js].include?(extension) \
                                        || content_type == "application/json")
    false
  end
end
