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

ActiveRecord::Schema[8.1].define(version: 2026_03_05_083010) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "names", force: :cascade do |t|
    t.string "name_class", null: false
    t.string "name_txt", null: false
    t.bigint "tax_id", null: false
    t.index "lower((name_txt)::text), name_class", name: "index_names_on_LOWER_name_txt_name_class"
    t.index ["tax_id", "name_class"], name: "index_names_on_tax_id_and_name_class"
    t.index ["tax_id", "name_txt"], name: "index_names_on_tax_id_and_name_txt_common", where: "((name_class)::text = 'common name'::text)"
    t.index ["tax_id", "name_txt"], name: "index_names_on_tax_id_and_name_txt_scientific", where: "((name_class)::text = 'scientific name'::text)"
  end

  create_table "nodes", force: :cascade do |t|
    t.boolean "hidden_flag", null: false
    t.bigint "parent_tax_id", null: false
    t.string "rank"
    t.bigint "tax_id", null: false
    t.index ["parent_tax_id"], name: "index_nodes_on_parent_tax_id"
    t.index ["tax_id"], name: "index_nodes_on_tax_id"
  end
end
