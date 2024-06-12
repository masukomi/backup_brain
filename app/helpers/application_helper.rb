module ApplicationHelper
  def icon_link(icon_name, url,
    link_css: nil,
    method: :get,
    alt: nil,
    title: nil,
    text: nil)
    link_to(
      image_tag(
        "/images/icons/#{icon_name}.svg"
      ) + icon_link_text(text),
      url,
      class: link_css,
      method: method,
      alt: (alt.presence || t("misc.missing_alt_text")),
      title: (title.presence || "")
    )
  end

  def confirmation_icon_link(icon_name, url,
    link_css: nil,
    method: :get,
    alt: nil,
    title: nil,
    text: nil)
    link_to(
      image_tag(
        "/images/icons/#{icon_name}.svg"
      ) + icon_link_text(text),
      url,
      class: link_css,
      method: method,
      alt: (alt.presence || t("misc.missing_alt_text")),
      title: (title.presence || ""),
      data: {confirm: t("misc.are_you_sure")}
    )
  end

  private

  def icon_link_text(text)
    return "" if text.blank?
    "<span class='icon-link-text'>#{text}</span>".html_safe
  end
end
