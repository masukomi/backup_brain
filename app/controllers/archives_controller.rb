#!/usr/bin/env ruby
class ArchivesController < ApplicationController
  before_action :authenticate_user!, only: %i[show edit modify]
  before_action :set_object_and_parent, only: %i[edit modify]
  before_action :set_object, only: %i[show]
  before_action :set_object_type, only: %i[show edit]

  def show
    filename = sanitize_path_component(params[:filename])
    format = params[:format].gsub(/[^a-zA-Z0-9]/, "")
    path = "archives/#{@object_type}/#{@object._id}/#{filename}.#{format}"
    raise ActionController::MissingFile.new("File Not Found") unless File.exist?(path)
    send_file path, disposition: "inline"
  end

  def edit
    @lines_of_text = @object.string_data.split("\n").size
  end

  def modify
    # NOTE: this'll need to be updated when
    # we support new archive types
    archive = Archive.new(bookmark: @parent, mime_type: "text/markdown")
    archive.string_data = params[:string_data]
    archive.manually_edited = true
    archive.transcription_ids = @object.transcription_ids.dup
    # @parent.archives << archive

    respond_to do |format|
      if archive.save
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

    @object = Bookmark.find(sanitize_path_component(params[:id]))
    if @object.private? && !user_signed_in?
      @object = nil
      raise ActionController::MissingFile "File Not Found"
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
    string.gsub(/[^a-zA-Z0-9]/, "")
  end
end
