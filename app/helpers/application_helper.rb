module ApplicationHelper
  def icon_link(icon_name, url, link_css: nil, method: :get, alt: nil, title: nil)
    link_to(
      image_tag(
        "/images/icons/#{icon_name}.svg"
      ),
      url,
      class: link_css,
      method: method,
      alt: (alt.presence || t("misc.missing_alt_text")),
      title: (title.presence || "")
    )
  end
end
