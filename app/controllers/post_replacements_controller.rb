class PostReplacementsController < ApplicationController
  respond_to :html
  before_action :moderator_only, only: [:destroy]
  before_action :janitor_only, only: [:create, :new, :approve, :reject, :promote]
  content_security_policy only: [:new] do |p|
    p.img_src :self, :data, "*"
  end

  def new
    @post = Post.find(params[:post_id])
    @post_replacement = @post.replacements.new
    respond_with(@post_replacement)
  end

  def create
    @post = Post.find(params[:post_id])
    @post_replacement = @post.replacements.create(create_params.merge(creator_id: CurrentUser.id, creator_ip_addr: CurrentUser.ip_addr))
    if @post_replacement.errors.size == 0
      flash[:notice] = "Post replacement submitted"
    else
      flash[:notice] = @post_replacement.errors.full_messages.join('; ')
    end
    respond_with(@post_replacement, location: @post)
  end

  def approve
    @post_replacement = PostReplacement.find(params[:id])
    @post_replacement.approve!(penalize_current_uploader: params[:penalize_current_uploader])

    respond_with(@post_replacement, location: post_path(@post_replacement.post))
  end

  def reject
    @post_replacement = PostReplacement.find(params[:id])
    @post_replacement.reject!

    respond_with(@post_replacement)
  end

  def destroy
    @post_replacement = PostReplacement.find(params[:id])
    @post_replacement.destroy

    respond_with(@post_replacement)
  end

  def promote
    @post_replacement = PostReplacement.find(params[:id])
    @post = @post_replacement.promote!
    if @post.errors.any?
      respond_with(@post)
    else
      respond_with(@post.post)
    end
  end

  def index
    params[:search][:post_id] = params.delete(:post_id) if params.has_key?(:post_id)
    @post_replacements = PostReplacement.includes(:post).visible(CurrentUser.user).search(search_params).paginate(params[:page], limit: params[:limit])

    respond_with(@post_replacements)
  end

private
  def create_params
    params.require(:post_replacement).permit(:replacement_url, :replacement_file, :reason, :source)
  end
end
