class UserPresenter
  attr_reader :user

  def initialize(user)
    @user = user
  end

  def name
    user.pretty_name
  end

  def join_date
    user.created_at.strftime("%Y-%m-%d")
  end

  def level
    user.level_string
  end

  def ban_reason
    if user.is_banned?
      "#{user.recent_ban.reason}; expires #{user.recent_ban.expires_at || 'never'} (#{user.bans.count} bans total)"
    else
      nil
    end
  end

  def permissions
    permissions = []

    if user.can_approve_posts?
      permissions << "approve posts"
    end

    if user.can_upload_free?
      permissions << "unrestricted uploads"
    end

    permissions.join(", ")
  end

  def upload_limit(template)
    if user.can_upload_free?
      return "none"
    end

    upload_limit_pieces = user.upload_limit_pieces

    %{<abbr title="Base Upload Limit">#{user.base_upload_limit}</abbr> + (<abbr title="Approved Posts">#{upload_limit_pieces[:approved]}</abbr> / 10) - (<abbr title="Deleted Posts">#{upload_limit_pieces[:deleted]}</abbr> / 4) - <abbr title="Pending or Flagged Posts">#{upload_limit_pieces[:pending]}</abbr> = <abbr title="User Upload Limit Remaining">#{user.upload_limit}</abbr>}.html_safe
  end

  def uploads
    Post.tag_match("user:#{user.name}").limit(6).records
  end

  def has_uploads?
    user.post_upload_count > 0
  end

  def favorites
    ids = Favorite.select(:post_id).where(user_id: user.id).order(created_at: :desc).limit(50).map(&:post_id)[0..5]
    Post.where(id: ids)
  end

  def has_favorites?
    user.favorite_count > 0
  end

  def upload_count(template)
    template.link_to(user.post_upload_count, template.posts_path(:tags => "user:#{user.name}"))
  end

  def active_upload_count(template)
    template.link_to(user.post_upload_count - user.post_deleted_count, template.posts_path(:tags => "user:#{user.name}"))
  end

  def deleted_upload_count(template)
    template.link_to(user.post_deleted_count, template.deleted_posts_path(user_id: user.id))
  end

  def replaced_upload_count(template)
    template.link_to(user.own_post_replaced_count, template.post_replacements_path(search: {uploader_name_on_approve: user.name}))
  end

  def favorite_count(template)
    template.link_to(user.favorite_count, template.favorites_path(:user_id => user.id))
  end

  def comment_count(template)
    template.link_to(user.comment_count, template.comments_path(:search => {:creator_id => user.id}, :group_by => "comment"))
  end

  def commented_posts_count(template)
    count = CurrentUser.without_safe_mode { Post.fast_count("commenter:#{user.name}") }
    template.link_to(count, template.posts_path(:tags => "commenter:#{user.name} order:comment_bumped"))
  end

  def post_version_count(template)
    template.link_to(user.post_update_count, template.post_versions_path(:lr => user.id, :search => {:updater_id => user.id}))
  end

  def note_version_count(template)
    template.link_to(user.note_version_count, template.note_versions_path(:search => {:updater_id => user.id}))
  end

  def noted_posts_count(template)
    count = CurrentUser.without_safe_mode { Post.fast_count("noteupdater:#{user.name}") }
    template.link_to(count, template.posts_path(:tags => "noteupdater:#{user.name} order:note"))
  end

  def wiki_page_version_count(template)
    template.link_to(user.wiki_page_version_count, template.wiki_page_versions_path(:search => {:updater_id => user.id}))
  end

  def artist_version_count(template)
    template.link_to(user.artist_version_count, template.artist_versions_path(:search => {:updater_id => user.id}))
  end

  def forum_post_count(template)
    template.link_to(user.forum_post_count, template.forum_posts_path(:search => {:creator_id => user.id}))
  end

  def pool_version_count(template)
    template.link_to(user.pool_version_count, template.pool_versions_path(:search => {:updater_id => user.id}))
  end

  def appeal_count(template)
    template.link_to(user.appeal_count, template.post_appeals_path(:search => {:creator_name => user.name}))
  end

  def flag_count(template)
    template.link_to(user.flag_count, template.post_flags_path(:search => {:creator_name => user.name}))
  end

  def approval_count(template)
    template.link_to(Post.where("approver_id = ?", user.id).count, template.posts_path(:tags => "approver:#{user.name}"))
  end

  def feedbacks
    positive = user.positive_feedback_count
    neutral = user.neutral_feedback_count
    negative = user.negative_feedback_count

    return "0" unless positive > 0 || neutral > 0 || negative > 0

    total_class = (positive - negative) > 0 ? "user-feedback-positive" : "user-feedback-negative"
    total_class = "" if (positive - negative) == 0
    positive_html = %{<span class="user-feedback-positive">#{positive} Pos</span>}.html_safe if positive > 0
    neutral_html = %{<span class="user-feedback-neutral">#{neutral} Neutral</span>}.html_safe if neutral > 0
    negative_html = %{<span class="user-feedback-negative">#{negative} Neg</span>}.html_safe if negative > 0

    %{<span class="#{total_class}">#{positive - negative}</span> ( #{positive_html} #{neutral_html} #{negative_html} ) }.html_safe
  end

  def previous_names(template)
    user.user_name_change_requests.map { |req| template.link_to req.original_name, req }.join(" -> ").html_safe
  end

  def favorite_tags_with_types
    tag_names = user&.favorite_tags.to_s.split
    tag_names = TagAlias.to_aliased(tag_names)
    indices = tag_names.each_with_index.map {|x, i| [x, i]}.to_h
    Tag.where(name: tag_names).map {|x| [x.name, x.post_count, x.category]}.sort_by {|x| indices[x[0]] }
  end

  def recent_tags_with_types
    versions = PostArchive.where(updater_id: user.id).where("updated_at > ?", 1.hour.ago).order(id: :desc).limit(150)
    tags = versions.flat_map(&:added_tags)
    tags = tags.reject { |tag| Tag.is_metatag?(tag) }
    tags = tags.group_by(&:itself).transform_values(&:size).sort_by { |tag, count| [-count, tag] }.map(&:first)
    tags = tags.take(50)
    Tag.where(name: tags).map {|x| [x.name, x.post_count, x.category]}
  end

  def custom_css
    user.custom_style.to_s.split(/\r\n|\r|\n/).map do |line|
      if line =~ /\A@import/
        line
      else
        line.gsub(/([^[:space:]])[[:space:]]*(?:!important)?[[:space:]]*(;|})/, "\\1 !important\\2")
      end
    end.join("\n")
  end

  def can_view_favorites?
    return true if CurrentUser.id == user.id
    return false if user.enable_privacy_mode? && !CurrentUser.is_admin?
    true
  end

  def show_staff_notes?
    CurrentUser.is_moderator?
  end

  def staff_notes
    StaffNote.where(user_id: user.id).order(id: :desc).limit(15)
  end

  def new_staff_note
    StaffNote.new(user_id: user.id)
  end
end
