module ApplicationHelper
  include Pagy::Frontend

  def inline_icon(icon_name,
    icon_class: "inline-icon",
    alt: nil,
    title: nil)
    image_tag("/images/icons/#{icon_name}.svg",
      class: icon_class,
      alt: alt,
      title: title)
  end

  def icon_link(icon_name, url,
    link_css: nil,
    icon_css: nil,
    method: :get,
    alt: nil,
    title: nil,
    text: nil)
    link_to(
      image_tag(
        "/images/icons/#{icon_name}.svg",
        class: icon_css
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

  ## Finds the appropriate Bootstrap css class for the
  ## type of alert we're using
  def class_for_flash(type)
    {
      notice: "alert-primary",
      error: "alert-warning",
      alert: "alert-danger"
    }[type] || "alert-dark"
    # dark seemed as good a default as anything.
  end

  private

  def icon_link_text(text)
    return "" if text.blank?
    "<span class='icon-link-text'>#{text}</span>".html_safe
  end
end
