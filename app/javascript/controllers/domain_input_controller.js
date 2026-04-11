import { Controller } from "@hotwired/stimulus"

const DOMAIN_REGEXP = /(?:\w+\.)+\w+$/

export default class extends Controller {
  static targets = ["textInput", "chipsArea", "addButton", "hiddenFields"]
  static values = { existing: Array }

  connect() {
    this.existingValue.forEach(domain => this._addChip(domain))
  }

  handleInput() {
    const valid = DOMAIN_REGEXP.test(this.textInputTarget.value.trim())
    this.addButtonTarget.disabled = !valid
  }

  handleKeydown(e) {
    if (e.key === "Enter") {
      e.preventDefault()
      if (!this.addButtonTarget.disabled) this.addDomain()
    }
  }

  addDomain() {
    const value = this.textInputTarget.value.trim()
    if (!DOMAIN_REGEXP.test(value)) return
    this._addChip(value)
    this.textInputTarget.value = ""
    this.addButtonTarget.disabled = true
    this.textInputTarget.focus()
  }

  _addChip(domain) {
    const existing = Array.from(this.chipsAreaTarget.querySelectorAll(".domain-chip"))
      .map(el => el.dataset.domain)
    if (existing.includes(domain)) return

    const chip = document.createElement("span")
    chip.className = "tag-chip domain-chip"
    chip.dataset.domain = domain

    const label = document.createElement("span")
    label.textContent = domain

    const removeBtn = document.createElement("button")
    removeBtn.type = "button"
    removeBtn.className = "tag-chip-remove"
    removeBtn.setAttribute("aria-label", `Remove domain ${domain}`)
    removeBtn.textContent = "×"
    removeBtn.addEventListener("click", () => {
      chip.remove()
      this._removeHiddenField(domain)
    })

    chip.appendChild(label)
    chip.appendChild(removeBtn)
    this.chipsAreaTarget.appendChild(chip)
    this._addHiddenField(domain)
  }

  _addHiddenField(domain) {
    const input = document.createElement("input")
    input.type = "hidden"
    input.name = "person[domains][]"
    input.value = domain
    input.dataset.domain = domain
    this.hiddenFieldsTarget.appendChild(input)
  }

  _removeHiddenField(domain) {
    const field = this.hiddenFieldsTarget.querySelector(`input[data-domain="${CSS.escape(domain)}"]`)
    if (field) field.remove()
  }
}
