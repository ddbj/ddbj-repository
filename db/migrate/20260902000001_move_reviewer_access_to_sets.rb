class MoveReviewerAccessToSets < ActiveRecord::Migration[8.1]
  # Reviewer access was one link per submission request, and it carried the
  # whole of the request from the moment it existed: the uploaded record,
  # the applied record, both flatfiles. It is now one link per set,
  # carrying the accessions the set's members have named on it.
  #
  # Nothing is migrated across, because there is nothing to migrate: a
  # request-wide share names no accessions and a request is not a set. Every
  # link handed out under the old table stops working, which is the point of
  # the change rather than a cost of it.
  def up
    drop_table :reviewer_accesses

    create_table :reviewer_accesses do |t|
      t.references :submission_set, null: false, foreign_key: true, index: {unique: true}
      t.references :created_by,     null: false, foreign_key: {to_table: :users}
      t.string     :token,          null: false, index: {unique: true}
      t.datetime   :expires_at,     null: false

      t.timestamps
    end

    create_table :reviewer_access_accessions do |t|
      t.references :reviewer_access, null: false, foreign_key: true
      t.references :added_by,        null: false, foreign_key: {to_table: :users}
      t.string     :accession,       null: false

      t.timestamps

      t.index %i[reviewer_access_id accession], unique: true, name: 'index_reviewer_access_accessions_uniqueness'
    end
  end

  def down
    drop_table :reviewer_access_accessions
    drop_table :reviewer_accesses

    create_table :reviewer_accesses do |t|
      t.references :submission_request, null: false, foreign_key: true, index: {unique: true}
      t.string     :token,      null: false, index: {unique: true}
      t.datetime   :expires_at, null: false

      t.timestamps
    end
  end
end
