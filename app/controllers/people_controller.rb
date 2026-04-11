class PeopleController < ApplicationController
  before_action :authenticate_user!
  before_action :set_person, only: %i[show edit update destroy]

  def index
    @people = Person.all.order_by(name: :asc)
  end

  def show
  end

  def new
    @person = Person.new
  end

  def edit
  end

  def create
    @person = Person.new(person_params.merge(aliases: split_aliases))
    if @person.save
      flash_message(:notice, t("people.creation_success"))
      redirect_to @person
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @person.update(person_params.merge(aliases: split_aliases))
      flash_message(:notice, t("people.update_success"))
      redirect_to @person
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @person.destroy
    flash_message(:notice, t("people.deletion_success"))
    redirect_to people_path
  end

  private

  def set_person
    @person = Person.find(params[:id])
  end

  def person_params
    params.require(:person).permit(:name, :description, :pronouns, :home_url,
      domains: [])
  end

  def split_aliases
    params.dig(:person, :aliases_string).to_s
      .split(",")
      .map(&:strip)
      .reject(&:empty?)
  end
end
