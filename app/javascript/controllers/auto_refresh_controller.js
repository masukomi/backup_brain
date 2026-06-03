import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["intervalInput"]
  static values = { interval: { type: Number, default: 10000 } }

  connect() {
    const params = new URLSearchParams(location.search)
    const seconds = params.has("refresh") ? parseInt(params.get("refresh"), 10) : this.intervalValue / 1000
    const ms = seconds * 1000

    if (this.hasIntervalInputTarget) {
      this.intervalInputTarget.value = seconds
    }
    if (ms > 0) this._startTimer(ms)
  }

  disconnect() {
    clearInterval(this.timer)
  }

  intervalChanged() {
    clearInterval(this.timer)
    const seconds = parseInt(this.intervalInputTarget.value, 10)
    const params = new URLSearchParams(location.search)
    params.set("refresh", seconds)
    const newUrl = `${location.pathname}?${params}`
    history.replaceState(null, "", newUrl)
    if (seconds > 0) this._startTimer(seconds * 1000)
  }

  _startTimer(ms) {
    this.timer = setInterval(() => {
      Turbo.visit(location.href, { action: "replace" })
    }, ms)
  }
}
