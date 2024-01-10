module Pagination
  include Pagy::Backend

  def pagination_link_header(pagy, resource)
    return nil if pagy.last == 1

    {
      first: url_for([resource, page: 1]),
      last:  url_for([resource, page: pagy.last]),
      prev:  pagy.prev ? url_for([resource, page: pagy.prev]) : nil,
      next:  pagy.next ? url_for([resource, page: pagy.next]) : nil
    }.compact.map {|rel, url|
      %(<#{url}>; rel="#{rel}")
    }.join(', ')
  end
end
