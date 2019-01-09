@template_root = File.expand_path(File.join(File.dirname(__FILE__)))

run 'touch config/credentials.yml.example'
run 'echo secret_key_base: >> config/credentials.yml.example'

##
## DOCKER
##

run "mkdir docker"

['Dockerfile', '.dockerignore', 'docker/docker-compose.yml', 'docker/env.example', 'docker/nginx.conf.example', 'docker/README.md', 'docker/supervisor.conf'].each do |file|
  file file, File.read("#{@template_root}/#{file}").gsub('@APP_NAME', app_name.underscore)
end


###
## PROCFILE
###

file 'Procfile', <<-CODE
web:    bundle exec rails server puma -p 3000
CODE

###
## ruby-version and ruby-gemset files
###

run "rvm current >> .ruby-version"
run "echo '#{app_name}' >> .ruby-gemset"

###
## REMOVING GEMS
###

gsub_file 'Gemfile', /gem 'sqlite3'.*$/, ""
gsub_file 'Gemfile', /gem 'sass-rails'.*$/, ""
gsub_file 'Gemfile', /gem 'uglifier'.*$/, ""
gsub_file 'Gemfile', /gem 'tzinfo-data'.*$/, ""

###
### adds gems always used
###

## inflections
gem 'inflections'

## pundit
gem 'pundit'
insert_into_file 'app/controllers/application_controller.rb', after: 'class ApplicationController < ActionController::Base' do
  <<-CODE
\n  include Pundit
CODE
end

###
## POSTGRESQL
###

if yes?('Do you want to install postgresql?')
  gem 'pg'

  database_yml = <<-CODE
default: &default
  adapter: postgresql
  encoding: unicode
  # For details on connection pooling, see rails configuration guide
  # http://guides.rubyonrails.org/configuring.html#database-pooling
  pool: 5

development:
  <<: *default
  database: #{app_name.underscore}_development

test:
  <<: *default
  database: #{app_name.underscore}_test

production:
  <<: *default
  database: #{app_name.underscore}_production
  host: <%= Rails.application.credentials.postgres_host %>
  username: <%= Rails.application.credentials.postgres_username %>
  password: <%= Rails.application.credentials.postgres_password %>
  CODE

  file 'config/database.yml.example', database_yml
  file 'config/database.yml', database_yml

  run 'echo postgres_host: >> config/credentials.yml.example'
  run 'echo postgres_username: >> config/credentials.yml.example'
  run 'echo postgres_password: >> config/credentials.yml.example'
end

if yes?("Do you want to install awesome_print gem?")
  insert_into_file 'Gemfile', after: 'group :development, :test do' do
  <<-CODE
  \n  gem 'awesome_print'
  CODE
  end
end

if yes?("Do you want to install foreman gem?")
  insert_into_file 'Gemfile', after: 'group :development do' do
  <<-CODE
  \n  gem 'foreman'
  CODE
  end
end

###
## LETTER_OPENER (open mails in browser in dev)
###

if yes?("Do you want to install letter_opener?")
  insert_into_file 'Gemfile', after: 'group :development do' do
  <<-CODE
  \n  gem 'letter_opener'
  CODE
  end
end

###
## image_processing gem
###

if yes?("Do you want to process images? ie install 'image_processing' gem")
  gem 'image_processing'
end

###
## SIDEKIQ and SIDEKIQ-CRON (background jobs)
###

if yes?("Do you want to install sidekiq and sidekiq-cron?")
  gem 'sidekiq'
  gem 'sidekiq-cron'

  insert_into_file 'Procfile', after: '3000' do
    <<-CODE
\nworker: bundle exec sidekiq -C ./config/sidekiq.yml
    CODE
  end

  file 'config/sidekiq.yml', <<-CODE
