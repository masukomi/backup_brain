import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { interval: { type: Number, default: 10000 } }

  connect() {
    this.timer = setInterval(() => {
      Turbo.visit(location.href, { action: "replace" })
    }, this.intervalValue)
  }

  disconnect() {
    clearInterval(this.timer)
  }
}
