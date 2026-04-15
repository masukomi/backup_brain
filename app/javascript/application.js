// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"

document.addEventListener("click", (event) => {
  const blurred = event.target.closest(".blurred")
  if (blurred) {
    event.preventDefault()
    event.stopPropagation()
    blurred.classList.remove("blurred")
  }
})
