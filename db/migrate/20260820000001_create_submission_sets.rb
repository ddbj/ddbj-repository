class CreateSubmissionSets < ActiveRecord::Migration[8.1]
  # Two axes, deliberately separate tables: who is in a set
  # (submission_set_members) and what is in it
  # (submission_set_inclusions). Putting a submission in a set is the only
  # thing that lets the set's members read it, which is why the two are
  # joined only through the set.
  def change
    create_table :submission_sets do |t|
      t.string     :name,  null: false
      t.references :owner, null: false, foreign_key: {to_table: :users}

      t.timestamps
    end

    # One row per person, whether they have accepted yet or not: "add a
    # member" is one action, so it leaves one row. `user_id` is what
    # separates the two states — absent means the invitation is still out.
    create_table :submission_set_members do |t|
      t.references :submission_set, null: false, foreign_key: true

      # What the inviter typed. Absent on the creator's own row, who was
      # never invited — a joined member's address is their account's.
      t.string     :email
      t.references :user,                        foreign_key: true
      t.references :invited_by,    null: false,  foreign_key: {to_table: :users}
      t.string     :invitation_token
      t.datetime   :invitation_expires_at
      t.datetime   :joined_at

      t.timestamps
    end

    # The address is what the inviter typed, so it is matched the way a
    # person would read it back.
    add_index :submission_set_members, 'submission_set_id, lower(email)',
              unique: true,
              name:   'index_submission_set_members_on_set_and_lower_email'

    add_index :submission_set_members, :invitation_token,
              unique: true,
              where:  'invitation_token IS NOT NULL'

    # One account, one seat. Without this, somebody invited at two of
    # their addresses joins twice and appears on the roster twice.
    add_index :submission_set_members, %i[submission_set_id user_id],
              unique: true,
              where:  'user_id IS NOT NULL'

    # Pending and joined are the only two states there are, and an
    # invitation is not half an invitation: a pending row carries the
    # address it went to, the token it went out as, and the date it stops
    # working, or it does not exist.
    #
    # A joined row KEEPS its token. The token grants nothing once it has
    # been walked through — acceptance refuses a row that is already
    # joined — and keeping it is what lets the link say "this invitation
    # has already been used" rather than answering the person holding it
    # with a 404.
    add_check_constraint :submission_set_members, <<~SQL.squish, name: 'submission_set_members_state_exclusivity'
      (user_id IS     NULL AND joined_at IS     NULL AND email IS NOT NULL AND invitation_token IS NOT NULL AND invitation_expires_at IS NOT NULL) OR
      (user_id IS NOT NULL AND joined_at IS NOT NULL)
    SQL

    create_table :submission_set_inclusions do |t|
      t.references :submission_set,     null: false, foreign_key: true
      t.references :submission_request, null: false, foreign_key: true
      t.references :added_by,           null: false, foreign_key: {to_table: :users}

      t.timestamps
    end

    # Many-to-many on purpose: a BioProject is a hub, and the sets hanging
    # off it are different collaborations rather than one.
    add_index :submission_set_inclusions, %i[submission_set_id submission_request_id], unique: true
  end
end
