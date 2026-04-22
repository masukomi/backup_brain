import { Controller } from "@hotwired/stimulus"

// Manages the light/dark mode toggle.
// Stores the user's explicit choice in localStorage under "bb-color-scheme".
// Sets data-color-scheme="dark|light" on <html> so the active CSS theme file
// can respond to it via :root[data-color-scheme="dark"] selectors.
//
// An inline script in <head> reads localStorage and sets the attribute before
// the first paint, preventing any flash of unstyled content.
export default class extends Controller {
  static targets = ["icon", "label"]
  static values = { darkLabel: String, lightLabel: String }

  connect() {
    this._mq = window.matchMedia("(prefers-color-scheme: dark)")
    this.updateToggle()

    // Re-render label if OS preference changes (only matters when no explicit override is saved)
    this._mqListener = () => {
      if (!localStorage.getItem("bb-color-scheme")) this.updateToggle()
    }
    this._mq.addEventListener("change", this._mqListener)
  }

  disconnect() {
    this._mq?.removeEventListener("change", this._mqListener)
  }

  toggle(event) {
    event.preventDefault()
    const next = this.effectiveScheme() === "dark" ? "light" : "dark"
    localStorage.setItem("bb-color-scheme", next)
    document.documentElement.dataset.colorScheme = next
    this.updateToggle()
  }

  effectiveScheme() {
    return document.documentElement.dataset.colorScheme ||
      (this._mq.matches ? "dark" : "light")
  }

  updateToggle() {
    const isDark = this.effectiveScheme() === "dark"
    this.iconTarget.src = isDark ? "/images/icons/sun.svg" : "/images/icons/moon.svg"
    this.labelTarget.textContent = isDark ? this.lightLabelValue : this.darkLabelValue
  }
}
