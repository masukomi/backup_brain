#!/usr/bin/env ruby

require "json"
module ArchiverJsonHelper
  def error_json_and_exit(note:, exception:, additional_info: nil)
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
    puts JSON.pretty_generate({
      status: "SUCCESS",
      markdown: markdown
    })
    exit 0
  end
end
