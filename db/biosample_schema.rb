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

ActiveRecord::Schema[8.1].define(version: 2024_08_29_001416) do
  create_schema "mass"

  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "mass.attribute", primary_key: ["smp_id", "attribute_name"], force: :cascade do |t|
    t.text "attribute_name", null: false
    t.text "attribute_value"
    t.integer "seq_no", null: false
    t.bigint "smp_id", null: false
  end

  create_table "mass.contact", primary_key: ["submission_id", "seq_no"], force: :cascade do |t|
    t.datetime "create_date", precision: nil, default: -> { "now()" }, null: false
    t.text "email"
    t.text "first_name"
    t.text "last_name"
    t.datetime "modified_date", precision: nil, default: -> { "now()" }, null: false
    t.integer "seq_no", null: false
    t.text "submission_id", null: false
  end

  create_table "mass.contact_form", primary_key: ["submission_id", "seq_no"], force: :cascade do |t|
    t.text "email"
    t.text "first_name"
    t.text "last_name"
    t.integer "seq_no", null: false
    t.text "submission_id", null: false
  end

  create_table "mass.link", primary_key: ["smp_id", "seq_no"], force: :cascade do |t|
    t.text "description"
    t.integer "seq_no", null: false
    t.bigint "smp_id", null: false
    t.text "url"
  end

  create_table "mass.link_form", primary_key: ["submission_id", "seq_no"], force: :cascade do |t|
    t.text "description"
    t.integer "seq_no", null: false
    t.text "submission_id", null: false
    t.text "url"
  end

  create_table "mass.operation_history", primary_key: "his_id", force: :cascade do |t|
    t.datetime "date", precision: nil
    t.binary "detail"
    t.text "file_name"
    t.integer "serial"
    t.text "submission_id"
    t.text "submitter_id"
    t.text "summary"
    t.integer "type"
    t.bigint "usr_id"
  end

  create_table "mass.sample", primary_key: "smp_id", force: :cascade do |t|
    t.integer "core_package"
    t.datetime "create_date", precision: nil, default: -> { "now()" }, null: false
    t.datetime "dist_date", precision: nil
    t.text "env_package"
    t.integer "env_pkg"
    t.integer "mixs"
    t.datetime "modified_date", precision: nil, default: -> { "now()" }, null: false
    t.text "package"
    t.text "package_group"
    t.integer "pathogen"
    t.datetime "release_date", precision: nil
    t.integer "release_type"
    t.text "sample_name", null: false
    t.integer "status_id"
    t.text "submission_id", null: false
  end

  create_table "mass.submission", primary_key: "submission_id", id: :text, force: :cascade do |t|
    t.integer "charge_id", default: 1
    t.text "comment"
    t.datetime "create_date", precision: nil, default: -> { "now()" }, null: false
    t.datetime "modified_date", precision: nil, default: -> { "now()" }, null: false
    t.text "organization"
    t.text "organization_url"
    t.text "submitter_id"
  end

  create_table "mass.submission_form", primary_key: "submission_id", id: :text, force: :cascade do |t|
    t.text "attribute_file"
    t.text "attribute_file_name"
    t.text "comment"
    t.integer "core_package"
    t.datetime "create_date", precision: nil, default: -> { "now()" }, null: false
    t.text "env_package"
    t.integer "env_pkg"
    t.integer "mixs"
    t.datetime "modified_date", precision: nil, default: -> { "now()" }, null: false
    t.text "organization"
    t.text "organization_url"
    t.text "package"
    t.text "package_group"
    t.integer "pathogen"
    t.integer "release_type"
    t.integer "status_id", null: false
    t.text "submitter_id", null: false
  end

  create_table "mass.xml", primary_key: ["smp_id", "version"], force: :cascade do |t|
    t.text "accession_id"
    t.text "content", null: false
    t.datetime "create_date", precision: nil, default: -> { "now()" }, null: false
    t.datetime "modified_date", precision: nil, default: -> { "now()" }, null: false
    t.bigint "smp_id", null: false
    t.integer "version", null: false
  end

end
