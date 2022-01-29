class ResultsAddDescJson < ActiveRecord::Migration[7.0]
  def change
    add_column(:results, :desc_json, :string)
    add_column(:results, :core_link, :string)
  end
end
