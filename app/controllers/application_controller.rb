class ApplicationController < ActionController::Base
  class APIThrottled < Exception; end

  skip_forgery_protection if: -> { SessionLoader.new(request).has_api_authentication? || request.options? }
  before_action :reset_current_user
  before_action :set_current_user
  before_action :normalize_search
  before_action :api_check
  before_action :set_variant
  before_action :enable_cors
  after_action :reset_current_user
  layout "default"

  include TitleHelper
  include DeferredPosts
  helper_method :deferred_post_ids, :deferred_posts

  rescue_from Exception, :with => :rescue_exception
  rescue_from User::PrivilegeError, :with => :access_denied
  rescue_from ActionController::UnpermittedParameters, :with => :access_denied

  # This is raised on requests to `/blah.js`. Rails has already rendered StaticController#not_found
  # here, so calling `rescue_exception` would cause a double render error.
  rescue_from ActionController::InvalidCrossOriginRequest, with: -> {}

  def enable_cors
    response.headers["Access-Control-Allow-Origin"] = "*"
    response.headers["Access-Control-Allow-Headers"] = "Authorization"
  end

  protected

  def self.rescue_with(*klasses, status: 500)
    rescue_from *klasses do |exception|
      render_error_page(status, exception)
    end
  end

  def api_check
    if !CurrentUser.is_anonymous? && !request.get? && !request.head?
      throttled = CurrentUser.user.token_bucket.throttled?
      headers["X-Api-Limit"] = CurrentUser.user.token_bucket.cached_count.to_s

      if throttled
        raise APIThrottled.new
        return false
      end
    end

    true
  end

  def rescue_exception(exception)
    @exception = exception

    if Rails.env.test? && ENV["DEBUG"]
      puts "---"
      STDERR.puts("#{exception.class} exception thrown: #{exception.message}")
      exception.backtrace.each {|x| STDERR.puts(x)}
      puts "---"
    end

    case exception
    when ProcessingError
      render_expected_error(400, exception)
    when APIThrottled
      render_expected_error(429, "Throttled: Too many requests")
    when ActiveRecord::QueryCanceled
      render_error_page(500, exception, message: "The database timed out running your query.")
    when ActionController::BadRequest
      render_error_page(400, exception)
    when SessionLoader::AuthenticationFailure
      session.delete(:user_id)
      cookies.delete :remember
      render_expected_error(401, exception.message)
    when ActionController::InvalidAuthenticityToken
      render_error_page(403, exception)
    when ActiveRecord::RecordNotFound
      render_404
    when ActionController::RoutingError
      render_error_page(405, exception)
    when ActionController::UnknownFormat, ActionView::MissingTemplate
      render_error_page(406, exception, message: "#{request.format.to_s} is not a supported format for this page", format: :html)
    when Danbooru::Paginator::PaginationError
      render_expected_error(410, exception.message)
    when Post::SearchError
      render_expected_error(422, exception.message)
    when NotImplementedError
      render_error_page(501, exception, message: "This feature isn't available: #{exception.message}")
    when PG::ConnectionBad
      render_error_page(503, exception, message: "The database is unavailable. Try again later.")
    when ActionController::ParameterMissing
      render_expected_error(400, exception.message)
    else
      render_error_page(500, exception)
    end
  end

  def render_404
    respond_to do |fmt|
        fmt.html do
          render "static/404", formats: [:html, :atom], status: 404
        end
        fmt.json do
          render json: {:success => false, reason: "not found"}, :status => 404
        end
        fmt.atom do
          render "static/404", formats: [:atom], status: 404
        end
    end
  end

  def render_expected_error(status, message, format: request.format.symbol)
    format = :html unless format.in?(%i[html json atom])
    layout = CurrentUser.user.present? ? "default" : "blank"
    @message = message
    render "static/error", layout: layout, status: status, formats: format
  end

  def render_error_page(status, exception, message: exception.message, format: request.format.symbol)
    @exception = exception
    @expected = status < 500
    @message = message.encode("utf-8", invalid: :replace, undef: :replace )
    @backtrace = Rails.backtrace_cleaner.clean(@exception.backtrace)
    format = :html unless format.in?(%i[html json atom])

    # if InvalidAuthenticityToken was raised, CurrentUser isn't set so we have to use the blank layout.
    layout = CurrentUser.user.present? ? "default" : "blank"

    if !CurrentUser.user&.try(:is_janitor?) && message == exception.message
      @message = "An unexpected error occurred."
    end


    DanbooruLogger.log(@exception, expected: @expected)
    log_params = {
        host: Socket.gethostname,
        params: request.filtered_parameters,
        user_id: CurrentUser.id,
        referrer: request.referrer,
        user_agent: request.user_agent
    }
    # Required to unwrap exceptions that occur inside template rendering.
    new_exception = exception
    if exception.respond_to?(:cause) && exception.is_a?(ActionView::Template::Error)
      new_exception = exception.cause
    end
    if new_exception&.is_a?(ActiveRecord::QueryCanceled)
      log_params[:sql] = {}
      log_params[:sql][:query] = new_exception&.sql || "[NOT FOUND?]"
      log_params[:sql][:binds] = new_exception&.binds
    end
    log = ExceptionLog.add(exception, CurrentUser.ip_addr, log_params) if !@expected
    @log_code = log&.code
    render "static/error", layout: layout, status: status, formats: format
  end

  def access_denied(exception = nil)
    previous_url = params[:url] || request.fullpath
    @message = "Access Denied: #{exception}" if exception.is_a?(String)
    @message ||= exception&.message || "Access Denied"

    respond_to do |fmt|
      fmt.html do
        if CurrentUser.is_anonymous?
          if request.get?
            redirect_to new_session_path(:url => previous_url), notice: @message
          else
            redirect_to new_session_path, notice: @message
          end
        else
          render :template => "static/access_denied", :status => 403
        end
      end
      fmt.json do
        render :json => {:success => false, reason: @message}.to_json, :status => 403
      end
    end
  end

  def set_current_user
    SessionLoader.new(request).load
  end

  def reset_current_user
    CurrentUser.user = nil
    CurrentUser.ip_addr = nil
    CurrentUser.safe_mode = Danbooru.config.safe_mode
    CurrentUser.root_url = root_url.chomp("/")
  end

  def set_variant
    request.variant = params[:variant].try(:to_sym)
  end

  User::Roles.each do |role|
    define_method("#{role}_only") do
      if !CurrentUser.user.send("is_#{role}?") || CurrentUser.user.is_banned? || IpBan.is_banned?(CurrentUser.ip_addr)
        access_denied
      end
    end
  end

  def logged_in_only
    if CurrentUser.is_anonymous?
      access_denied("Must be logged in")
    end
  end

  # Remove blank `search` params from the url.
  #
  # /tags?search[name]=touhou&search[category]=&search[order]=
  # => /tags?search[name]=touhou
  def normalize_search
    return unless request.get?
    params[:search] ||= ActionController::Parameters.new

    deep_reject_blank = lambda do |hash|
      hash.reject { |k, v| v.blank? || (v.is_a?(Hash) && deep_reject_blank.call(v).blank?) }
    end
    nonblank_search_params = deep_reject_blank.call(params[:search])

    if nonblank_search_params != params[:search]
      params[:search] = nonblank_search_params
      redirect_to url_for(params: params.except(:controller, :action, :index).permit!)
    end
  end

  def search_params
    params.fetch(:search, {}).permit!
  end
end
