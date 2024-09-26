class ScriptKiddiesController < ApplicationController
  STATUSES = Rack::Utils::SYMBOL_TO_STATUS_CODE.select { |k, v| v > 400 }.keys.freeze
  def fuck_off
    head(STATUSES.sample)
  end
end
