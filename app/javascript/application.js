// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"

document.addEventListener("click", (event) => {
  const blurred = event.target.closest(".blurred, spoiler")
  if (blurred) {
    event.preventDefault()
    event.stopPropagation()
    if (blurred.tagName.toLowerCase() === "spoiler") {
      const span = document.createElement("span")
      span.innerHTML = blurred.innerHTML
      blurred.replaceWith(span)
    } else {
      blurred.classList.remove("blurred")
    }
  }
})
