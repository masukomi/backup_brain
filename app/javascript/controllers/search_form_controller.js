import { Controller } from "@hotwired/stimulus"

// Switches the search form between searching Bookmarks and searching Notes.
// Retargets the form's action and hides the "Search Archives Too" option,
// which only applies to bookmarks.
export default class extends Controller {
  static targets = ["target", "archivesOption"]
  static values = { bookmarksUrl: String, notesUrl: String }

  connect() {
    this.update()
  }

  update() {
    const searchingNotes = this.targetTarget.value === "notes"

    this.element.action = searchingNotes
      ? this.notesUrlValue
      : this.bookmarksUrlValue

    if (this.hasArchivesOptionTarget) {
      this.archivesOptionTarget.hidden = searchingNotes
    }
  }
}
