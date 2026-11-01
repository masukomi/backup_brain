import { Controller } from "@hotwired/stimulus"

// Copies the text of the "source" target to the clipboard and, when a
// redirectUrl is given, sends the user there once the copy succeeded.
export default class extends Controller {
  static targets = ["source", "feedback"]
  static values = { redirectUrl: String, redirectDelay: { type: Number, default: 800 } }

  async copy() {
    const text = this.sourceTarget.textContent.trim()
    let copied = false
    // navigator.clipboard only exists in secure contexts (https or
    // localhost). Plain http on another host falls through to execCommand.
    if (navigator.clipboard && window.isSecureContext) {
      try {
        await navigator.clipboard.writeText(text)
        copied = true
      } catch (e) {
        copied = false
      }
    }
    if (!copied) copied = this._legacyCopy(text)

    if (!copied) {
      // Nothing worked: leave the key selected so the user can copy by hand.
      this._selectSource()
      return
    }
    if (this.hasFeedbackTarget) this.feedbackTarget.hidden = false
    if (this.redirectUrlValue) {
      setTimeout(() => Turbo.visit(this.redirectUrlValue), this.redirectDelayValue)
    }
  }

  _legacyCopy(text) {
    const textarea = document.createElement("textarea")
    textarea.value = text
    textarea.setAttribute("readonly", "")
    textarea.style.position = "fixed"
    textarea.style.opacity = "0"
    document.body.appendChild(textarea)
    textarea.select()
    let ok = false
    try {
      ok = document.execCommand("copy")
    } catch (e) {
      ok = false
    }
    document.body.removeChild(textarea)
    return ok
  }

  _selectSource() {
    const range = document.createRange()
    range.selectNodeContents(this.sourceTarget)
    const selection = window.getSelection()
    selection.removeAllRanges()
    selection.addRange(range)
  }
}
