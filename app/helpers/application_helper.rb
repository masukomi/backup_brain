module ApplicationHelper
  def icon_link(icon_name, url, link_class = nil)
    link_to(
      image_tag(
        "/images/icons/#{icon_name}.svg"
      ),
      url,
      class: link_class
    )
  end
end
