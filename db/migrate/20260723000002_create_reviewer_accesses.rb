class CreateReviewerAccesses < ActiveRecord::Migration[8.1]
  # A shareable, unguessable link that lets a reviewer view a submission
  # request without logging in. One active link per request (unique
  # submission_request_id); re-enabling regenerates the token.
  def change
    create_table :reviewer_accesses do |t|
      t.references :submission_request, null: false, foreign_key: true, index: {unique: true}
      t.string     :token,      null: false, index: {unique: true}
      t.datetime   :expires_at, null: false

      t.timestamps
    end
  end
end
