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

ActiveRecord::Schema[8.1].define(version: 2024_08_27_023903) do
  create_schema "mass"

  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "mass.contact", primary_key: "cnt_id", force: :cascade do |t|
    t.text "email"
    t.text "first_name", default: ""
    t.boolean "is_contact", default: false, null: false
    t.boolean "is_pi", default: false, null: false
    t.text "last_name", default: ""
    t.text "middle_name", default: ""
    t.text "submitter_id", null: false
  end

  create_table "mass.login", primary_key: "usr_id", force: :cascade do |t|
    t.datetime "create_date", precision: nil, default: -> { "date_trunc('second'::text, now())" }
    t.boolean "need_chgpasswd", default: true
    t.text "password", null: false
    t.integer "role", default: 0, null: false
    t.text "submitter_id", null: false
    t.boolean "usable", default: true, null: false
  end

  create_table "mass.organization", primary_key: "submitter_id", id: :text, force: :cascade do |t|
    t.text "address"
    t.text "affiliation"
    t.text "center_name"
    t.text "city"
    t.text "country"
    t.text "department"
    t.text "detail"
    t.text "fax"
    t.text "organization"
    t.text "phone"
    t.text "phone_ext"
    t.text "state"
    t.text "unit"
    t.text "url"
    t.text "zipcode"
  end

end
