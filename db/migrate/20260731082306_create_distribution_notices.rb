# What was sent, to whom, on whose say-so, and whether it arrived.
#
# Until now the only trace a release notice left was
# `projects.distribution_notified_at` — enough to stop sending twice, not
# enough to answer "was this submitter told?", which is the question the
# screen exists for. A skipped submitter left nothing at all, so the only
# evidence that an address was missing was the row still sitting in the
# due list with no explanation of how long it had been there.
#
# Accessions are denormalised on purpose: this records what the mail
# said. A project renamed or deleted afterwards must not change the
# history of what a submitter was told.
class CreateDistributionNotices < ActiveRecord::Migration[8.1]
  def change
    create_table :distribution_notices do |t|
      t.references :user, null: false, foreign_key: true, index: false

      t.datetime :sent_at, null: false

      # `scheduled` (the daily job) or `manual`; `actor` names the curator
      # for the latter. Support questions are almost always "who sent
      # this, and when", so the answer is one column pair.
      t.string :trigger, null: false
      t.string :actor

      # `delivered` or `skipped`. A skip is history too — without it the
      # due list cannot explain itself.
      t.string :result,      null: false
      t.string :skip_reason

      t.jsonb :accessions, null: false, default: []

      t.index %i[sent_at], order: {sent_at: :desc}
      t.index %i[user_id sent_at]
    end
  end
end
