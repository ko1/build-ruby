class AddRevToResults < ActiveRecord::Migration[7.0]
  def change
    add_column :results, :rev, :string
  end
end
