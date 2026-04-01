class JobsController < ApplicationController
  before_action :authenticate_user!

  # Jobs that can be triggered from the UI, mapped to how they are enqueued.
  # Jobs that require per-record parameters (e.g. ArchiveUrlJob) are excluded.
  MANAGEABLE_JOBS = {
    "FetchMastodonBookmarksJob" => -> { FetchMastodonBookmarksJob.perform_later(reschedulable: true) },
    "ArchiveImagesJob" => -> { ArchiveImagesJob.perform_later(bookmarks: nil) },
    "DeleteOrphanedTagsJob" => -> { DeleteOrphanedTagsJob.schedule_unless_pending }
  }.freeze

  # Jobs visible on the page but not triggerable from the UI (require per-record parameters).
  UNMANAGEABLE_JOBS = %w[ArchiveUrlJob ArchiveUrlWithoutRetriesJob TranscribeAudioJob YouTubeTranscriptionJob].freeze

  def index
    @jobs = MANAGEABLE_JOBS.keys.map do |class_name|
      pending_jobs = Delayed::Backend::Mongoid::Job
        .where(failed_at: nil, handler: /job_class: #{Regexp.escape(class_name)}\n/)
        .order_by(run_at: :asc)
        .to_a
      {class_name: class_name, label: humanize_job_name(class_name), pending_jobs: pending_jobs}
    end

    @unmanageable_jobs = UNMANAGEABLE_JOBS.map do |class_name|
      pending_jobs = Delayed::Backend::Mongoid::Job
        .where(failed_at: nil, handler: /job_class: #{Regexp.escape(class_name)}\n/)
        .order_by(run_at: :asc)
        .to_a
      {class_name: class_name, label: humanize_job_name(class_name), pending_jobs: pending_jobs}
    end
  end

  def run
    class_name = params[:job_class]
    enqueue_proc = MANAGEABLE_JOBS[class_name]
    raise ActionController::RoutingError, "Unknown job" unless enqueue_proc

    enqueue_proc.call
    redirect_to jobs_path, notice: t("jobs.enqueued", name: humanize_job_name(class_name))
  end

  def unschedule_job
    class_name = params[:job_class]
    raise ActionController::RoutingError, "Unknown job" unless MANAGEABLE_JOBS.key?(class_name) || UNMANAGEABLE_JOBS.include?(class_name)

    Delayed::Backend::Mongoid::Job
      .where(failed_at: nil, handler: /job_class: #{Regexp.escape(class_name)}\n/)
      .destroy_all
    redirect_to jobs_path, notice: t("jobs.unscheduled", name: humanize_job_name(class_name))
  end

  def abort_job
    delayed_job = Delayed::Backend::Mongoid::Job.find(params[:delayed_job_id])
    class_name = delayed_job.handler[/job_class: (\S+)/, 1]
    raise ActionController::RoutingError, "Unknown job" unless MANAGEABLE_JOBS.key?(class_name)

    worker_killed = false
    if delayed_job.locked_by.present?
      pid_match = delayed_job.locked_by.match(/pid:(\d+)/)
      if pid_match
        pid = pid_match[1].to_i
        begin
          Process.kill("KILL", pid)
          worker_killed = true
        rescue Errno::ESRCH
          # Process already gone — that's fine, carry on
        rescue Errno::EPERM
          return redirect_to jobs_path, alert: t("jobs.errors.abort_permission_denied")
        end
      end
    end

    delayed_job.destroy
    restart_worker if worker_killed
    redirect_to jobs_path, notice: t("jobs.aborted", name: humanize_job_name(class_name))
  end

  private

  def humanize_job_name(class_name)
    class_name.sub(/Job$/, "").gsub(/([A-Z])/, ' \1').strip
  end

  def restart_worker
    log_path = Rails.root.join("log/delayed_job.log").to_s
    pid = Process.spawn(
      {"RAILS_ENV" => Rails.env},
      "bundle", "exec", "rake", "jobs:work",
      chdir: Rails.root.to_s,
      in: "/dev/null",
      out: log_path,
      err: log_path
    )
    Process.detach(pid)
  end
end
