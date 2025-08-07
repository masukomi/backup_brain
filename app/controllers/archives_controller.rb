#!/usr/bin/env ruby
class ArchivesController < ApplicationController
  before_action :authenticate_user!, only: %i[show]
  before_action :set_object, only: %i[show]
  before_action :set_object_type, only: %i[show]
  def show
    filename = sanitize_path_component(params[:filename])
    format = params[:format].gsub(/[^a-zA-Z0-9]/, "")
    path = "archives/#{@object_type}/#{@object._id}/#{filename}.#{format}"
    raise ActionController::MissingFile.new("File Not Found") unless File.exist?(path)
    send_file path, disposition: "inline"
  end

  # --- helpers
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
