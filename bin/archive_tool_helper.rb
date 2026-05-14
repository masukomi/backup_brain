#!/usr/bin/env ruby

require "json"
require "logger"

module ArchiveToolHelper
  LOG_PATH = File.expand_path("../log/archivers.log", __dir__)

  def self.logger
    @logger ||= begin
      log = Logger.new(LOG_PATH)
      log.level = Logger::INFO
      log.formatter = proc { |severity, time, _progname, msg|
        "#{time.strftime("%Y-%m-%dT%H:%M:%S")} #{severity.ljust(5)}: #{msg}\n"
      }
      log
    end
  end

  def archiver_logger
    ArchiveToolHelper.logger
  end

  def error_json_and_exit(note:, exception:, additional_info: nil)
    log_msg = "[#{File.basename($0)}] #{note}"
    log_msg += ": #{exception.message}" if exception
    archiver_logger.error(log_msg)
    archiver_logger.error(exception.backtrace.join("\n")) if exception&.backtrace

    warn "#{note}: #{exception.message}"
    json = {
      status: "ERROR",
      note: note,
      error_message: exception&.message,
      backtrace: exception&.backtrace&.join("\n"),
      additional_info: additional_info
    }

    puts JSON.pretty_generate(json)
    exit 0
  end

  def success_json_and_exit(markdown:)
    archiver_logger.info("[#{File.basename($0)}] completed successfully")
    puts JSON.pretty_generate({
      status: "SUCCESS",
      markdown: markdown
    })
    exit 0
  end
end
