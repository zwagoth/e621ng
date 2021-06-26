require 'test_helper'

class PostReplacementTest < ActiveSupport::TestCase
  setup do
    Timecop.travel(2.weeks.ago) do
      @user = FactoryBot.create(:user)
      @mod_user = FactoryBot.create(:moderator_user)
    end
    @upload = UploadService.new(FactoryBot.attributes_for(:jpg_upload).merge(uploader: @mod_user, uploader_ip_addr: '127.0.0.1')).start!
    @post = @upload.post
    @post.update_columns({is_pending: false, approver_id: @mod_user.id})
    CurrentUser.user = @user
    CurrentUser.ip_addr = "127.0.0.1"
  end

  teardown do
    CurrentUser.user = nil
    CurrentUser.ip_addr = nil
  end

  context "User Limits:" do
    should "fail on too many per post in one day" do
      Danbooru.config.stubs(:post_replacement_per_day_limit).returns(-1)
      @replacement = @post.replacements.create(FactoryBot.attributes_for(:png_replacement).merge(creator: @user, creator_ip_addr: '127.0.0.1'))
      assert_equal ['Creator has already suggested too many replacements for this post today'], @replacement.errors.full_messages
    end

    should "fail on too many per post total" do
      Danbooru.config.stubs(:post_replacement_per_post_limit).returns(-1)
      @replacement = @post.replacements.create(FactoryBot.attributes_for(:png_replacement).merge(creator: @user, creator_ip_addr: '127.0.0.1'))
      assert_equal ['Creator has already suggested too many total replacements for this post'], @replacement.errors.full_messages
    end

    should "fail if user has no remaining upload limit" do
      User.any_instance.stubs(:upload_limit).returns(0)
      @replacement = @post.replacements.create(FactoryBot.attributes_for(:png_replacement).merge(creator: @user, creator_ip_addr: '127.0.0.1'))
      assert_equal ['Creator have reached your upload limit'], @replacement.errors.full_messages
    end

    should "fail if user has no remaining replacements" do
      User.any_instance.stubs(:can_replace_post_with_reason).returns(:REJ_LIMITED)
      @replacement = @post.replacements.create(FactoryBot.attributes_for(:png_replacement).merge(creator: @user, creator_ip_addr: '127.0.0.1'))
      assert_equal ['Creator have reached the hourly limit for this action'], @replacement.errors.full_messages
    end
  end

  context "Upload:" do
    should "allow non duplicate replacement submission" do
      @replacement = @post.replacements.create(FactoryBot.attributes_for(:png_replacement).merge(creator: @user, creator_ip_addr: '127.0.0.1'))
      assert_equal @replacement.errors.size, 0
      assert_equal @post.replacements.size, 1
      assert_equal @replacement.status, 'pending'
      assert @replacement.storage_id
      assert_equal Digest::MD5.file("#{Rails.root}/test/files/test.png").hexdigest, Digest::MD5.file(@replacement.replacement_file_path).hexdigest
    end

    should "not allow duplicate replacement submission" do
      @replacement = @post.replacements.create(FactoryBot.attributes_for(:jpg_replacement).merge(creator: @user, creator_ip_addr: '127.0.0.1'))
      assert_equal(["Md5 duplicate of existing post ##{@post.id}"], @replacement.errors.full_messages)
    end

    should "not allow duplicate of pending replacement submission" do
      @replacement = @post.replacements.create(FactoryBot.attributes_for(:png_replacement).merge(creator: @user, creator_ip_addr: '127.0.0.1'))
      assert_equal @replacement.errors.size, 0
      assert_equal @post.replacements.size, 1
      assert_equal @replacement.status, 'pending'
      assert @replacement.storage_id
      @new_replacement = @post.replacements.create(FactoryBot.attributes_for(:png_replacement).merge(creator: @user, creator_ip_addr: '127.0.0.1'))
      assert_equal(["Md5 duplicate of pending replacement on post ##{@post.id}"], @new_replacement.errors.full_messages)
    end

    should "not allow invalid or blank file replacements" do
      @replacement = @post.replacements.create(FactoryBot.attributes_for(:empty_replacement).merge(creator: @user, creator_ip_addr: '127.0.0.1'))
      assert_equal(["Unknown or invalid file format"], @replacement.errors.full_messages)
      @replacement = @post.replacements.create(FactoryBot.attributes_for(:jpg_invalid_replacement).merge(creator: @user, creator_ip_addr: '127.0.0.1'))
      assert_equal(["Unknown or invalid file format"], @replacement.errors.full_messages)
    end

    should "affect user upload limit" do
      assert_difference(->{PostReplacement.pending.for_user(@user.id).count}, 1) do
        @replacement = @post.replacements.create(FactoryBot.attributes_for(:png_replacement).merge(creator: @user, creator_ip_addr: '127.0.0.1'))
      end
    end
  end

  context "Reject:" do
    setup do
      @replacement = FactoryBot.create(:png_replacement, creator: @user, creator_ip_addr: '127.0.0.1', post: @post)
      assert @replacement
    end

    should "mark replacement as rejected" do
      @replacement.reject!
      assert_equal 'rejected', @replacement.status
    end

    should "allow duplicate replacement after rejection" do
      @replacement.reject!
      assert_equal 'rejected', @replacement.status
      @new_replacement = @post.replacements.create(FactoryBot.attributes_for(:png_replacement).merge(creator: @user, creator_ip_addr: '127.0.0.1'))
      assert @new_replacement.valid?
      assert_equal [], @new_replacement.errors.full_messages
    end

    should "create a mod action" do
      assert_difference("ModAction.count") do
        @replacement.reject!
      end
    end

    should "give user back their upload slot" do
      assert_difference(->{PostReplacement.pending.for_user(@user.id).count}, -1) do
        @replacement.reject!
      end
    end

    should "increment the users rejected replacements count" do
      assert_difference(->{@user.post_replacement_rejected_count}, 1) do
        assert_difference(->{PostReplacement.rejected.for_user(@user.id).count}, 1) do
          @replacement.reject!
          @user.reload
        end
      end
    end

    should "work only once for pending replacements" do
      @replacement.reject!
      assert_equal [], @replacement.errors.full_messages
      @replacement.reject!
      assert_equal ["Status must be pending to reject"], @replacement.errors.full_messages
    end
  end

  context "Approve:" do
    setup do
      @note = FactoryBot.create(:note, post: @post, x: 100, y: 200, width: 100, height: 50)
      @replacement = FactoryBot.create(:png_replacement, creator: @user, creator_ip_addr: '127.0.0.1', post: @post)
      assert @replacement
    end

    should "create a mod action" do
      assert_difference("ModAction.count") do
        @replacement.approve! penalize_current_uploader: true
      end
    end

    should "fail if post cannot be backed up" do
      @post.md5 = "123" # Breaks file path, should force backup to fail.
      assert_raise(ProcessingError) do
        @replacement.approve! penalize_current_uploader: true
      end
    end


    should "update post with new image" do
      old_md5 = @post.md5
      @replacement.approve! penalize_current_uploader: true
      @post.reload
      assert_not_equal @post.md5, old_md5
      assert_equal @replacement.image_width, @post.image_width
      assert_equal @replacement.image_height, @post.image_height
      assert_equal @replacement.md5, @post.md5
      assert_equal @replacement.creator_id, @post.uploader_id
      assert_equal @replacement.file_ext, @post.file_ext
      assert_equal @replacement.file_size, @post.file_size
    end

    should "generate videos samples if replacement is video" do
      @replacement = FactoryBot.create(:webm_replacement, creator: @user, creator_ip_addr: '127.0.0.1', post: @post)
      @post.expects(:generate_video_samples).times(1)
      @replacement.approve! penalize_current_uploader: true
    end

    should "delete original files immediately" do
      sm = Danbooru.config.storage_manager
      old_md5 = @post.md5
      old_ext = @post.file_ext
      @replacement.approve! penalize_current_uploader: true
      @post.reload
      assert_not File.exist?(sm.file_path(old_md5, old_ext, :original))
      assert_not File.exist?(sm.file_path(old_md5, old_ext, :preview))
      assert_not File.exist?(sm.file_path(old_md5, old_ext, :large))
      assert_not File.exist?(sm.file_path(old_md5, old_ext, :original, protected=true))
    end

    should "not be able to approve on deleted post" do
      @post.update_column(:is_deleted, true)
      assert_raise ProcessingError do
        @replacement.approve! penalize_current_uploader: true
      end
    end

    should "create backup replacement" do
      old_md5 = @post.md5
      old_source = @post.source
      assert_difference("@post.replacements.size", 1) do
        @replacement.approve! penalize_current_uploader: true
      end
      new_replacement = @post.replacements.last
      assert_equal 'original', new_replacement.status
      assert_equal old_md5, new_replacement.md5
      assert_equal old_source, new_replacement.source
      assert_equal old_md5, Digest::MD5.file(new_replacement.replacement_file_path).hexdigest
    end

    should "update users upload counts" do
      assert_difference(->{Post.for_user(@mod_user.id).where('is_flagged = false AND is_deleted = false AND is_pending = false').count}, -1) do
        assert_difference(->{Post.for_user(@user.id).where('is_flagged = false AND is_deleted = false AND is_pending = false').count}, 1) do
          @replacement.approve! penalize_current_uploader: true
        end
      end
    end

    should "update the original users upload limit if penalized" do
      assert_difference(->{@mod_user.own_post_replaced_count}, 1) do
        assert_difference(->{@mod_user.own_post_replaced_penalize_count}, 1) do
          assert_difference(->{PostReplacement.penalized.for_uploader_on_approve(@mod_user.id).count}, 1) do
            @replacement.approve! penalize_current_uploader: true
            @mod_user.reload
          end
        end
      end
    end

    should "not update the original users upload limit if not penalizing" do
      assert_difference(-> {@mod_user.own_post_replaced_count}, 1) do
        assert_difference(->{@mod_user.own_post_replaced_penalize_count}, 0) do
          assert_difference(->{PostReplacement.not_penalized.for_uploader_on_approve(@mod_user.id).count}, 1) do
            @replacement.approve! penalize_current_uploader: false
            @mod_user.reload
          end
        end
      end
    end

    should "correctly resize the posts notes" do
      @replacement.approve! penalize_current_uploader: true
      @note.reload
      assert_equal 153, @note.x
      assert_equal 611, @note.y
      assert_equal 153, @note.width
      assert_equal 152, @note.height
    end

    should "only work on pending or original replacements" do
      @replacement.reject!
      @replacement.approve! penalize_current_uploader: false
      assert_equal(["Status must be pending or original to approve"], @replacement.errors.full_messages)
    end

    should "only work once" do
      @replacement.approve! penalize_current_uploader: false
      assert_equal [], @replacement.errors.full_messages
      @replacement.approve! penalize_current_uploader: false
      assert_equal ["Status must be pending or original to approve"], @replacement.errors.full_messages
    end
  end

  context "Toggle:" do
    setup do
      @replacement = FactoryBot.create(:png_replacement, creator: @user, creator_ip_addr: '127.0.0.1', post: @post)
      assert @replacement
    end

    should "change the users upload limit" do
      @replacement.approve! penalize_current_uploader: false
      assert_difference(->{@mod_user.own_post_replaced_penalize_count}, 1) do
        assert_difference(->{PostReplacement.penalized.for_uploader_on_approve(@mod_user.id).count}, 1) do
          @replacement.toggle_penalize!
          @mod_user.reload
        end
      end
    end

    should "only work on appoved replacements" do
      @replacement.toggle_penalize!
      assert_equal(["Status must be approved to penalize"], @replacement.errors.full_messages)
    end
  end

  context "Promote:" do
    setup do
      @replacement = FactoryBot.create(:png_replacement, creator: @user, creator_ip_addr: '127.0.0.1', post: @post)
      assert @replacement
    end

    should "create a new post with replacement contents" do
      post = @replacement.promote!
      assert post
      assert_equal [], post.errors.full_messages
      assert_equal [], post.post.errors.full_messages
      assert_equal 'promoted', @replacement.status
      assert_equal post.md5, @replacement.md5
      assert_equal post.file_ext, @replacement.file_ext
      assert_equal post.image_width, @replacement.image_width
      assert_equal post.image_height, @replacement.image_height
      assert_equal post.tag_string.strip, @replacement.post.tag_string.strip
      assert_equal post.parent_id, @replacement.post_id
      assert_equal post.file_size, @replacement.file_size
    end

    should "credit replacer with new post" do
      assert_difference(->{Post.for_user(@mod_user.id).where('is_flagged = false AND is_deleted = false AND is_pending = false').count}, 0) do
        assert_difference(->{Post.for_user(@user.id).where('is_flagged = false AND is_deleted = false').count}, 1) do
          post = @replacement.promote!
          assert post
          assert_equal [], post.errors.full_messages
          assert_equal [], post.post.errors.full_messages
        end
      end
    end

    should "only work on pending replacements" do
      @replacement.approve! penalize_current_uploader: false
      @replacement.promote!
      assert_equal(["Status must be pending to promote"], @replacement.errors.full_messages)
    end
  end
end
