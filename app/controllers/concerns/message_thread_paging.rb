# A thread is read from the end, so it is loaded from the end.
#
# Not `pagy`: page numbers count from the oldest message, so every new
# message shifts what "page 2" means, and the page somebody is reading
# changes under them. A cursor does not move.
#
# `Total-Count` says how many there are in all, which is what tells a
# client whether there is anything earlier to ask for. It is already in
# the CORS expose list, unlike a header invented here.
module MessageThreadPaging
  extend ActiveSupport::Concern

  # Enough that most threads arrive whole, small enough that the one that
  # does not cannot hold up the screen.
  PER_PAGE = 50

  private

  # `before_id` is the oldest message the caller already has.
  #
  # Paged by id and cut by id — one column for both, so the boundary is
  # exact. `created_at` is stamped in Ruby and the id at INSERT, so two
  # messages written at the same moment can disagree about which is
  # older; paging by one and cutting by the other would then hand the
  # same message out twice, and the thread renders it twice because
  # nothing keys the list.
  #
  # Sets `@thread_size` as well as the header: the screens that render
  # the page need the same number, and it is one COUNT either way.
  def thread_page(scope)
    # `reorder`, not `order`: the association carries `chronological`, and
    # appending to it leaves the oldest end first — so the page would be
    # the *beginning* of the thread, rendered backwards.
    page   = scope.reorder(id: :desc)
    before = params[:before_id].to_s.to_i

    page = page.where(id: ...before) if before.positive?

    @thread_size = scope.reorder(nil).count

    response.headers['Total-Count'] = @thread_size.to_s

    page.limit(PER_PAGE).to_a.reverse
  end
end
