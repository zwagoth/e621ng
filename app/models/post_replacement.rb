class PostReplacement < ApplicationRecord
  self.table_name = 'post_replacements2'
  belongs_to :post
  belongs_to :creator, class_name: "User"
  belongs_to :approver, class_name: "User", optional: true
  attr_accessor :replacement_file, :replacement_url, :final_source, :tags, :is_backup

  validate :user_is_not_limited, on: :create
  validate :post_is_valid, on: :create
  validate :set_file_name, on: :create
  validate :fetch_source_file, on: :create
  validate :update_file_attributes, on: :create
  validate :no_pending_duplicates, on: :create
  validate :write_storage_file, on: :create

  before_destroy :remove_files

  def replacement_url_parsed
    return nil unless replacement_url =~ %r!\Ahttps?://!i
    Addressable::URI.heuristic_parse(replacement_url) rescue nil
  end

  module PostMethods
    def post_is_valid
      if post.is_deleted?
        self.errors.add(:post, "is deleted")
        return false
      end
    end
  end

  module FileMethods
    def is_image?
      %w(jpg jpeg gif png).include?(file_ext)
    end

    def is_flash?
      %w(swf).include?(file_ext)
    end

    def is_video?
      %w(webm).include?(file_ext)
    end

    def is_ugoira?
      %w(zip).include?(file_ext)
    end
  end

  def no_pending_duplicates
    return true if is_backup
    post = Post.where(md5: md5).first
    if post
      self.errors.add(:md5, "duplicate of existing post ##{post.id}")
      return false
    end
    replacements = PostReplacement.where(status: 'pending', md5: md5)
    replacements.each do |replacement|
      self.errors.add(:md5, "duplicate of pending replacement on post ##{replacement.post_id}")
    end
    replacements.size == 0
  end

  def user_is_not_limited
    return true if status == 'original'
    replaceable = creator.can_replace_post_with_reason
    if replaceable != true
      self.errors.add(:creator, User.throttle_reason(replaceable))
      return false
    end
    uploadable = creator.can_upload_with_reason
    if uploadable != true
      self.errors.add(:creator, User.upload_reason_string(uploadable))
      return false
    end

    # Janitor bypass replacement limits
    return true if creator.is_janitor?

    if post.replacements.where(creator_id: creator.id).where('created_at > ?', 1.day.ago).count >= Danbooru.config.post_replacement_per_day_limit
      self.errors.add(:creator, 'has already suggested too many replacements for this post today')
      return false
    end
    if post.replacements.where(creator_id: creator.id).count >= Danbooru.config.post_replacement_per_post_limit
      self.errors.add(:creator, 'has already suggested too many total replacements for this post')
      return false
    end
    true
  end

  def source_list
    source.split("\n").uniq.reject(&:blank?)
  end

  module StorageMethods
    def remove_files
      ModAction.log(:post_replacement_delete, {id: id, post_id: post_id, md5: md5, storage_id: storage_id})
      Danbooru.config.storage_manager.delete_replacement(self)
    end

    def fetch_source_file
      return if replacement_file.present?

      download = Downloads::File.new(replacement_url_parsed, "")
      file, strategy = download.download!

      self.replacement_file = file
      self.source = replacement_url + "\n#{self.source}"
    rescue Downloads::File::Error
      self.errors.add(:replacement_url, "failed to fetch file")
      throw :abort
    end

    def update_file_attributes
      self.file_ext = UploadService::Utils.file_header_to_file_ext(replacement_file)
      if file_ext == "bin"
        self.errors.add(:base, "Unknown or invalid file format")
        throw :abort
      end
      self.file_size = replacement_file.size
      self.md5 = Digest::MD5.file(replacement_file.path).hexdigest

      UploadService::Utils.calculate_dimensions(self, replacement_file) do |width, height|
        self.image_width = width
        self.image_height = height
      end
    end

    def set_file_name
      if replacement_file.present?
        self.file_name = replacement_file.try(:original_filename) || File.basename(replacement_file.path)
      else
        if replacement_url_parsed.blank?
          self.errors.add(:base, "No file or source URL provided")
          throw :abort
        end
        self.file_name = replacement_url_parsed.basename
      end
    end

    def write_storage_file
      self.storage_id = SecureRandom.hex(16)
      Danbooru.config.storage_manager.store_replacement(replacement_file, self, :original)
      thumbnail_file = PostThumbnailer.generate_thumbnail(replacement_file, is_video? ? :video : :image)
      Danbooru.config.storage_manager.store_replacement(thumbnail_file, self, :preview)
    ensure
      thumbnail_file.try(:close!)
    end

    def replacement_file_path
      Danbooru.config.storage_manager.replacement_path(self, file_ext, :original)
    end

    def replacement_thumb_path
      Danbooru.config.storage_manager.replacement_path(self, file_ext, :preview)
    end

    def replacement_file_url
      Danbooru.config.storage_manager.replacement_url(self)
    end

    def replacement_thumb_url
      Danbooru.config.storage_manager.replacement_url(self, :preview)
    end
  end

  module ApiMethods
    def hidden_attributes
      super + [:storage_id]
    end
  end

  module ProcessingMethods
    def approve!(penalize_current_uploader:)
      transaction do
        ModAction.log(:post_replacement_accept, {post_id: post.id, replacement_id: self.id, old_md5: post.md5, new_md5: self.md5})
        processor = UploadService::Replacer.new(post: post, replacement: self)
        processor.process!(penalize_current_uploader: penalize_current_uploader)
      end
    end

    def promote!
      transaction do
        processor = UploadService.new(new_upload_params)
        new_post = processor.start!
        update_attribute(:status, 'promoted')
        new_post
      end
    end

    def reject!
      ModAction.log(:post_replacement_reject, {post_id: post.id, replacement_id: self.id})
      update_attribute(:status, 'rejected')
      UserStatus.for_user(creator_id).update_all("post_replacement_rejected_count = post_replacement_rejected_count + 1")
    end
  end

  module PromotionMethods
    def new_upload_params
      {
          uploader_id: creator_id,
          uploader_ip_addr: creator_ip_addr,
          file: Danbooru.config.storage_manager.open(Danbooru.config.storage_manager.replacement_path(self, file_ext, :original)),
          tag_string: post.tag_string,
          rating: post.rating,
          source: "#{self.source}\n" + post.source,
          parent_id: post.id,
          description: post.description,
          locked_tags: post.locked_tags,
          replacement_id: self.id
      }
    end
  end

  concerning :Search do
    class_methods do
      def search(params = {})
        q = super

        q = q.attribute_exact_matches(:file_ext, params[:file_ext])
        q = q.attribute_exact_matches(:md5, params[:md5])
        q = q.attribute_exact_matches(:status, params[:status])

        if params[:creator_id].present?
          q = q.where(creator_id: params[:creator_id].split(",").map(&:to_i))
        end

        if params[:creator_name].present?
          q = q.where(creator_id: User.name_to_id(params[:creator_name]))
        end

        if params[:uploader_id_on_approve].present?
          q = q.where(uploader_id_on_approve: params[:uploader_id_on_approve].split(",").map(&:to_i))
        end

        if params[:uploader_name_on_approve].present?
          q = q.where(uploader_id_on_approve: User.name_to_id(params[:uploader_name_on_approve]))
        end

        if params[:post_id].present?
          q = q.where(post_id: params[:post_id].split(",").map(&:to_i))
        end


        q.order(Arel.sql("CASE status WHEN 'pending' THEN 0 ELSE 1 END ASC, id DESC"))
      end

      def pending
        where(status: 'pending')
      end

      def rejected
        where(status: 'rejected')
      end

      def approved
        where(status: 'approved')
      end

      def for_user(id)
        where(creator_id: id.to_i)
      end

      def visible(user)
        return where('status != ?', 'rejected') if user.is_anonymous?
        return all if user.is_janitor?
        where('creator_id = ? or status != ?', user.id, 'rejected')
      end
    end
  end

  def file_visible_to?(user)
    return true if user.is_janitor?
    false
  end

  include ApiMethods
  include StorageMethods
  include FileMethods
  include ProcessingMethods
  include PromotionMethods
  include PostMethods

end
