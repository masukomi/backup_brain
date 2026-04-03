require "htmlentities"
module ApplicationHelper
  include Pagy::Frontend

  def inline_icon(icon_name,
    icon_class: "inline-icon",
    alt: nil,
    title: nil,
    aria_hidden: false)

    tag_options = {
      class: icon_class
    }
    # don't waste html characters on useless attributes
    tag_options[:alt] = alt if alt
    tag_options[:title] = title if title
    tag_options[:"aria-hidden"] = aria_hidden if aria_hidden

    image_tag("/images/icons/#{icon_name}.svg", tag_options)
  end

  def icon_link(icon_name, url,
    link_css: nil,
    icon_css: nil,
    method: :get,
    alt: nil,
    title: nil,
    text: nil,
    target: nil,
    aria_hidden: false)

    link_options = {method: method}
    link_options[:class] = link_css if link_css
    link_options[:target] = target if target
    link_options[:title] = title if title
    link_options[:"aria-hidden"] = aria_hidden if aria_hidden

    image_options = {class: icon_css}
    if alt.present?
      image_options[:alt] = alt
    else
      image_options[:"aria-hidden"] = true
    end

    link_to(
      image_tag(
        "/images/icons/#{icon_name}.svg",
        image_options
      ) + icon_link_text(text),
      url,
      link_options
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
      alt: alt.presence || t("misc.missing_alt_text"),
      title: title.presence || "",
      data: {confirm: t("misc.are_you_sure")}
    )
  end

  ## Finds the appropriate Bootstrap css class for the
  ## type of alert we're using
  def class_for_flash(type)
    {
      "notice" => "alert-primary",
      "error" => "alert-warning",
      "alert" => "alert-danger"
    }[type] || "alert-dark"
    # dark seemed as good a default as anything.
  end

  # Calculates how many rows a text area should have
  # based on the number of lines in its content.
  def text_area_rows(text, minimum: 8)
    lines = text.to_s.split("\n")
    lines_count = lines.map { |l|
      c = (l.chars.count / 80)
      (c == 0) ? 1 : c
    }.sum + 4
    # +4 because the correct number is always cut off
    # with my large fonts and 4 gives it just enough
    # buffer that it feels like it's encouraging you
    # to add "just a little more.. if you want" ;)

    (lines_count > minimum) ? lines_count : minimum
  end

  def decode_entities(text)
    @@html_entities ||= HTMLEntities.new

    @@html_entities.decode(text)
  end

  private

  def icon_link_text(text)
    return "" if text.blank?
    "<span class='icon-link-text'>#{text}</span>".html_safe
  end
end
