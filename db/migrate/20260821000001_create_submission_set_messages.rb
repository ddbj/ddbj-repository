# The set's own conversation.
#
# Its own thread rather than a message fanned out to the submissions in
# the set: a question about twelve submissions is one question, and
# writing it into twelve request threads would put it in a curator's
# queue twelve times — the duplication the submitter was trying to avoid,
# handed to the other side.
#
# `read_at` (the request thread's marker) has no meaning here. There it
# stands for "the submitter has dealt with this", and there is exactly
# one submitter; a set has as many members as it has, so where each of
# them has got to is a fact about the person and lives on their roster
# row or their participation.
class CreateSubmissionSetMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :submission_set_messages do |t|
      t.references :submission_set, null: false, foreign_key: true
      t.references :user,           null: false, foreign_key: true

      t.string :author_role, null: false
      t.text   :body,        null: false

      t.timestamps

      # How the thread is read, and how "has anybody answered since?" is
      # asked — both walk one set's messages in order.
      t.index %i[submission_set_id created_at id]
    end

    # A curator's relationship to one set's thread, mirroring
    # SubmissionRequestParticipant: `unsubscribed_at` decides whether it
    # reaches their queue at all, `last_read_at` how far they have got.
    # Members are not here — they are the roster, and their marker is on
    # it.
    create_table :submission_set_participants do |t|
      t.references :submission_set, null: false, foreign_key: true
      t.references :user,           null: false, foreign_key: true

      t.datetime :last_read_at
      t.datetime :unsubscribed_at

      t.timestamps

      t.index %i[submission_set_id user_id], unique: true, name: 'index_set_participants_on_set_and_user'
    end

    # Where this member has got to in the set's thread. On the roster row
    # because that is what a member is: nothing here follows or unfollows,
    # since being in the set is what makes it theirs to read.
    add_column :submission_set_members, :last_read_at, :datetime
  end
end
