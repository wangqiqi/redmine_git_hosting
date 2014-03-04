class GitolitePublicKeysController < ApplicationController
  unloadable

  before_filter :require_login
  before_filter :set_user_variable
  before_filter :set_users_keys, :except => [:index, :new, :reset_rss_key]
  before_filter :find_gitolite_public_key, :except => [:index, :new, :reset_rss_key, :create]

  helper :issues
  helper :users
  helper :custom_fields

  helper :gitolite_public_keys
  include GitolitePublicKeysHelper


  def create
    @gitolite_public_key = GitolitePublicKey.new(params[:gitolite_public_key].merge(:user => @user))

    if params[:create_button]
      if @gitolite_public_key.save
        flash[:notice] = l(:notice_public_key_added, :title => keylabel(@gitolite_public_key))

        respond_to do |format|
          format.html { redirect_to @redirect_url }
        end
      else
        flash[:error] = @gitolite_public_key.errors.full_messages.to_sentence

        respond_to do |format|
          format.html { redirect_to @redirect_url }
        end
      end
    else
      respond_to do |format|
        format.html { redirect_to @redirect_url }
      end
    end
  end


  def edit
    redirect_to url_for(:controller => 'my', :action => 'account', :public_key_id => @gitolite_public_key[:id])
  end


  def update
    if !request.get?
      if params[:save_button]
        if @gitolite_public_key.update_attributes(params[:gitolite_public_key])
          flash[:notice] = l(:notice_public_key_updated, :title => keylabel(@gitolite_public_key))

          respond_to do |format|
            format.html { redirect_to @redirect_url }
          end
        else
          flash[:error] = @gitolite_public_key.errors.full_messages.to_sentence

          respond_to do |format|
            format.html { redirect_to @redirect_url }
          end
        end
      else
        destroy_key if params[:delete_button]

        respond_to do |format|
          format.html { redirect_to @redirect_url }
        end
      end
    end
  end


  def destroy
    if request.delete?
      destroy_key
    end
    redirect_to @redirect_url
  end


  protected


  def set_user_variable
    if params[:user_id]
      @user = (params[:user_id] == 'current') ? User.current : User.find_by_id(params[:user_id])
      if @user
        @redirect_url = url_for(:controller => 'users', :action => 'edit', :id => params[:user_id], :tab => 'keys')
      else
        render_404
      end
    else
      @user = User.current
      @redirect_url = url_for(:controller => 'my', :action => 'account')
    end
  end


  def set_users_keys
    @gitolite_user_keys   = @user.gitolite_public_keys.active.user_key.find(:all, :order => 'title ASC, created_at ASC')
    @gitolite_deploy_keys = @user.gitolite_public_keys.active.deploy_key.find(:all, :order => 'title ASC, created_at ASC')
    @gitolite_public_keys = @gitolite_user_keys + @gitolite_deploy_keys
  end


  def find_gitolite_public_key
    key = GitolitePublicKey.find_by_id(params[:id])
    if key and (@user == key.user || @user.admin?)
      @gitolite_public_key = key
    elsif key
      render_403
    else
      render_404
    end
  end


  def destroy_key
    @gitolite_public_key[:active] = 0

    # Since we are ultimately destroying this key, just force save (since old keys may fail new validations)
    @gitolite_public_key.save((Rails::VERSION::STRING.split('.')[0].to_i > 2) ? { :validate => false } : false)
    destroy_ssh_key

    flash[:notice] = l(:notice_public_key_deleted, :title => keylabel(@gitolite_public_key))
  end


  def destroy_ssh_key
    RedmineGitolite::GitHosting.logger.info { "User '#{User.current.login}' has deleted a SSH key" }

    repo_key = {}
    repo_key['title']    = @gitolite_public_key.identifier
    repo_key['key']      = @gitolite_public_key.key
    repo_key['location'] = @gitolite_public_key.location
    repo_key['owner']    = @gitolite_public_key.owner

    RedmineGitolite::GitHosting.logger.info { "Delete SSH key #{@gitolite_public_key.identifier}" }
    RedmineGitolite::GitHosting.resync_gitolite({ :command => :delete_ssh_key, :object => repo_key })

    project_list = []
    @gitolite_public_key.user.projects_by_role.each do |role|
      role[1].each do |project|
        project_list.push(project.id)
      end
    end

    if project_list.length > 0
      RedmineGitolite::GitHosting.logger.info { "Update project to remove SSH access : #{project_list.uniq}" }
      RedmineGitolite::GitHosting.resync_gitolite({ :command => :update_projects, :object => project_list.uniq })
    end
  end


  # Suggest title for new one-of deployment key
  def suggested_title
    # Base of suggested title
    default_title = "#{@project.name} Deploy Key"

    # Find number of keys or max default deploy key that matches
    maxnum = @repository.repository_deployment_credentials.map(&:gitolite_public_key).uniq.count
    @repository.repository_deployment_credentials.each do |credential|
      if matches = credential.gitolite_public_key.title.match(/#{default_title} (\d+)$/)
        maxnum = [maxnum, matches[1].to_i].max
      end
    end

    # Also, check for uniqueness for current user
    @user.gitolite_public_keys.each do |key|
      if matches = key.title.match(/#{default_title} (\d+)$/)
        maxnum = [maxnum, matches[1].to_i].max
      end
    end

    return "#{default_title} #{maxnum + 1}"
  end

end
