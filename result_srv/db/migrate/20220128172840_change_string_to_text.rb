class ChangeStringToText < ActiveRecord::Migration[7.0]
  def change
    change_column :results, :memo, :text
    change_column :results, :desc, :text
    change_column :results, :desc_json, :text
  end
end
