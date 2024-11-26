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

ActiveRecord::Schema[8.0].define(version: 2024_08_27_024216) do
  create_schema "mass"

  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "ext_entity", primary_key: "ext_id", force: :cascade do |t|
    t.text "acc_type", null: false
    t.text "ref_name", null: false
    t.integer "status", null: false
  end

  create_table "ext_permit", primary_key: "per_id", force: :cascade do |t|
    t.bigint "ext_id", null: false
    t.text "submitter_id", null: false
  end

  create_table "operation_history", primary_key: "his_id", force: :cascade do |t|
    t.integer "type", null: false
    t.text "summary", null: false
    t.text "file_name"
    t.binary "detail"
    t.datetime "date", precision: nil, default: -> { "date_trunc('second'::text, now())" }, null: false
    t.bigint "usr_id", null: false
    t.integer "serial"
    t.text "submitter_id"
  end

  create_table "status_history", force: :cascade do |t|
    t.bigint "sub_id", null: false
    t.integer "status", null: false
    t.datetime "date", precision: nil, default: -> { "date_trunc('second'::text, now())" }, null: false
  end

  create_table "submission", primary_key: "sub_id", force: :cascade do |t|
    t.bigint "usr_id", null: false
    t.text "submitter_id", null: false
    t.integer "serial", null: false
    t.integer "charge"
    t.date "create_date"
    t.date "submit_date"
    t.date "hold_date"
    t.date "dist_date"
    t.date "finish_date"
    t.text "note"
  end
end
