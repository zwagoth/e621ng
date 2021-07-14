Rails.application.routes.draw do

  require 'sidekiq/web'
  require 'sidekiq_unique_jobs/web'

  mount Sidekiq::Web => '/sidekiq', constraints: AdminRouteConstraint.new

  namespace :admin do
    resources :users, :only => [:edit, :update, :edit_blacklist, :update_blacklist, :alt_list] do
      member do
        get :edit_blacklist
        post :update_blacklist
        get :request_password_reset
        post :password_reset
      end
      collection do
        get :alt_list
      end
    end
    resource :alias_and_implication_import, :only => [:new, :create]
    resource :dashboard, :only => [:show]
    resources :exceptions, only: [:index, :show]
    resource :reowner, controller: 'reowner', only: [:new, :create]
    resources :staff_notes, only: [:index]
  end
  resources :edit_histories
  namespace :moderator do
    resource :dashboard, :only => [:show]
    resources :ip_addrs, :only => [:index] do
      collection do
        get :search
      end
    end
    resources :invitations, :only => [:new, :create, :index]
    resource :tag, :only => [:edit, :update]
    namespace :post do
      resource :queue, :only => [:show] do
        member do
          get :random
        end
      end
      resource :approval, :only => [:create, :destroy]
      resources :disapprovals, :only => [:create, :index]
      resources :posts, :only => [:delete, :undelete, :expunge, :confirm_delete] do
        member do
          get :confirm_delete
          post :expunge
          post :delete
          post :undelete
          get :confirm_move_favorites
          post :move_favorites
          get :confirm_ban
          post :ban
          post :unban
          post :regenerate_thumbnails
          post :regenerate_videos
        end
      end
    end
    resources :invitations, :only => [:new, :create, :index, :show]
    resources :ip_addrs, :only => [:index, :search] do
      collection do
        get :search
      end
    end
  end
  namespace :explore do
    resources :posts, :only => [] do
      collection do
        get :popular
        get :searches
        get :missed_searches
        get :intro
      end
    end
  end
  namespace :maintenance do
    namespace :user do
      resource :count_fixes, only: [:new, :create]
      resource :email_notification, :only => [:show, :destroy]
      resource :password_reset, :only => [:new, :create, :edit, :update]
      resource :login_reminder, :only => [:new, :create]
      resource :deletion, :only => [:show, :destroy]
      resource :email_change, :only => [:new, :create]
      resource :dmail_filter, :only => [:edit, :update]
      resource :api_key, :only => [:show, :view, :update, :destroy] do
        post :view
      end
    end
  end

  resources :tickets do
    member do
      post :claim
      post :unclaim
    end
  end

  resources :takedowns do
    collection do
      post :count_matching_posts
    end
    member do
      post :add_by_ids
      post :add_by_tags
      post :remove_by_ids
    end
  end

  resources :artists do
    member do
      put :revert
      put :ban
      put :unban
    end
    collection do
      get :show_or_new
      get :banned
    end
  end
  resources :artist_urls, only: [:index, :update]
  resources :artist_versions, :only => [:index] do
    collection do
      get :search
    end
  end
  resources :bans
  resources :bulk_update_requests do
    member do
      post :approve
    end
  end
  resources :comments do
    resource :votes, :controller => "comment_votes", :only => [:create, :destroy]
    collection do
      get :search
    end
    member do
      post :hide
      post :unhide
      post :warning
    end
  end
  resources :comment_votes, only: [:index, :delete, :lock] do
    collection do
      post :lock
      post :delete
    end
  end
  resources :delayed_jobs, :only => [:index, :destroy] do
    member do
      put :run
      put :retry
      put :cancel
    end
  end
  resources :dmails, :only => [:new, :create, :index, :show, :destroy] do
    member do
      post :spam
      post :ham
    end
    collection do
      post :mark_all_as_read
    end
  end
  resource :dtext_preview, :only => [:create]
  resources :favorites, :only => [:index, :create, :destroy]
  resources :forum_posts do
    resource :votes, controller: "forum_post_votes"
    member do
      post :hide
      post :unhide
      post :warning
    end
    collection do
      get :search
    end
  end
  resources :forum_topics do
    member do
      post :hide
      post :unhide
      get :new_merge
      post :create_merge
      post :subscribe
      post :unsubscribe
    end
    collection do
      post :mark_all_as_read
    end
    resource :visit, :controller => "forum_topic_visits"
  end
  resources :forum_categories
  resources :help_pages, controller: "help", path: "help"
  resources :ip_bans
  resources :upload_whitelists do
    collection do
      get :is_allowed
    end
  end
  resources :email_blacklists
  resource :iqdb_queries, :only => [:show] do
    collection do
      post :show
      get :preview
      get :check, to: redirect {|path_params, req| "/iqdb_queries?#{req.query_string}"}
    end
  end
  resources :janitor_trials do
    collection do
      get :test
    end
    member do
      put :promote
      put :demote
    end
  end
  resources :mod_actions
  resources :news_updates
  resources :notes do
    collection do
      get :search
    end
    member do
      put :revert
    end
  end
  resources :note_versions, :only => [:index]
  resource :note_previews, :only => [:show]
  resources :pools do
    member do
      put :revert
      post :undelete
      get :import
      get :import_preview
      post :import_posts
    end
    collection do
      get :gallery
    end
    resource :order, :only => [:edit], :controller => "pool_orders"
  end
  resource :pool_element, :only => [:create, :destroy] do
    collection do
      get :all_select
    end
  end
  resources :pool_versions, :only => [:index] do
    member do
      get :diff
    end
  end
  resources :post_replacements, :only => [:index, :new, :create, :destroy] do
    member do
      put :approve
      put :reject
      put :promote
    end
  end
  resources :deleted_posts, only: [:index]
  resources :posts, :only => [:index, :show, :update] do
    resources :events, :only => [:index], :controller => "post_events"
    resources :replacements, :only => [:index, :new, :create], :controller => "post_replacements"
    resource :votes, :controller => "post_votes", :only => [:create, :destroy]
    resource :flag, controller: 'post_flags', only: [:destroy]
    resources :favorites, :controller => "post_favorites", :only => [:index]
    collection do
      get :random
    end
    member do
      get :update_iqdb
      put :revert
      put :copy_notes
      get :show_seq
      put :mark_as_translated
      get :comments, to: "comments#for_post"
    end
    get :similar, :to => "iqdb_queries#index"
  end
  resources :post_votes, only: [:index, :delete, :lock] do
    collection do
      post :lock
      post :delete
    end
  end
  resources :post_appeals
  resources :post_flags, except: [:destroy]
  resources :post_approvals, only: [:index]
  resources :post_versions, :only => [:index, :search] do
    member do
      put :undo
    end
    collection do
      get :search
    end
  end
  resources :artist_commentaries, :only => [:index, :show] do
    collection do
      put :create_or_update
      get :search
    end
    member do
      put :revert
    end
  end
  resource :related_tag, :only => [:show, :update]
  match "related_tag/bulk", to: "related_tags#bulk", via: [:get, :post]
  resource :recommended_posts, only: [:show]
  resource :session, only: [:new, :create, :destroy] do
    get :sign_out, on: :collection
  end
  resource :source, :only => [:show]
  resources :stats, only: [:index]
  resources :tags do
    resource :correction, :only => [:new, :create, :show], :controller => "tag_corrections"
    collection do
      get :autocomplete
      post :preview
    end
  end
  resources :tag_type_versions
  resources :tag_aliases do
    member do
      post :approve
    end
  end
  resource :tag_alias_request, :only => [:new, :create]
  resources :tag_implications do
    member do
      post :approve
    end
  end
  resource :tag_implication_request, :only => [:new, :create]
  resources :uploads
  resources :users do
    resource :password, :only => [:edit], :controller => "maintenance/user/passwords"
    resource :api_key, :only => [:show, :view, :update, :destroy], :controller => "maintenance/user/api_keys" do
      post :view
    end
    resources :staff_notes, only: [:index, :new, :create], controller: "admin/staff_notes"

    collection do
      get :home
      get :search
      get :upload_limit
      get :custom_style
    end
  end
  resources :user_feedbacks do
    collection do
      get :search
    end
  end
  resources :user_name_change_requests do
    member do
      post :approve
      post :reject
    end
  end
  resource :user_revert, :only => [:new, :create]
  resources :wiki_pages do
    member do
      put :revert
    end
    collection do
      get :search
      get :show_or_new
    end
  end
  resources :wiki_page_versions, :only => [:index, :show, :diff] do
    collection do
      get :diff
    end
  end
  resources :blips do
    member do
      post :hide
      post :unhide
      post :warning
    end
  end
  resources :post_report_reasons
  resources :post_sets do
    collection do
      get :atom
      get :for_select
    end
    member do
      get :maintainers
      get :post_list
      post :update_posts
      post :add_posts
      post :remove_posts
    end
  end
  resources :post_set_maintainers do
    member do
      get :approve
      get :block
      get :deny
    end
  end
  resource :email do
    collection do
      get :activate_user
      get :resend_confirmation
    end
  end

  options "*all", to: "application#enable_cors"

  # aliases
  resources :wpages, :controller => "wiki_pages"
  resources :ftopics, :controller => "forum_topics"
  resources :fposts, :controller => "forum_posts"

  # legacy aliases
  get "/artist" => redirect {|params, req| "/artists?page=#{req.params[:page]}&search[name]=#{CGI::escape(req.params[:name].to_s)}"}
  get "/artist/index" => redirect {|params, req| "/artists?page=#{req.params[:page]}"}
  get "/artist/show/:id" => redirect("/artists/%{id}")
  get "/artist/show" => redirect {|params, req| "/artists?name=#{CGI::escape(req.params[:name].to_s)}"}
  get "/artist/history/:id" => redirect("/artist_versions?search[artist_id]=%{id}")
  get "/artist/recent_changes" => redirect("/artist_versions")

  get "/comment" => redirect {|params, req| "/comments?page=#{req.params[:page]}"}
  get "/comment/index" => redirect {|params, req| "/comments?page=#{req.params[:page]}"}
  get "/comment/show/:id" => redirect("/comments/%{id}")
  get "/comment/new" => redirect("/comments")
  get("/comment/search" => redirect do |params, req|
    if req.params[:query] =~ /^user:(.+)/i
      "/comments?group_by=comment&search[creator_name]=#{CGI::escape($1)}"
    else
      "/comments/search"
    end
  end)

  get "/favorite" => redirect {|params, req| "/favorites?page=#{req.params[:page]}"}
  get "/favorite/index" => redirect {|params, req| "/favorites?page=#{req.params[:page]}"}

  get "/forum" => redirect {|params, req| "/forum_topics?page=#{req.params[:page]}"}
  get "/forum/index" => redirect {|params, req| "/forum_topics?page=#{req.params[:page]}"}
  get "/forum/show/:id" => redirect {|params, req| "/forum_posts/#{req.params[:id]}?page=#{req.params[:page]}"}
  get "/forum/search" => redirect("/forum_posts/search")

  get "/help/show/:title" => redirect("/help/%{title}")

  get "/note" => redirect {|params, req| "/notes?page=#{req.params[:page]}"}
  get "/note/index" => redirect {|params, req| "/notes?page=#{req.params[:page]}"}
  get "/note/history" => redirect {|params, req| "/note_versions?search[updater_id]=#{req.params[:user_id]}"}

  get "/pool" => redirect {|params, req| "/pools?page=#{req.params[:page]}"}
  get "/pool/index" => redirect {|params, req| "/pools?page=#{req.params[:page]}"}
  get "/pool/show/:id" => redirect("/pools/%{id}")
  get "/pool/history/:id" => redirect("/pool_versions?search[pool_id]=%{id}")
  get "/pool/recent_changes" => redirect("/pool_versions")

  get "/post/index/:page/:tags" => redirect {|params, req| "/posts?tags=#{CGI::escape(params[:tags].to_s)}&page=#{params[:page].to_i}"}
  get "/post/index/:page" => redirect {|params, req| "/posts?tags=&page=#{params[:page].to_i}"}
  get "/post/index" => redirect {|params, req| "/posts?tags=#{CGI::escape(req.params[:tags].to_s)}&page=#{req.params[:page]}"}
  get "/post" => redirect {|params, req| "/posts?tags=#{CGI::escape(req.params[:tags].to_s)}&page=#{req.params[:page]}"}
  get "/post/upload" => redirect("/uploads/new")
  get "/post/moderate" => redirect("/moderator/post/queue")
  get "/post/atom" => redirect {|params, req| "/posts.atom?tags=#{CGI::escape(req.params[:tags].to_s)}"}
  get "/post/atom.feed" => redirect {|params, req| "/posts.atom?tags=#{CGI::escape(req.params[:tags].to_s)}"}
  get "/post/popular_by_day" => redirect("/explore/posts/popular")
  get "/post/popular_by_week" => redirect("/explore/posts/popular")
  get "/post/popular_by_month" => redirect("/explore/posts/popular")
  get "/post/show/:id/:tag_title" => redirect("/posts/%{id}")
  get "/post/show/:id" => redirect("/posts/%{id}")
  get "/post/show" => redirect {|params, req| "/posts?md5=#{req.params[:md5]}"}
  get "/post/view/:id/:tag_title" => redirect("/posts/%{id}")
  get "/post/view/:id" => redirect("/posts/%{id}")
  get "/post/flag/:id" => redirect("/posts/%{id}")

  get("/post_tag_history" => redirect do |params, req|
    page = req.params[:before_id].present? ? "b#{req.params[:before_id]}" : req.params[:page]
    "/post_versions?page=#{page}&search[updater_id]=#{req.params[:user_id]}"
  end)
  get "/post_tag_history/index" => redirect {|params, req| "/post_versions?page=#{req.params[:page]}&search[post_id]=#{req.params[:post_id]}"}

  get "/tag" => redirect {|params, req| "/tags?page=#{req.params[:page]}&search[name_matches]=#{CGI::escape(req.params[:name].to_s)}&search[order]=#{req.params[:order]}&search[category]=#{req.params[:type]}"}
  get "/tag/index" => redirect {|params, req| "/tags?page=#{req.params[:page]}&search[name_matches]=#{CGI::escape(req.params[:name].to_s)}&search[order]=#{req.params[:order]}"}

  get "/tag_implication" => redirect {|params, req| "/tag_implications?search[name_matches]=#{CGI::escape(req.params[:query].to_s)}"}

  get "/user" => redirect {|params, req| "/users?page=#{req.params[:page]}"}
  get "/user/index" => redirect {|params, req| "/users?page=#{req.params[:page]}"}
  get "/user/show/:id" => redirect("/users/%{id}")
  get "/user/login" => redirect("/session/new")
  get "/user_record" => redirect {|params, req| "/user_feedbacks?search[user_id]=#{req.params[:user_id]}"}

  get "/wiki" => redirect {|params, req| "/wiki_pages?page=#{req.params[:page]}"}
  get "/wiki/index" => redirect {|params, req| "/wiki_pages?page=#{req.params[:page]}"}
  get "/wiki/rename" => redirect("/wiki_pages")
  get "/wiki/show/:title" => redirect("/wiki_pages/%{title}")
  get "/wiki/show" => redirect {|params, req| "/wiki_pages?title=#{CGI::escape(req.params[:title].to_s)}"}
  get "/wiki/recent_changes" => redirect {|params, req| "/wiki_page_versions?search[updater_id]=#{req.params[:user_id]}"}
  get "/wiki/history/:title" => redirect("/wiki_page_versions?title=%{title}")

  get "/static/keyboard_shortcuts" => "static#keyboard_shortcuts", :as => "keyboard_shortcuts"
  get "/static/site_map" => "static#site_map", :as => "site_map"
  get "/static/takedown" => "static#takedown", as: "takedown_static"
  get "/static/terms_of_service" => "static#terms_of_service", :as => "terms_of_service"
  post "/static/accept_terms_of_service" => "static#accept_terms_of_service", :as => "accept_terms_of_service"
  get "/static/contact" => "static#contact", :as => "contact"
  get "/static/discord" => "static#discord", as: "discord_get"
  post "/static/discord" => "static#discord", as: "discord_post"
  get "/static/toggle_mobile_mode" => "static#disable_mobile_mode", as: "disable_mobile_mode"
  get "static/theme" => "static#theme", as: "theme"
  get "/meta_searches/tags" => "meta_searches#tags", :as => "meta_searches_tags"

  get "/intro" => redirect("/explore/posts/intro")

  root :to => "static#home"

  get "*other", :to => "static#not_found"
end
