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

ActiveRecord::Schema[7.2].define(version: 2024_08_29_001416) do
  create_schema "mass"

  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "contact_form", primary_key: ["submission_id", "seq_no"], force: :cascade do |t|
    t.text "submission_id", null: false
    t.integer "seq_no", null: false
    t.text "email"
    t.text "first_name"
    t.text "last_name"
  end

  create_table "link_form", primary_key: ["submission_id", "seq_no"], force: :cascade do |t|
    t.text "submission_id", null: false
    t.integer "seq_no", null: false
    t.text "description"
    t.text "url"
  end

  create_table "operation_history", primary_key: "his_id", force: :cascade do |t|
    t.integer "type"
    t.text "summary"
    t.text "file_name"
    t.binary "detail"
    t.datetime "date", precision: nil
    t.bigint "usr_id"
    t.integer "serial"
    t.text "submitter_id"
    t.text "submission_id"
  end

  create_table "submission", primary_key: "submission_id", id: :text, force: :cascade do |t|
    t.text "submitter_id"
    t.text "organization"
    t.text "organization_url"
    t.text "comment"
    t.integer "charge_id", default: 1
    t.datetime "create_date", precision: nil, default: -> { "now()" }, null: false
    t.datetime "modified_date", precision: nil, default: -> { "now()" }, null: false
  end

  create_table "submission_form", primary_key: "submission_id", id: :text, force: :cascade do |t|
    t.text "submitter_id", null: false
    t.integer "status_id", null: false
    t.text "organization"
    t.text "organization_url"
    t.integer "release_type"
    t.integer "core_package"
    t.integer "pathogen"
    t.integer "mixs"
    t.integer "env_pkg"
    t.text "attribute_file_name"
    t.text "attribute_file"
    t.text "comment"
    t.datetime "create_date", precision: nil, default: -> { "now()" }, null: false
    t.datetime "modified_date", precision: nil, default: -> { "now()" }, null: false
    t.text "package_group"
    t.text "package"
    t.text "env_package"
  end
end
