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

ActiveRecord::Schema[8.1].define(version: 2026_10_01_093000) do
  create_table "items", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "dismissed", default: false, null: false
    t.text "evidence"
    t.string "external_id", null: false
    t.json "facts", default: {}
    t.json "followup", default: {}
    t.boolean "missing_from_snapshot", default: false, null: false
    t.text "next_action"
    t.datetime "observed_at"
    t.json "overrides", default: {}
    t.string "project_id"
    t.datetime "snoozed_until"
    t.string "source", null: false
    t.datetime "source_updated_at"
    t.string "source_url"
    t.string "status", default: "unknown", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["source", "external_id"], name: "index_items_on_source_and_external_id", unique: true
  end



  create_table "source_states", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "last_attempt_at"
    t.datetime "last_success_at"
    t.text "message"
    t.datetime "observed_at"
    t.string "source", null: false
    t.string "state", default: "unavailable", null: false
    t.datetime "updated_at", null: false
    t.index ["source"], name: "index_source_states_on_source", unique: true
  end
end
