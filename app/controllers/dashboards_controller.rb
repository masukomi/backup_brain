class DashboardsController < ApplicationController
  # ⚠ WARNING TO FUTUTRE HACKERS
  # The user privacy stuff in here is based on the idea that
  # there will only be one user.
  # It is guaranteed to expose private data if
  # you allow multiple accounts to be created.
  # Don't do that. This is a single-user instance.

  before_action :authenticate_user!, only: %i[dailies]

  def dailies
    # TODO pick a better default
    @since = params[:since].blank? ? 1 : params[:since].to_i
    @until = params[:until].blank? ? 0 : params[:until].to_i
    @until_date = @until.weeks.ago.end_of_week
    @since_date = @since.weeks.ago.beginning_of_week
    query_params = {
      :created_at.gte => @since_date,
      :created_at.lte => @until_date
    }

    if cookies[:hide_private].present?
      query_params.merge!({private: false})
      @grouped_people = {}
    else
      @grouped_people = Person.where(query_params).to_a.group_by_day { |b| b.created_at }
    end

    @grouped_bookmarks = Bookmark
      .where(query_params)
      .to_a
      .group_by_day { |b| b.created_at }

    @grouped_notes = Note
      .where(query_params)
      .to_a
      .group_by_day { |b| b.created_at }

    @grouped_dailies = merge_groupings(
      [@grouped_bookmarks, @grouped_notes, @grouped_people],
      custom_sort: ->(a, b) {
        a.send(:created_at) <=> b.send(:created_at)
      }
    ).sort.to_h
  end
end
