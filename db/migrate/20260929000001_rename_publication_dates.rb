# When an object was first made public, and when what is public about it
# last changed — DB-2096's `last_published_at`, which moves on the way into
# public, on a change while public, and on the way out, and on nothing else.
# D-way's `release_date` and `dist_date` were those two, under names that
# said neither; `dist_date` did not move on the way out.
#
# Timestamps, as DB-2096 keeps them. What is here now is D-way's dates, taken
# as midnight in Tokyo until the next import brings the time of day.
#
# `modified_date` (D-way's every-update stamp, which is `updated_at`) and
# `issued_date` (never written) go: nothing reads them.
class RenamePublicationDates < ActiveRecord::Migration[8.1]
  TABLES = %i[projects samples dra_submissions].freeze

  def up
    TABLES.each do |table|
      rename_column table, :release_date, :first_published_at
      rename_column table, :dist_date,    :last_published_at

      %i[first_published_at last_published_at].each do |column|
        change_column table, column, :datetime, using: "(#{column}::timestamp AT TIME ZONE 'Asia/Tokyo') AT TIME ZONE 'UTC'"
      end
    end

    remove_column :projects, :modified_date, :date
    remove_column :projects, :issued_date,   :date
    remove_column :samples,  :modified_date, :date
  end

  def down
    add_column :projects, :modified_date, :date
    add_column :projects, :issued_date,   :date
    add_column :samples,  :modified_date, :date

    TABLES.each do |table|
      %i[first_published_at last_published_at].each do |column|
        change_column table, column, :date, using: "((#{column} AT TIME ZONE 'UTC') AT TIME ZONE 'Asia/Tokyo')::date"
      end

      rename_column table, :first_published_at, :release_date
      rename_column table, :last_published_at,  :dist_date
    end
  end
end
