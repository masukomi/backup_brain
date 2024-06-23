# Puma can serve each request in a thread from an internal thread pool.
# The `threads` method setting takes two numbers: a minimum and maximum.
# Any libraries that use thread pools should be configured to match
# the maximum value specified for Puma. Default is set to 5 threads for minimum
# and maximum; this matches the default thread size of Active Record.
#
max_threads_count = ENV.fetch("RAILS_MAX_THREADS") { 5 }
min_threads_count = ENV.fetch("RAILS_MIN_THREADS") { max_threads_count }
threads min_threads_count, max_threads_count

# Specifies the `worker_timeout` threshold that Puma will use to wait before
# terminating a worker in development environments.
#
worker_timeout 3600 if ENV.fetch("RAILS_ENV", "development") == "development"

# Specifies the `port` that Puma will listen on to receive requests; default is 3000.
#
port ENV.fetch("PORT") { 3000 }

# Specifies the `environment` that Puma will run in.
#
environment ENV.fetch("RAILS_ENV") { "development" }

# Specifies the `pidfile` that Puma will use.
pidfile ENV.fetch("PIDFILE") { "tmp/pids/server.pid" }

# Specifies the number of `workers` to boot in clustered mode.
# Workers are forked web server processes. If using threads and workers together
# the concurrency of the application would be max `threads` * `workers`.
# Workers do not work on JRuby or Windows (both of which do not support
# processes).
#
# workers ENV.fetch("WEB_CONCURRENCY") { 2 }

# Use the `preload_app!` method when specifying a `workers` number.
# This directive tells Puma to first boot the application and load code
# before forking the application. This takes advantage of Copy On Write
# process behavior so workers use less memory.
#
# preload_app!

# Allow puma to be restarted by `bin/rails restart` command.
plugin :tmp_restart

if Rails.env.development?
  force_ssl = (ENV.fetch("FORCE_SSL") { "false" }).strip == "true"

  host_name = (ENV.fetch("HOST_NAME") { "localhost" }).strip
  ssl_port  = (ENV.fetch("SSL_PORT") { "3335" }).to_i

  begin
    if force_ssl && host_name != "localhost"
      ip_address = (ENV.fetch("IP_ADDRESS") { "127.0.0.1" }).strip
      key_path   = File.join("config", "ssl", "#{host_name}_key.pem")
      cert_path  = File.join("config", "ssl", "#{host_name}_cert.pem")
      key_path_exists = File.exist?(key_path)
      cert_path_exists = File.exist?(cert_path)
      if key_path_exists && cert_path_exists
        ssl_bind ip_address, ssl_port, {
          key: key_path,
          cert: cert_path,
          verify_mode: "none"
        }

        Rails.logger.debug Paint["Configured Puma with SSL certs for #{host_name}", :green]
      else
        require "paint"
        Rails.logger.debug Paint["⚠️  SSL Configuration was wrong. Won't use SSL.", :red]
        Rails.logger.debug Paint["→ missing #{key_path}", :yellow] unless key_path_exists
        Rails.logger.debug Paint["→ missing #{cert_path}", :yellow] unless cert_path_exists

      end

    else
      Rails.logger.debug "SSL for Puma config is disabled. Skipping"
    end
  rescue
    Rails.logger.debug "⚠️  Something went wrong when atttempting to configure puma for SSL"
  end
end
