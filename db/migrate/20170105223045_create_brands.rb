class CreateBrands < ActiveRecord::Migration[5.0]
  def change
    create_table :brands do |t|
      t.string :name
      t.string :desc
      t.string :profile_img
      t.string :card_img

      t.timestamps
    end
  end
end
