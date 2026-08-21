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

  # `before_id` is the oldest message the caller already has. Ids are
  # sequential and `chronological` breaks ties by id, so the cursor and
  # the reading order are the same order.
  def thread_page(scope)
    # `reorder`, not `order`: the association carries `chronological`, and
    # appending to it leaves the oldest end first — so the page would be
    # the *beginning* of the thread, rendered backwards.
    page = scope.reorder(created_at: :desc, id: :desc)
    page = page.where(id: ...params[:before_id].to_i) if params[:before_id].present?

    response.headers['Total-Count'] = scope.reorder(nil).count.to_s

    page.limit(PER_PAGE).to_a.reverse
  end
end
