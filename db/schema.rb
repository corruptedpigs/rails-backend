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

ActiveRecord::Schema[8.1].define(version: 2026_06_05_000001) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "articles", force: :cascade do |t|
    t.string "author"
    t.text "content"
    t.datetime "created_at", null: false
    t.text "description"
    t.string "external_id", null: false
    t.string "image_url"
    t.string "language", default: "en", null: false
    t.datetime "notified_at"
    t.integer "preview_views", default: 0, null: false
    t.string "public_id", null: false
    t.datetime "published_at"
    t.float "relevance_score"
    t.string "source_name"
    t.string "status", default: "pending", null: false
    t.string "story_key"
    t.string "telegram_channel"
    t.bigint "telegram_message_id"
    t.string "title"
    t.datetime "updated_at", null: false
    t.string "url"
    t.index ["external_id"], name: "index_articles_on_external_id", unique: true
    t.index ["language"], name: "index_articles_on_language"
    t.index ["public_id"], name: "index_articles_on_public_id", unique: true
    t.index ["published_at"], name: "index_articles_on_published_at"
    t.index ["status"], name: "index_articles_on_status"
    t.index ["story_key"], name: "index_articles_on_story_key"
  end

  create_table "audits", force: :cascade do |t|
    t.string "action"
    t.bigint "associated_id"
    t.string "associated_type"
    t.bigint "auditable_id"
    t.string "auditable_type"
    t.text "audited_changes"
    t.string "comment"
    t.datetime "created_at"
    t.string "remote_address"
    t.string "request_uuid"
    t.bigint "user_id"
    t.string "user_type"
    t.string "username"
    t.integer "version", default: 0
    t.index ["associated_type", "associated_id"], name: "associated_index"
    t.index ["auditable_type", "auditable_id", "version"], name: "auditable_index"
    t.index ["created_at"], name: "index_audits_on_created_at"
    t.index ["request_uuid"], name: "index_audits_on_request_uuid"
    t.index ["user_id", "user_type"], name: "user_index"
  end
end
