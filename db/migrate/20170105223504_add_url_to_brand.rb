class AddUrlToBrand < ActiveRecord::Migration[5.0]
  def change
    add_column :brands, :facebook_url, :string
    add_column :brands, :instagram_url, :string
    add_column :brands, :twitter_url, :string
  end
end
