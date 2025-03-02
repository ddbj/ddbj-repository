class Init < ActiveRecord::Migration[7.1]
  def change
    create_table :dway_users do |t|
      t.string :uid, null: false

      t.timestamps

      t.index :uid, unique: true
    end

    create_table :submissions do |t|
      t.references :dway_user, foreign_key: true

      t.timestamps
    end

    create_table :requests do |t|
      t.references :dway_user,  foreign_key: true
      t.references :submission, foreign_key: true

      t.string :db,     null: false
      t.string :status, null: false
      t.jsonb  :result

      t.timestamps
    end

    create_table :objs do |t|
      t.references :request, foreign_key: true, null: false

      t.string :key, null: false
    end
  end
end
