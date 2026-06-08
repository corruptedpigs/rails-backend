class AddImageUrlToArticles < ActiveRecord::Migration[8.1]
  def change
    add_column :articles, :image_url, :string
  end
end
