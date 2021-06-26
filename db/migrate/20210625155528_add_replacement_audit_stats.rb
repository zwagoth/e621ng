class AddReplacementAuditStats < ActiveRecord::Migration[6.1]
  def up
    add_column :post_replacements2, :uploader_id_on_approve, :int
    add_column :post_replacements2, :penalize_uploader_on_approve, :boolean
    add_column :user_statuses, :own_post_replaced_count, :int, nil: false, default: 0
    add_column :user_statuses, :own_post_replaced_penalize_count, :int, nil: false, default: 0
    add_column :user_statuses, :post_replacement_rejected_count, :int, nil: false, default: 0

  end

  def down
    drop_column :post_replacements2, :uploader_id_on_approve
    drop_column :post_replacements2, :penalize_uploader_on_approve
    drop_column :user_statuses, :own_post_replaced_count
    drop_column :user_statuses, :own_post_replaced_penalize_count
    drop_column :user_statuses, :post_replacement_rejected_count
  end
end
