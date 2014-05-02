# gsub_file 'config/database.yml', /database: lurker_app.*/, 'database: lurker_app'
create_link "bin/lurker", "#{File.expand_path '../../bin/lurker', __FILE__}"

remove_file 'spec/spec_helper.rb'
remove_file 'app/models/user.rb'

generate 'rspec:install'
generate 'model User name:string --no-timestamps --no-test-framework'
generate 'model Repo user:references name:string --no-timestamps --no-test-framework'

route <<-ROUTE
  mount Lurker::Server.to_rack(path: 'html'), at: "/#{Lurker::DEFAULT_URL_BASE}"

  namespace :api do
    namespace :v1 do
      resources :users do
        resources :repos
      end
    end
  end

  root to: redirect('/lurker')
ROUTE

inject_into_class 'app/models/user.rb', 'User' do
  <<-CODE
    has_many :repos
    validates :name, presence: true
  CODE
end

file 'app/controllers/application_controller.rb', 'ApplicationController', force: true do
  <<-CODE
    class ApplicationController < ActionController::Base
      protect_from_forgery with: :null_session
      before_filter :set_format

      private

      def set_format
        request.format = :json
      end
    end
  CODE
end

file 'app/controllers/api/v1/users_controller.rb', 'Api::V1::UsersController', force: true do
  <<-CODE
    class Api::V1::UsersController < ApplicationController
      def index
        @users = User.all
        if (limit = params[:limit]).to_s.match(/\\d+/)
          @users = @users.limit(limit.to_i)
        end
        render json: @users.order('id ASC')
      end

      def create
        @user = User.new(user_params)
        if @user.save
          render json: @user
        else
          render json: { errors: @user.errors }
        end
      end

      def update
        if user.update(user_params)
          render json: user
        else
          render json: { errors: user.errors }
        end
      end

      def show
        render json: user
      end

      def destroy
        user.destroy
        render json: true
      end

      private

      def user
        @user ||= (User.find_by_name(params[:id]) || User.find(params[:id]))
      end

      def user_params
        @user_params = params[:user]
        if @user_params.respond_to? :permit
          @user_params.permit(:name)
        else
          @user_params
        end
      end
    end
  CODE
end

file 'app/controllers/api/v1/repos_controller.rb', 'Api::V1::ReposController', force: true do
  <<-CODE
    class Api::V1::ReposController < ApplicationController

      def index
        @repos = user.repos
        if (limit = params[:limit]).to_s.match(/\\d+/)
          @repos = @repos.limit(limit.to_i)
        end
        render json: @repos.order('id ASC')
      end

      def create
        @repo = user.repos.build(repo_params)
        if @repo.save
          render json: @repo.to_json(include: 'user', except: 'user_id')
        else
          render json: { errors: @repo.errors }, status: 401
        end
      end

      def show
        render json: Repo.find(params[:id])
      end

      def update
        @repo = user.repos.find(params[:id])
        if @repo.update(repo_params)
          render json: @repo
        else
          render json: { errors: @repo.errors }
        end
      end


      def destroy
        Repo.find(params[:id]).destroy
        render json: true
      end

      private

      def user
        @user ||= (User.find_by_name(params[:user_id]) || User.find(params[:user_id]))
      end

      def repo_params
        @repo_params = params[:repo]
        if @repo_params.respond_to? :permit
          @repo_params.permit(:name, :user_id)
        else
          @repo_params
        end
      end
    end
  CODE
end

# FIXME: uninitialized constant User (NameError) in last creation line
append_to_file 'config/environment.rb' do
  <<-CODE
    $:.unshift File.expand_path('../../app/models', __FILE__)
  CODE
end

inject_into_class 'config/application.rb', 'Application' do
  <<-CODE
    if ENV['DATABASE_URL'].present? # heroku
      config.middleware.use Lurker::Sandbox
    end
    config.action_dispatch.default_headers = {
      'Access-Control-Allow-Origin' => '*',
      'Access-Control-Request-Method' => 'GET, PUT, POST, DELETE, OPTIONS'
    }
  CODE
end

file 'spec/support/fixme.rb', force: true do
  <<-CODE
    require 'simplecov'

    if simplecov_root = ENV['SIMPLECOV_ROOT']
      SimpleCov.root simplecov_root
    end

    if simplecov_cmdname = ENV['SIMPLECOV_CMDNAME']
      SimpleCov.command_name simplecov_cmdname
      SimpleCov.start do
        filters.clear # This will remove the :root_filter that comes via simplecov's defaults
        add_filter do |src|
          !(src.filename =~ /^\#{SimpleCov.root}\\/lib\\/lurker/)
        end
      end
    else
      SimpleCov.start
    end

    require 'database_cleaner'
    DatabaseCleaner.strategy = :truncation

    require 'lurker/spec_watcher'

    RSpec.configure do |c|
      c.treat_symbols_as_metadata_keys_with_true_values = true
      c.backtrace_exclusion_patterns += [
        /\\/lib\\/lurker/
      ]

      c.before do
        %w[repos_id_seq users_id_seq].each do |id|
          ActiveRecord::Base.connection.execute "ALTER SEQUENCE \#{id} RESTART WITH 1"
        end
        DatabaseCleaner.start
      end

      c.after do
        DatabaseCleaner.clean
      end
    end
  CODE
end

file 'lib/tasks/db.rake', force: true do
  <<-CODE
    namespace :db do
      desc 'fills in data'
      task :import => :environment do
        User.find_or_create_by!(name: "razum2um").repos.find_or_create_by!(name: "lurker")
        User.find_or_create_by!(name: "razum2um").repos.find_or_create_by!(name: "resque-kalashnikov")
        User.find_or_create_by!(name: "razum2um").repos.find_or_create_by!(name: "mutli_schema")
      end
    end
  CODE
end

run 'bin/rake db:drop'
run 'bin/rake db:create'
run 'bin/rake db:migrate'
run 'bin/rake db:import'

run 'RAILS_ENV=test bin/rake db:drop'
run 'RAILS_ENV=test bin/rake db:create'
run 'RAILS_ENV=test bin/rake db:migrate'

