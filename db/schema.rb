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

ActiveRecord::Schema[8.1].define(version: 2025_12_25_065705) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "accession_renewal_validation_details", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "message", null: false
    t.bigint "renewal_id", null: false
    t.string "severity", null: false
    t.datetime "updated_at", null: false
    t.index ["renewal_id"], name: "index_accession_renewal_validation_details_on_renewal_id"
  end

  create_table "accession_renewals", force: :cascade do |t|
    t.bigint "accession_id", null: false
    t.datetime "created_at", null: false
    t.datetime "finished_at"
    t.string "progress", default: "waiting", null: false
    t.datetime "started_at"
    t.datetime "updated_at", null: false
    t.string "validity"
    t.index ["accession_id"], name: "index_accession_renewals_on_accession_id"
  end

  create_table "accessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "entry_id", null: false
    t.datetime "last_updated_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.string "number", null: false
    t.bigint "submission_id", null: false
    t.datetime "updated_at", null: false
    t.integer "version", default: 1, null: false
    t.index ["number", "entry_id", "version"], name: "index_accessions_on_number_and_entry_id_and_version", unique: true
    t.index ["number"], name: "index_accessions_on_number", unique: true
    t.index ["submission_id"], name: "index_accessions_on_submission_id"
  end

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "bioproject_submission_params", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "umbrella", null: false
    t.datetime "updated_at", null: false
  end

  create_table "objs", force: :cascade do |t|
    t.string "_id", null: false
    t.datetime "created_at", null: false
    t.string "destination"
    t.datetime "updated_at", null: false
    t.bigint "validation_id", null: false
    t.string "validity"
    t.index ["validation_id"], name: "index_objs_on_validation_id"
    t.index ["validity"], name: "index_objs_on_validity"
  end

  create_table "sequences", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "next", default: 1, null: false
    t.string "prefix", null: false
    t.string "scope", null: false
    t.datetime "updated_at", null: false
    t.index ["scope"], name: "index_sequences_on_scope", unique: true
  end

  create_table "submissions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "error_message"
    t.datetime "finished_at"
    t.string "param_id"
    t.string "param_type"
    t.string "progress", default: "waiting", null: false
    t.string "result"
    t.datetime "started_at"
    t.datetime "updated_at", null: false
    t.bigint "validation_id", null: false
    t.string "visibility", null: false
    t.index ["validation_id"], name: "index_submissions_on_validation_id", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.boolean "admin", default: false, null: false
    t.string "api_key", null: false
    t.datetime "created_at", null: false
    t.string "uid", null: false
    t.datetime "updated_at", null: false
    t.index ["api_key"], name: "index_users_on_api_key", unique: true
    t.index ["uid"], name: "index_users_on_uid", unique: true
  end

  create_table "validation_details", force: :cascade do |t|
    t.string "code"
    t.datetime "created_at", null: false
    t.string "entry_id"
    t.string "message"
    t.bigint "obj_id", null: false
    t.string "severity"
    t.datetime "updated_at", null: false
    t.index ["obj_id"], name: "index_validation_details_on_obj_id"
  end

  create_table "validations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "db", null: false
    t.datetime "finished_at"
    t.string "progress", default: "waiting", null: false
    t.string "raw_result"
    t.datetime "started_at"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.string "via", null: false
    t.index ["created_at"], name: "index_validations_on_created_at"
    t.index ["db"], name: "index_validations_on_db"
    t.index ["progress"], name: "index_validations_on_progress"
    t.index ["user_id"], name: "index_validations_on_user_id"
  end

  add_foreign_key "accession_renewal_validation_details", "accession_renewals", column: "renewal_id"
  add_foreign_key "accession_renewals", "accessions"
  add_foreign_key "accessions", "submissions"
  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "objs", "validations"
  add_foreign_key "submissions", "validations"
  add_foreign_key "validation_details", "objs"
  add_foreign_key "validations", "users"
end
