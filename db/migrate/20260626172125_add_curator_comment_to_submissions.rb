class AddCuratorCommentToSubmissions < ActiveRecord::Migration[8.1]
  def change
    add_column :submissions, :curator_comment, :text
  end
end
