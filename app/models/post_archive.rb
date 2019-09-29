class PostArchive < ApplicationRecord
  class RevertError < Exception ; end
  extend Memoist

  belongs_to :post
  belongs_to_updater
  user_status_counter :post_update_count, foreign_key: :updater_id

  before_validation :fill_version, on: :create
  before_validation :fill_changes, on: :create

  #establish_connection (ENV["ARCHIVE_DATABASE_URL"] || "archive_#{Rails.env}".to_sym) if enabled?
  self.table_name = "post_versions"

  def self.check_for_retry(msg)
    if msg =~ /can't get socket descriptor/ && msg =~ /post_versions/
      connection.reconnect!
    end
  end

  module SearchMethods
    def for_user(user_id)
      if user_id
        where("updater_id = ?", user_id)
      else
        none
      end
    end

    def for_user_name(name)
      user_id = User.name_to_id(name)
      for_user(user_id)
    end

    def build_query(params)
      must = []
      def should(*args)
        {bool: {should: args}}
      end
      def split_to_terms(field, input)
        input.split(',').map(&:to_i).map {|x| {term: {field => x}}}
      end

      if params[:updater_name].present?
        must << {term: {updater_id: User.name_to_id(params[:updater_name])}}
      end

      if params[:updater_id].present?
        must << should(*split_to_terms(:updater_id, params[:updater_id]))
      end

      if params[:post_id].present?
        must << should(*split_to_terms(:post_id, params[:post_id]))
      end

      if params[:start_id].present?
        must << {range: {id: {gte: params[:start_id].to_i}}}
      end

      if must.empty?
        must.push({match_all: {}})
      end

      {
          query: {bool: {must: must}},
          sort: {id: :desc},
          _source: false,
          timeout: "#{CurrentUser.user.try(:statement_timeout) || 3_000}ms"
      }
    end
  end

  extend SearchMethods
  include Indexable
  include PostVersionIndex

  def self.queue(post)
    self.create({
                    post_id: post.id,
                    rating: post.rating,
                    parent_id: post.parent_id,
                    source: post.source,
                    updater_id: CurrentUser.id,
                    updater_ip_addr: CurrentUser.ip_addr,
                    tags: post.tag_string,
                    locked_tags: post.locked_tags,
                    description: post.description
                })
  end

  def self.calculate_version(post_id)
    1 + where("post_id = ?", post_id).maximum(:version).to_i
  end

  def fill_version
    self.version = PostArchive.calculate_version (self.post_id)
  end

  def fill_changes
    prev = previous

    if prev
      self.added_tags = tag_array - prev.tag_array
      self.removed_tags = prev.tag_array - tag_array
      self.added_locked_tags = locked_tag_array - prev.locked_tag_array
      self.removed_locked_tags = prev.locked_tag_array - locked_tag_array
    else
      self.added_tags = tag_array
      self.removed_tags = []
      self.added_locked_tags = locked_tag_array
      self.removed_locked_tags = []
    end

    self.rating_changed = prev.nil? || rating != prev.try(:rating)
    self.parent_changed = prev.nil? || parent_id != prev.try(:parent_id)
    self.source_changed = prev.nil? || source != prev.try(:source)
    self.description_changed = prev.nil? || description != prev.try(:description)
  end

  def tag_array
    tags.split
  end

  def locked_tag_array
    (locked_tags || "").split
  end

  def presenter
    PostVersionPresenter.new(self)
  end

  def reload
    flush_cache
    super
  end

  def previous
    # HACK: if all the post versions for this post have already been preloaded,
    # we can use that to avoid a SQL query.
    if association(:post).loaded? && post && post.association(:versions).loaded?
      post.versions.sort_by(&:version).reverse.find {|v| v.version < version}
    else
      PostArchive.where("post_id = ? and version < ?", post_id, version).order("version desc").first
    end
  end

  def visible?
    post && post.visible?
  end

  def diff_sources(version = nil)
    new_sources = source.split("\n") || []
    old_sources = version&.source&.split("\n") || []

    added_sources = new_sources - old_sources
    removed_sources = old_sources - new_sources

    return {
        :added_sources => added_sources,
        :unchanged_sources => new_sources & old_sources,
        :removed_sources => removed_sources
    }
  end

  def diff(version = nil)
    if post.nil?
      latest_tags = tag_array
    else
      latest_tags = post.tag_array
      latest_tags << "rating:#{post.rating}" if post.rating.present?
      latest_tags << "parent:#{post.parent_id}" if post.parent_id.present?
    end

    new_tags = tag_array
    new_tags << "rating:#{rating}" if rating.present?
    new_tags << "parent:#{parent_id}" if parent_id.present?

    old_tags = version.present? ? version.tag_array : []
    if version.present?
      old_tags << "rating:#{version.rating}" if version.rating.present?
      old_tags << "parent:#{version.parent_id}" if version.parent_id.present?
    end

    added_tags = new_tags - old_tags
    removed_tags = old_tags - new_tags

    return {
        :added_tags => added_tags,
        :removed_tags => removed_tags,
        :obsolete_added_tags => added_tags - latest_tags,
        :obsolete_removed_tags => removed_tags & latest_tags,
        :unchanged_tags => new_tags & old_tags
    }
  end

  def changes
    delta = {
        :added_tags => added_tags,
        :removed_tags => removed_tags,
        :obsolete_removed_tags => [],
        :obsolete_added_tags => [],
        :unchanged_tags => []
    }

    return delta if post.nil?

    latest_tags = post.tag_array
    latest_tags << "rating:#{post.rating}" if post.rating.present?
    latest_tags << "parent:#{post.parent_id}" if post.parent_id.present?
    latest_tags << "source:#{post.source}" if post.source.present?

    if parent_changed
      if parent_id.present?
        delta[:added_tags] << "parent:#{parent_id}"
      end

      if previous
        delta[:removed_tags] << "parent:#{previous.parent_id}"
      end
    end

    if rating_changed
      delta[:added_tags] << "rating:#{rating}"

      if previous
        delta[:removed_tags] << "rating:#{previous.rating}"
      end
    end

    if source_changed
      if source.present?
        delta[:added_tags] << "source:#{source}"
      end

      if previous
        delta[:removed_tags] << "source:#{previous.source}"
      end
    end

    delta[:obsolete_added_tags] = delta[:added_tags] - latest_tags
    delta[:obsolete_removed_tags] = delta[:removed_tags] & latest_tags

    if previous
      delta[:unchanged_tags] = tag_array & previous.tag_array
    else
      delta[:unchanged_tags] = []
    end

    delta
  end

  def added_tags_with_fields
    changes[:added_tags].join(" ")
  end

  def removed_tags_with_fields
    changes[:removed_tags].join(" ")
  end

  def obsolete_added_tags
    changes[:obsolete_added_tags].join(" ")
  end

  def obsolete_removed_tags
    changes[:obsolete_removed_tags].join(" ")
  end

  def unchanged_tags
    changes[:unchanged_tags].join(" ")
  end

  def truncated_source
    source.gsub(/^http:\/\//, "").sub(/\/.+/, "")
  end

  def undo
    raise RevertError unless post.visible?

    added = changes[:added_tags] - changes[:obsolete_added_tags]
    removed = changes[:removed_tags] - changes[:obsolete_removed_tags]

    added.each do |tag|
      if tag =~ /^source:/
        post.source = ""
      elsif tag =~ /^parent:/
        post.parent_id = nil
      else
        escaped_tag = Regexp.escape(tag)
        post.tag_string = post.tag_string.sub(/(?:\A| )#{escaped_tag}(?:\Z| )/, " ").strip
      end
    end
    removed.each do |tag|
      if tag =~ /^source:(.+)$/
        post.source = $1
      else
        post.tag_string = "#{post.tag_string} #{tag}".strip
      end
    end
  end

  def undo!
    undo
    post.save!
  end

  def can_undo?(user)
    version > 1 && post&.visible? && user.is_member?
  end

  def can_revert_to?(user)
    post&.visible? && user.is_member?
  end

  def method_attributes
    super + [:obsolete_added_tags, :obsolete_removed_tags, :unchanged_tags, :updater_name]
  end

  memoize :previous, :tag_array, :changes, :added_tags_with_fields, :removed_tags_with_fields, :obsolete_removed_tags, :obsolete_added_tags, :unchanged_tags
end
