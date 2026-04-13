Delayed::Worker.destroy_failed_jobs = true
Delayed::Worker.sleep_delay = 60
Delayed::Worker.max_attempts = 3

# setting to 30 minutes max_run_time because
# transcription jobs on a pi are NOT fast.
Delayed::Worker.max_run_time = 30.minutes
Delayed::Worker.read_ahead = 10
Delayed::Worker.default_queue_name = "default"
Delayed::Worker.delay_jobs = !Rails.env.test?
Delayed::Worker.raise_signal_exceptions = :term
Delayed::Worker.logger = Logger.new(Rails.root.join("log/delayed_job.log").to_s)
