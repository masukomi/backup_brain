Delayed::Worker.destroy_failed_jobs = true
Delayed::Worker.sleep_delay = 60
Delayed::Worker.max_attempts = 3

# Whisper Transcription on a Pi can be *very* slow for long audio files.
# > 30min run time for ~13 min audio on a Pi5
if ENV["DELAYED_WORKER_MAX_RUN_MINUTES"].present?
  mins = ENV["DELAYED_WORKER_MAX_RUN_MINUTES"].to_i
  Delayed::Worker.max_run_time = if mins > 0
    mins.minutes
  else
    120.minutes
  end
else
  Delayed::Worker.max_run_time = 2.hours
end
Delayed::Worker.read_ahead = 10
Delayed::Worker.default_queue_name = "default"
Delayed::Worker.delay_jobs = !Rails.env.test?
Delayed::Worker.raise_signal_exceptions = :term
Delayed::Worker.logger = Logger.new(Rails.root.join("log/delayed_job.log").to_s)
