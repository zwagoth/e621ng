#!/usr/bin/env ruby

require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'config', 'environment'))

UserStatus.find_each do |user_status|
  user_status.update_column(:post_replacement_rejected_count, PostReplacement.rejected.for_user(user_status.user.id).count)
end

# post ids who have two replacements, one approved, one original
PostReplacement.select(:post_id).where(status: ["approved", "original"]).group(:post_id)
               .having("count(post_id) = 2").map(&:post_id).each do |post_id|
  replacements = PostReplacement.where(post_id: post_id).order(:status)
  
  approved = replacements[0]
  original = replacements[1]

  approved.uploader_id_on_approve = original.creator_id
  approved.penalize_uploader_on_approve = true
  approved.save!

  user_status = UserStatus.for_user(original.creator_id)
  user_status.update_all("own_post_replaced_count = own_post_replaced_count + 1")
  user_status.update_all("own_post_replaced_penalize_count = own_post_replaced_penalize_count + 1")
end
