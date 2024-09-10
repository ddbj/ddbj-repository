# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.2].define(version: 2024_08_27_022556) do
  create_schema "mass"

  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "action_history", primary_key: "action_id", id: :serial, force: :cascade do |t|
    t.text "submission_id"
    t.text "action", null: false
    t.datetime "action_date", precision: nil
    t.boolean "result", default: true, null: false
    t.text "action_level", null: false
    t.text "submitter_id"
  end

  create_table "project", primary_key: "submission_id", id: :text, force: :cascade do |t|
    t.text "project_id_prefix", default: "PRJDB"
    t.serial "project_id_counter", null: false
    t.datetime "created_date", precision: nil, default: -> { "now()" }, null: false
    t.datetime "modified_date", precision: nil, default: -> { "now()" }, null: false
    t.datetime "issued_date", precision: nil
    t.integer "status_id"
    t.text "project_type", null: false
    t.datetime "release_date", precision: nil
    t.datetime "dist_date", precision: nil
    t.text "comment"
  end

  create_table "submission", primary_key: "submission_id", id: :text, force: :cascade do |t|
    t.text "submitter_id"
    t.integer "status_id", default: 100
    t.datetime "created_date", precision: nil, default: -> { "now()" }, null: false
    t.datetime "modified_date", precision: nil, default: -> { "now()" }, null: false
    t.integer "charge_id", default: 1, null: false
    t.string "form_status_flags", limit: 6, default: "000000"
  end

  create_table "submission_data", primary_key: ["submission_id", "data_name", "t_order"], force: :cascade do |t|
    t.text "submission_id", null: false
    t.text "data_name", null: false
    t.text "data_value"
    t.integer "t_order", default: -1, null: false
    t.text "form_name"
    t.datetime "modified_date", precision: nil, default: -> { "now()" }, null: false
  end

  create_table "xml", primary_key: ["submission_id", "version"], force: :cascade do |t|
    t.text "submission_id", null: false
    t.text "content", null: false
    t.integer "version", null: false
    t.text "registered_date", default: -> { "now()" }, null: false
  end
end
