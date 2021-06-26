require 'test_helper'

class PostReplacementsControllerTest < ActionDispatch::IntegrationTest

  setup do
    Sidekiq::Testing.inline!
  end

  teardown do
    Sidekiq::Testing.fake!
  end

  context "The post replacements controller" do
    setup do
      @user = create(:moderator_user, can_approve_posts: true, created_at: 1.month.ago)
      @user.as_current do
        @upload = UploadService.new(FactoryBot.attributes_for(:jpg_upload).merge({uploader: @user})).start!
        @post = @upload.post
        @replacement = create(:png_replacement, creator: @user, post: @post)
      end
    end

    context "create action" do
      should "accept new non duplicate replacement" do
        file = Rack::Test::UploadedFile.new("#{Rails.root}/test/files/alpha.png", "image/png")
        params = {
          post_id: @post.id,
          post_replacement: {
            replacement_file: file,
            reason: 'test replacement'
          }
        }

        assert_difference(-> { @post.replacements.size }) do
          post_auth post_replacements_path, @user, params: params
          @post.reload
        end

        assert_redirected_to post_path(@post)
      end
    end

    context "reject action" do
      should "reject replacement" do
        put_auth reject_post_replacement_path(@replacement), @user
        assert_redirected_to post_path(@post)
        @replacement.reload
        @post.reload
        assert_equal @replacement.status, "rejected"
        assert_not_equal @post.md5, @replacement.md5
      end
    end

    context "approve action" do
      should "replace post" do
        put_auth approve_post_replacement_path(@replacement), @user
        assert_redirected_to post_path(@post)
        @replacement.reload
        @post.reload
        assert_equal @replacement.md5, @post.md5
        assert_equal @replacement.status, "approved"
      end
    end

    context "promote action" do
      should "create post" do
        post_auth promote_post_replacement_path(@replacement), @user
        last_post = Post.last
        assert_redirected_to post_path(last_post)
        @replacement.reload
        @post.reload
        assert_equal @replacement.md5, last_post.md5
        assert_equal @replacement.status, "promoted"
      end
    end

    context "toggle action" do
      should "change penalize_uploader flag" do
        put_auth approve_post_replacement_path(@replacement, penalize_current_uploader: true), @user
        @replacement.reload
        assert @replacement.penalize_uploader_on_approve
        put_auth toggle_penalize_post_replacement_path(@replacement), @user
        assert_redirected_to post_replacement_path(@replacement)
        @replacement.reload
        assert !@replacement.penalize_uploader_on_approve
      end
    end

    context "index action" do
      should "render" do
        get post_replacements_path
        assert_response :success
      end
    end

    context "new action" do
      should "render" do
        get_auth new_post_replacement_path, @user, params: {post_id: @post.id}
        assert_response :success
      end
    end
  end
end
