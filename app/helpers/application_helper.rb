require "htmlentities"
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
    text: nil,
    target: nil)

    link_options = {
      class: link_css,
      method: method,
      target: target
    }
    link_options[:title] = title if title

    image_options = {
      class: icon_css
    }
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

  def get_setting(lookup_key)
    @@settings_cache ||= Hash[* Setting.all.map { |s| [s.lookup_key, s.value] }.flatten]
    @@settings_cache[lookup_key]
  end

  def bust_settings_cache
    @@settings_cache = nil
  end

  private

  def icon_link_text(text)
    return "" if text.blank?
    "<span class='icon-link-text'>#{text}</span>".html_safe
  end
end
