class CreateArticles < ActiveRecord::Migration[8.1]
  def change
    create_table :articles do |t|
      t.string   :public_id,          null: false
      t.string   :external_id,        null: false
      t.string   :title
      t.text     :description
      t.text     :content
      t.string   :url
      t.string   :source_name
      t.string   :author
      t.string   :language,           null: false, default: "en"
      t.datetime :published_at
      t.float    :relevance_score
      t.string   :story_key
      t.string   :status,             null: false, default: "pending"
      t.datetime :notified_at
      t.bigint   :telegram_message_id
      t.string   :telegram_channel
      t.integer  :preview_views,      null: false, default: 0

      t.timestamps
    end

    add_index :articles, :public_id,   unique: true
    add_index :articles, :external_id, unique: true
    add_index :articles, :story_key
    add_index :articles, :status
    add_index :articles, :language
    add_index :articles, :published_at
  end
end
