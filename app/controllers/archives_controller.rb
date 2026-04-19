#!/usr/bin/env ruby
class ArchivesController < ApplicationController
  before_action :authenticate_user!, only: %i[edit modify new create]
  before_action :require_show_access, only: %i[show]
  before_action :set_object_and_parent, only: %i[edit modify]
  before_action :set_object_type, only: %i[show edit new create]
  before_action :set_object, only: %i[show]

  def show
    filename = sanitize_path_component(params[:filename])
    format = params[:format].gsub(/[^a-zA-Z0-9]/, "")
    path = if !params[:grouping]
      "archives/#{@object_type}/#{@object._id}/#{filename}.#{format}"
    else
      "archives/#{@object_type}/#{@object._id}/#{params[:grouping]}/#{filename}.#{format}"
    end
    raise ActionController::MissingFile.new("File Not Found") unless File.exist?(path)
    send_file path, disposition: "inline"
  end

  def new
    set_parent_only
    @object = Archive.new
    @lines_of_text = 10
  end

  def edit
    @lines_of_text = @object.string_data.split("\n").size
  end

  def create
    set_parent_only
    @object = Archive.new(
      string_data: params[:string_data],
      mime_type: "text/markdown",
      manually_edited: true
    )
    @parent.archives << @object
    ContentTrigger.apply_triggers(test_string: @object.string_data, apply_to: @parent) if @object.string_data.present?
    if @parent.save
      flash_message(:notice, t("archives.notices.creation_success"))
      redirect_to bookmark_path(@parent)
    else
      @lines_of_text = 10
      render :new, status: :unprocessable_entity
    end
  end

  def modify
    # NOTE: this'll need to be updated when
    # we support new archive types
    archive = Archive.new(bookmark: @parent, mime_type: "text/markdown")
    archive.string_data = params[:string_data]
    archive.manually_edited = true
    @object.media_objects.each do |mo|
      archive.media_objects << mo.dup
    end
    # @parent.archives << archive

    respond_to do |format|
      if archive.save
        ContentTrigger.apply_triggers(test_string: archive.string_data, apply_to: @parent) if archive.string_data.present?
        @parent.save
        format.html {
          flash_message(:notice, t("archives.notices.creation_success"))
          # NOTE: this needs to be updated when
          # we support new archive types
          redirect_to bookmark_path(@parent)
        }
      else
        format.html { render :new, status: :unprocessable_entity }
      end
    end
  end

  protected

  # --- helpers

  def require_show_access
    return if user_signed_in?
    return if SecretKey.is_valid?(params[:secret_key])
    authenticate_user!
  end

  def set_parent_only
    @parent = Bookmark.find(sanitize_path_component(params[:parent_id]))
  end

  # This only gets called when editing / modifying Bookmark Archives
  def set_object_and_parent
    @parent = Bookmark.find(sanitize_path_component(params[:parent_id]))
    @object = @parent.archives.select { |a| a.id.to_s == params[:id] }.first
    if @object.nil? || (@parent.private? && !user_signed_in?)
      @object = nil
      raise ActionController::MissingFile "File Not Found"
    end
  end

  def set_object
    # someday this'll support more than just bookmarks

    if @object_type == "bookmarks"
      @object = Bookmark.find(sanitize_path_component(params[:id]))
      if @object.private? && !user_signed_in? && !SecretKey.is_valid?(params[:secret_key])
        @object = nil
        raise ActionController::MissingFile "File Not Found"
      end
    elsif @object_type == "people"
      if !user_signed_in?
        @object = nil
        raise ActionController::MissingFile "File Not Found"
      end
      # this may also raise a 404? I think
      @object = Person.find(sanitize_path_component(params[:id]))
    elsif @object_type == "social_media_accounts"
      @object = SocialMediaAccount.find(sanitize_path_component(params[:id]))
    else
      raise "Unsupported Object Type ( #{@object_type.inspect} ) in Archive Path"
    end
  end

  def set_object_type
    @object_type =
      sanitize_path_component(params[:object_type] || "bookmarks")
  end

  # our path components are either
  # - mongoid ids
  # - sha256 hex hashes
  # so only ascii letters and numbers
  def sanitize_path_component(string)
    return "" if string.blank?
    string.gsub(/[^a-zA-Z0-9_]/, "")
  end
end
