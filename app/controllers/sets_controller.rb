class SetsController < ApplicationController
  include SetContents

  before_action :refuse_proxy!, only: %i[create update destroy]
  before_action :load_set,    only: %i[show update destroy]

  def index
    @sets = SubmissionSet.joined_by(current_user).order(:name, :id).includes(:owner)

    # Counted, not loaded. `preload` here would instantiate every join row
    # in every set the reader belongs to in order to print three
    # integers each.
    @counts = self.class.set_counts(@sets.map(&:id), viewer: current_user)
  end

  def show
    load_set_contents
  end

  def create
    @set = SubmissionSet.create!(name: set_params[:name], owner: current_user)

    load_set_contents
    render :show, status: :created
  end

  def update
    forbid! 'Only the owner can rename a set.' unless @set.owned_by?(current_user)

    @set.update!(set_params)

    load_set_contents
    render :show
  end

  # Deleting is the owner's, and only once the set is empty of everyone
  # else's things: the submissions in it are their owners' to take out,
  # and the people in it are not the owner's to dissolve.
  #
  # Under a lock, and re-checked inside it. `deletable?` and `destroy!`
  # are two statements, and an invitation sent between them would be
  # destroyed by the cascade — which is the exact outcome the rule exists
  # to prevent.
  def destroy
    forbid! 'Only the owner can delete a set.' unless @set.owned_by?(current_user)

    @set.with_lock do
      refuse! SubmissionSet::EMPTY_FIRST unless @set.deletable?

      @set.destroy!
    end

    head :no_content
  end

  private

  # `:id` here, where everything nested under a set reads `:set_id` —
  # which is the whole of why this one is not SetContents#load_set. Same
  # rule behind it: a set you are not in is not visible as a set you are
  # not in.
  def load_set
    @set = SubmissionSet.joined_by(current_user).find(params.expect(:id))
  end

  def set_params = params.expect(set: %i[name])
end
