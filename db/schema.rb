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

ActiveRecord::Schema[8.1].define(version: 2026_06_02_170600) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "accession_histories", force: :cascade do |t|
    t.bigint "accession_id", null: false
    t.string "action", null: false
    t.datetime "created_at", null: false
    t.bigint "user_id", null: false
    t.index ["accession_id"], name: "index_accession_histories_on_accession_id"
    t.index ["user_id"], name: "index_accession_histories_on_user_id"
  end

  create_table "accessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "entry_id", null: false
    t.date "locus_date", default: -> { "CURRENT_TIMESTAMP" }, null: false
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

  create_table "project_links", force: :cascade do |t|
    t.bigint "child_project_id", null: false
    t.datetime "created_at", null: false
    t.string "external_accession"
    t.bigint "parent_project_id"
    t.datetime "updated_at", null: false
    t.index ["child_project_id", "external_accession"], name: "index_project_links_on_child_and_external", unique: true, where: "(external_accession IS NOT NULL)"
    t.index ["child_project_id", "parent_project_id"], name: "index_project_links_on_child_and_parent", unique: true, where: "(parent_project_id IS NOT NULL)"
    t.index ["child_project_id"], name: "index_project_links_on_child_project_id"
    t.index ["parent_project_id"], name: "index_project_links_on_parent_project_id"
    t.check_constraint "parent_project_id IS NOT NULL AND external_accession IS NULL OR parent_project_id IS NULL AND external_accession IS NOT NULL", name: "project_links_target_exclusivity"
  end

  create_table "projects", force: :cascade do |t|
    t.string "accession"
    t.bigint "assignee_id"
    t.datetime "created_at", null: false
    t.date "dist_date"
    t.date "hold_date"
    t.date "issued_date"
    t.integer "project_type", null: false
    t.date "release_date"
    t.integer "status", default: 5100, null: false
    t.bigint "submission_id", null: false
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["accession"], name: "index_projects_on_accession", unique: true, where: "(accession IS NOT NULL)"
    t.index ["assignee_id"], name: "index_projects_on_assignee_id"
    t.index ["status"], name: "index_projects_on_status"
    t.index ["submission_id"], name: "index_projects_on_submission_id", unique: true
  end

  create_table "regenerate_flatfiles_progresses", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "failed", default: 0, null: false
    t.integer "processed", default: 0, null: false
    t.integer "total", null: false
    t.datetime "updated_at", null: false
  end

  create_table "sample_references", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ref_accession", null: false
    t.string "ref_db", null: false
    t.bigint "sample_id", null: false
    t.datetime "updated_at", null: false
    t.index ["ref_db", "ref_accession"], name: "index_sample_references_on_ref_db_and_ref_accession"
    t.index ["sample_id", "ref_db", "ref_accession"], name: "index_sample_references_on_sample_db_accession", unique: true
    t.index ["sample_id"], name: "index_sample_references_on_sample_id"
  end

  create_table "samples", force: :cascade do |t|
    t.string "accession"
    t.bigint "assignee_id"
    t.datetime "created_at", null: false
    t.date "dist_date"
    t.string "env_package"
    t.string "organism"
    t.string "package"
    t.string "package_group"
    t.date "release_date"
    t.integer "release_type"
    t.string "sample_name", null: false
    t.integer "status", default: 5100, null: false
    t.bigint "submission_id", null: false
    t.integer "taxonomy_id"
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["accession"], name: "index_samples_on_accession", unique: true, where: "(accession IS NOT NULL)"
    t.index ["assignee_id"], name: "index_samples_on_assignee_id"
    t.index ["package"], name: "index_samples_on_package"
    t.index ["package_group"], name: "index_samples_on_package_group"
    t.index ["sample_name"], name: "index_samples_on_sample_name"
    t.index ["status"], name: "index_samples_on_status"
    t.index ["submission_id"], name: "index_samples_on_submission_id"
  end

  create_table "sequences", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "next", default: 1, null: false
    t.string "prefix", null: false
    t.string "scope", null: false
    t.datetime "updated_at", null: false
    t.index ["scope"], name: "index_sequences_on_scope", unique: true
  end

  create_table "submission_requests", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "db", null: false
    t.string "error_message"
    t.integer "status", default: 0, null: false
    t.bigint "submission_id"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["db"], name: "index_submission_requests_on_db"
    t.index ["submission_id"], name: "index_submission_requests_on_submission_id"
    t.index ["user_id"], name: "index_submission_requests_on_user_id"
  end

  create_table "submission_updates", force: :cascade do |t|
    t.string "actor"
    t.datetime "created_at", null: false
    t.string "db", null: false
    t.string "error_message"
    t.binary "patch", null: false
    t.integer "patch_canonical_version", default: 1, null: false
    t.integer "source", default: 0, null: false
    t.integer "status", default: 0, null: false
    t.bigint "submission_id", null: false
    t.datetime "updated_at", null: false
    t.index ["actor"], name: "index_submission_updates_on_actor", where: "(actor IS NOT NULL)"
    t.index ["db"], name: "index_submission_updates_on_db"
    t.index ["submission_id", "created_at"], name: "index_submission_updates_on_submission_id_and_created_at"
    t.index ["submission_id"], name: "index_submission_updates_on_submission_id"
    t.check_constraint "octet_length(patch) > 0", name: "submission_updates_patch_nonempty"
  end

  create_table "submissions", force: :cascade do |t|
    t.integer "canonical_version", default: 1, null: false
    t.string "converter_version"
    t.datetime "created_at", null: false
    t.string "db", null: false
    t.uuid "migration_run_id"
    t.string "source_id"
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["db"], name: "index_submissions_on_db"
    t.index ["migration_run_id"], name: "index_submissions_on_migration_run_id", where: "(migration_run_id IS NOT NULL)"
    t.index ["source_id"], name: "index_submissions_on_source_id", unique: true, where: "(source_id IS NOT NULL)"
    t.index ["user_id"], name: "index_submissions_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.boolean "admin", default: false, null: false
    t.string "api_key", null: false
    t.datetime "created_at", null: false
    t.text "notes", default: "", null: false
    t.string "uid", null: false
    t.datetime "updated_at", null: false
    t.index ["api_key"], name: "index_users_on_api_key", unique: true
    t.index ["uid"], name: "index_users_on_uid", unique: true
  end

  create_table "validation_details", force: :cascade do |t|
    t.string "code", null: false
    t.datetime "created_at", null: false
    t.string "entry_id"
    t.string "message", null: false
    t.string "severity", null: false
    t.datetime "updated_at", null: false
    t.bigint "validation_id", null: false
    t.index ["validation_id"], name: "index_validation_details_on_validation_id"
  end

  create_table "validations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "finished_at"
    t.string "progress", default: "running", null: false
    t.jsonb "raw_result"
    t.bigint "subject_id", null: false
    t.string "subject_type", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_validations_on_created_at"
    t.index ["progress"], name: "index_validations_on_progress"
    t.index ["subject_type", "subject_id"], name: "index_validations_on_subject"
  end

  add_foreign_key "accession_histories", "accessions"
  add_foreign_key "accession_histories", "users"
  add_foreign_key "accessions", "submissions"
  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "project_links", "projects", column: "child_project_id"
  add_foreign_key "project_links", "projects", column: "parent_project_id"
  add_foreign_key "projects", "submissions"
  add_foreign_key "projects", "users", column: "assignee_id"
  add_foreign_key "sample_references", "samples"
  add_foreign_key "samples", "submissions"
  add_foreign_key "samples", "users", column: "assignee_id"
  add_foreign_key "submission_requests", "submissions"
  add_foreign_key "submission_requests", "users"
  add_foreign_key "submission_updates", "submissions"
  add_foreign_key "submissions", "users"
  add_foreign_key "validation_details", "validations"
end
