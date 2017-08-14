class CreateResults < ActiveRecord::Migration[5.1]
  def change
    create_table :results do |t|
      t.timestamps
      t.string :name
      t.string :result
      t.string :desc
      t.string :detail_link
      t.string :memo
    end
  end
end
