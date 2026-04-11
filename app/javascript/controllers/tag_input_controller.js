import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["hidden", "chipsArea", "textInput", "dropdown"]
  static values = { autocompleteUrl: String }

  connect() {
    this._debounceTimer = null
    this._activeIndex = -1
    const existing = this.hiddenTarget.value.trim()
    if (existing) {
      existing.split(/\s+/).filter(t => t.length > 0).forEach(t => this._addChip(t))
    }
  }

  disconnect() {
    clearTimeout(this._debounceTimer)
  }

  focusInput() {
    this.textInputTarget.focus()
  }

  handleKeydown(e) {
    const items = this._dropdownItems()

    switch (e.key) {
      case "ArrowDown":
        e.preventDefault()
        this._activeIndex = Math.min(this._activeIndex + 1, items.length - 1)
        this._highlightItem(items)
        break

      case "ArrowUp":
        e.preventDefault()
        this._activeIndex = Math.max(this._activeIndex - 1, -1)
        this._highlightItem(items)
        break

      case "Escape":
        this._hideDropdown()
        break

      case "Enter": {
        const word = this.textInputTarget.value.trim()
        if (this._dropdownVisible() && this._activeIndex >= 0 && items[this._activeIndex]) {
          e.preventDefault()
          this._selectItem(items[this._activeIndex].dataset.tag)
        } else if (word.length > 0) {
          e.preventDefault()
          this._selectItem(word)
        }
        break
      }

      case "Tab": {
        const word = this.textInputTarget.value.trim()
        if (this._dropdownVisible() && this._activeIndex >= 0 && items[this._activeIndex]) {
          e.preventDefault()
          this._selectItem(items[this._activeIndex].dataset.tag)
        } else if (word.length > 0) {
          // Add chip but don't preventDefault — let Tab move focus
          this._selectItem(word)
        }
        break
      }

      case " ":
      case ",": {
        const word = this.textInputTarget.value.trim()
        e.preventDefault()
        if (word.length > 0) this._selectItem(word)
        break
      }

      case "Backspace":
        if (this.textInputTarget.value === "") {
          const chips = this.chipsAreaTarget.querySelectorAll(".tag-chip")
          if (chips.length > 0) {
            chips[chips.length - 1].remove()
            this._syncHidden()
          }
        }
        break
    }
  }

  handleInput() {
    clearTimeout(this._debounceTimer)
    this._activeIndex = -1

    // Handle paste: split on spaces/commas into chips, keep last partial word
    const value = this.textInputTarget.value
    if (value.includes(" ") || value.includes(",")) {
      const parts = value.split(/[\s,]+/).filter(p => p.length > 0)
      const last = parts.pop()
      parts.forEach(p => this._addChip(p))
      this.textInputTarget.value = last || ""
    }

    const word = this.textInputTarget.value.trim()
    if (word.length < 3) {
      this._hideDropdown()
      return
    }
    this._debounceTimer = setTimeout(() => this._fetchSuggestions(word), 300)
  }

  _fetchSuggestions(q) {
    const url = `${this.autocompleteUrlValue}?q=${encodeURIComponent(q)}`
    fetch(url, { headers: { Accept: "application/json" } })
      .then(r => r.json())
      .then(tags => this._showDropdown(tags))
      .catch(() => this._hideDropdown())
  }

  _showDropdown(tags) {
    const dropdown = this.dropdownTarget
    dropdown.innerHTML = ""
    if (tags.length === 0) {
      this._hideDropdown()
      return
    }
    tags.forEach(tag => {
      const li = document.createElement("li")
      const btn = document.createElement("button")
      btn.type = "button"
      btn.className = "dropdown-item"
      btn.textContent = tag
      btn.dataset.tag = tag
      btn.addEventListener("mousedown", e => {
        e.preventDefault() // prevent blur before click registers
        this._selectItem(tag)
      })
      li.appendChild(btn)
      dropdown.appendChild(li)
    })
    dropdown.classList.add("show")
  }

  _hideDropdown() {
    this.dropdownTarget.classList.remove("show")
    this.dropdownTarget.innerHTML = ""
    this._activeIndex = -1
  }

  _dropdownVisible() {
    return this.dropdownTarget.classList.contains("show")
  }

  _dropdownItems() {
    return Array.from(this.dropdownTarget.querySelectorAll(".dropdown-item"))
  }

  _highlightItem(items) {
    items.forEach((item, i) => item.classList.toggle("active", i === this._activeIndex))
  }

  _selectItem(tag) {
    this._addChip(tag)
    this.textInputTarget.value = ""
    this._hideDropdown()
    this.textInputTarget.focus()
  }

  _addChip(text) {
    const normalized = text.toLowerCase().replace(/\s+/g, "_").replace(/,/g, "")
    if (!normalized) return

    const existing = Array.from(this.chipsAreaTarget.querySelectorAll(".tag-chip"))
      .map(el => el.dataset.tag)
    if (existing.includes(normalized)) return

    const chip = document.createElement("span")
    chip.className = "tag-chip"
    chip.dataset.tag = normalized

    const label = document.createElement("span")
    label.textContent = normalized

    const removeBtn = document.createElement("button")
    removeBtn.type = "button"
    removeBtn.className = "tag-chip-remove"
    removeBtn.setAttribute("aria-label", `Remove tag ${normalized}`)
    removeBtn.textContent = "×"
    removeBtn.addEventListener("click", () => {
      chip.remove()
      this._syncHidden()
    })

    chip.appendChild(label)
    chip.appendChild(removeBtn)
    this.chipsAreaTarget.insertBefore(chip, this.textInputTarget)
    this._syncHidden()
  }

  _syncHidden() {
    const tags = Array.from(this.chipsAreaTarget.querySelectorAll(".tag-chip"))
      .map(el => el.dataset.tag)
    this.hiddenTarget.value = tags.join(" ")
  }
}
