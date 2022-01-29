class AddIndexResultsUpdatedAt < ActiveRecord::Migration[5.1]
  def change
    add_index :results, 'updated_at'
  end
end
