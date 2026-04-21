module PeopleHelper
  def list_persons_domains?(person)
    return false if person.domains.blank?
    return true if person.domains.size > 1
    # if they've only got one domain AND
    # they have a home url then that domain IS
    # the domain of the home url so there's no
    # point in listing them.
    person.home_url.blank?
  end
end
