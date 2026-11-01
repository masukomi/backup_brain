import { Controller } from "@hotwired/stimulus"

// Copies the text of the "source" target to the clipboard and, when a
// redirectUrl is given, sends the user there once the copy succeeded.
export default class extends Controller {
  static targets = ["source", "feedback"]
  static values = { redirectUrl: String, redirectDelay: { type: Number, default: 800 } }

  async copy() {
    const text = this.sourceTarget.textContent.trim()
    try {
      await navigator.clipboard.writeText(text)
    } catch (e) {
      // Older browsers / non-secure contexts: leave the key on screen.
      this._selectSource()
      return
    }
    if (this.hasFeedbackTarget) this.feedbackTarget.hidden = false
    if (this.redirectUrlValue) {
      setTimeout(() => Turbo.visit(this.redirectUrlValue), this.redirectDelayValue)
    }
  }

  _selectSource() {
    const range = document.createRange()
    range.selectNodeContents(this.sourceTarget)
    const selection = window.getSelection()
    selection.removeAllRanges()
    selection.addRange(range)
  }
}
