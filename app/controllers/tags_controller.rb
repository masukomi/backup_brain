class TagsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_tag, only: %i[show edit update destroy]

  # GET /tags or /tags.json
  def index
    @starting_with = params[:starting_with]
    @tags = Tag.order([:name, :asc])
    # get all possible first chars
    @tags_first_characters = @tags.map { |t| t.name[0] }.uniq
    # then narrow it down to what was requested (if anything)
    if @starting_with
      regexp_char = /\w/.match?(@starting_with) ? @starting_with : "\\#{@starting_with}"
      @tags = @tags.where(name: /^#{regexp_char}/)
    end
  end

  # GET /tags/1 or /tags/1.json
  def show
  end

  # No direct creation of tags
  def new
    redirect_to tags_url
  end
  # NOTE: More security could be added,
  # but there's not really a point.
  # You can't see ANY of these endpoints if you're
  # not logged in, and if you really want to
  # create a tag that nothing uses,
  # or muck with the value of an existing one,
  # well… it's YOUR instance. You won't hurt
  # anyone else & you probably won't hurt your
  # data.

  # GET /tags/1/edit
  def edit
  end

  # POST /tags or /tags.json
  def create
    redirect_to tags_url
  end

  # PATCH/PUT /tags/1 or /tags/1.json
  def update
    downcased = tag_params[:name].downcase
    respond_to do |format|
      if @tag.name == downcased || @tag.rename!(downcased)
        # renaming can result in deletion
        # because renaming it to match an existing one deletes the
        # one that got rename.
        if Tag.where(id: @tag.id).count > 0
          flash_message(:notice, I18n.t("tags.update_success"))
        else
          flash_message(:notice, I18n.t("tags.rename_deletion"))
        end
        format.html { redirect_to tags_url }
        format.json { render :show, status: :ok, location: @tag }
      else
        format.html { redirect_to tags_url(@tag) }
        format.json { render json: @tag.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /tags/1 or /tags/1.json
  def destroy
    @tag.destroy

    respond_to do |format|
      format.html { redirect_to tags_url, notice: I18n.t("deletion_success") }
      format.json { head :no_content }
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_tag
    @tag = Tag.find(params[:id])
  end

  # Only allow a list of trusted parameters through.
  def tag_params
    params.require(:tag).permit(:name)
  end
end
