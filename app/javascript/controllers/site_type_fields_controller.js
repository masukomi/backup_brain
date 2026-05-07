import { Controller } from "@hotwired/stimulus"

// Shows/hides field groups based on the selected site type.
// The select element must have data-site-type-fields-target="select" and
// data-slug-map with a JSON object mapping site type IDs to slugs.
// Conditional field wrappers must have data-site-type-fields-target="conditional"
// and data-for-slug set to the slug that should show them.
export default class extends Controller {
  static targets = ["select", "conditional"]

  connect() {
    this.update()
  }

  update() {
    const slugMap = JSON.parse(this.selectTarget.dataset.slugMap)
    const selectedSlug = slugMap[this.selectTarget.value] || ""

    this.conditionalTargets.forEach(el => {
      el.hidden = el.dataset.forSlug !== selectedSlug
    })
  }
}
