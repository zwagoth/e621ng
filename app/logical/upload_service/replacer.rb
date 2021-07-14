class UploadService
  class Replacer
    extend Memoist

    attr_reader :post, :replacement

    def initialize(post:, replacement:)
      @post = post
      @replacement = replacement
    end

    def find_replacement_url(repl, upload)
      if repl.replacement_file.present?
        return "file://#{repl.file_name}"
      end

      if !upload.source.present?
        raise ProcessingError "No source found in upload for replacement"
      end

      return upload.source
    end

    def create_backup_replacement
      begin
        repl = post.replacements.new(creator_id: post.uploader_id, creator_ip_addr: post.uploader_ip_addr, status: 'original',
                                     image_width: post.image_width, image_height: post.image_height, file_ext: post.file_ext,
                                     file_size: post.file_size, md5: post.md5, file_name: "#{post.md5}.#{post.file_ext}",
                                     source: post.source, reason: 'Backup of original file', is_backup: true)
        repl.replacement_file = Danbooru.config.storage_manager.open(Danbooru.config.storage_manager.file_path(post, post.file_ext, :original))
        repl.save
      rescue Exception => e
        raise ProcessingError, "Failed to create post file backup: #{e.message}"
      end
      raise ProcessingError, "Could not create post file backup?" if !repl.valid?
    end

    def process!(penalize_current_uploader:)
      # Prevent trying to replace deleted posts
      raise ProcessingError, "Cannot replace post: post is deleted." if post.is_deleted?

      create_backup_replacement
      replacement.replacement_file = Danbooru.config.storage_manager.open(Danbooru.config.storage_manager.replacement_path(replacement, replacement.file_ext, :original))

      upload = Upload.create(
          uploader_id: CurrentUser.id,
          uploader_ip_addr: CurrentUser.ip_addr,
          rating: post.rating,
          tag_string: post.tag_string,
          source: replacement.source,
          file: replacement.replacement_file,
          replaced_post: post,
          original_post_id: post.id,
          replacement_id: replacement.id
      )

      begin
        if upload.invalid? || upload.is_errored?
          raise ProcessingError, upload.status
        end

        upload.update(status: "processing")

        upload.file = Utils.get_file_for_upload(upload, file: upload.file)
        Utils.process_file(upload, upload.file, original_post_id: post.id)

        upload.save!
      rescue Exception => x
        upload.update(status: "error: #{x.class} - #{x.message}", backtrace: x.backtrace.join("\n"))
        raise ProcessingError, upload.status
      end
      md5_changed = upload.md5 != post.md5

      if md5_changed
        post.delete_files
        post.generated_samples = nil
      end

      previous_uploader = post.uploader_id

      post.md5 = upload.md5
      post.file_ext = upload.file_ext
      post.image_width = upload.image_width
      post.image_height = upload.image_height
      post.file_size = upload.file_size
      post.source = "#{replacement.source}\n" + post.source
      post.tag_string = upload.tag_string
      # Reset ownership information on post.
      post.uploader_id = replacement.creator_id
      post.uploader_ip_addr = replacement.creator_ip_addr
      post.save!


      # rescaling notes reloads the post, be careful when accessing previous values
      rescale_notes(post)
      update_ugoira_frame_data(post, upload)

      replacement.update({
                           status: 'approved',
                           approver_id: CurrentUser.id,
                           uploader_id_on_approve: previous_uploader,
                           penalize_uploader_on_approve: penalize_current_uploader.to_s.truthy?
                         })

      UserStatus.for_user(previous_uploader).update_all("own_post_replaced_count = own_post_replaced_count + 1")
      if penalize_current_uploader.to_s.truthy?
        UserStatus.for_user(previous_uploader).update_all("own_post_replaced_penalize_count = own_post_replaced_penalize_count + 1")
      end

      if post.is_video?
        post.generate_video_samples(later: true)
      end

      post.update_iqdb_async
    end

    def rescale_notes(post)
      x_scale = post.image_width.to_f / post.image_width_before_last_save.to_f
      y_scale = post.image_height.to_f / post.image_height_before_last_save.to_f

      post.notes.each do |note|
        note.rescale!(x_scale, y_scale)
      end
    end

    def update_ugoira_frame_data(post, upload)
      post.pixiv_ugoira_frame_data.destroy if post.pixiv_ugoira_frame_data.present?

      unless post.is_ugoira?
        return
      end

      PixivUgoiraFrameData.create(
          post_id: post.id,
          data: upload.context["ugoira"]["frame_data"],
          content_type: upload.context["ugoira"]["content_type"]
      )
    end
  end
end