# configuration file for Sidekiq
:verbose: true
:pidfile: ./tmp/pids/sidekiq.pid
:logfile: ./log/sidekiq.log
:concurrency:  25
:queues:
  - [default, 5]
  - [mailers, 3]
  CODE

  insert_into_file 'config/routes.rb', after: 'Rails.application.routes.draw do' do
    <<-CODE
  \n  mount Sidekiq::Web => '/sidekiq'
    CODE
  end

  insert_into_file 'config/routes.rb', before: 'Rails.application.routes.draw' do
    <<-CODE
require 'sidekiq/web'
require 'sidekiq/cron/web'

    CODE
  end


  initializer 'sidekiq.rb', <<-CODE
redis_url = "redis://\#{Rails.application.credentials.redis_host}:6379"

Sidekiq.configure_server do |config|
  config.redis = { url: redis_url }
end

Sidekiq.configure_client do |config|
  config.redis = { url: redis_url }
end

schedule_file = "config/schedule.yml"

if File.exists?(schedule_file)
  rendered_schedule_file = ERB.new(File.read(schedule_file)).result
  Sidekiq::Cron::Job.load_from_hash! YAML.load(rendered_schedule_file) || {}
end
  CODE

  file 'config/schedule.yml', <<-CODE
--- {}
  CODE

  run 'echo redis_host: >> config/credentials.yml.example'

  environment 'config.active_job.queue_adapter = :sidekiq'

  file 'tmp/pids/sidekiq.pid', ""
end


###
## DEVISE (authentication)
###

if want_devise = yes?("Do you want to install devise?")
  gem 'devise'

  environment 'config.to_prepare { Devise::Mailer.layout "mailer" }'
end

###
## FRIENDLY_ID
###

if want_friendly_id = yes?("Do you want to install friendly_id?")
  gem 'friendly_id'
end

###
## MAILING CONFIGURATION
###

environment 'config.action_mailer.delivery_method = Rails.application.credentials.mail_delivery_method&.to_sym'

environment 'config.action_mailer.default_url_options = { host: Rails.application.credentials.default_host, protocol: Rails.application.credentials.default_protocol }'

environment 'config.action_mailer.smtp_settings = {
    address:              Rails.application.credentials.smtp_address,
    port:                 Rails.application.credentials.smtp_port,
    user_name:            Rails.application.credentials.smtp_user_name,
    password:             Rails.application.credentials.smtp_password,
    authentication:       "plain",
    enable_starttls_auto: true
  }', env: 'production'

run 'echo default_mail_from: >> config/credentials.yml.example'
run 'echo smtp_address: >> config/credentials.yml.example'
run 'echo smtp_port: >> config/credentials.yml.example'
run 'echo smtp_user_name: >> config/credentials.yml.example'
run 'echo smtp_password: >> config/credentials.yml.example'
run 'echo smtp_delivery_method: >> config/credentials.yml.example'

gsub_file 'app/mailers/application_mailer.rb', "'from@example.com'", "Rails.application.credentials.default_mail_from"

insert_into_file 'app/mailers/application_mailer.rb', after: "ActionMailer::Base" do
  <<-CODE
  \n  append_view_path Rails.root.join('app', 'views', 'mailers')
  CODE
end

environment 'config.action_mailer.asset_host = "#{Rails.application.credentials.default_protocol}://#{Rails.application.credentials.default_host}"'

###
## DETAILS
###

run "echo default_host: >> config/credentials.yml.example"
run "echo default_protocol: >> config/credentials.yml.example"

# adds database.yml to .gitignore
run "echo /config/database.yml >> .gitignore"

# adds CHANGELOG.md file
run "touch CHANGELOG.md"

p 'TO FINISH INSTALLATION, DO THE FOLLOWING THINGS'
p "execute command 'cd #{app_name}'"
p "execute command 'bundle install'"
p "execute command 'rails generate pundit:install'"
if want_devise
  p "execute command 'rails generate devise:install'"
  p "configure devise updating the file config/initializers/devise.rb"
end
p "execute command 'rails generate friendly_id'" if want_friendly_id
p "DO NOT FORGET to configure the locale and the time_zone of your project"
