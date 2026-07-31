# Who has actually worked on a request, as opposed to who owns it.
#
# Assignment is a decision — someone presses "Assign to me" and takes
# responsibility. Participation is a side effect: reply to a submitter,
# edit a record, issue an accession, and you are involved whether or not
# you own it. Keeping the two apart is what lets My queue show a curator
# everything they are part of without ever moving an assignment behind
# their back, which is the failure mode of any auto-assign scheme.
#
# No `updated_at`: a row records that something happened, and it is never
# edited afterwards.
class CreateSubmissionRequestParticipants < ActiveRecord::Migration[8.1]
  def change
    create_table :submission_request_participants do |t|
      t.references :submission_request, null: false, foreign_key: true, index: false
      t.references :user,               null: false, foreign_key: true
      t.datetime   :created_at,         null: false

      # Unique so participation is idempotent — the tenth reply on a
      # thread must not add a tenth row — and it doubles as the lookup
      # index for "requests involving me".
      t.index %i[submission_request_id user_id], unique: true, name: 'index_participants_on_request_and_user'
    end
  end
end
