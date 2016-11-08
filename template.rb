@template_root = File.expand_path(File.join(File.dirname(__FILE__)))

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
web:    bundle exec rails server puma -p 5300 -b0.0.0.0
CODE

###
## ruby-version and ruby-gemset files
###

run "rvm current >> .ruby-version"
run "echo '#{app_name}' >> .ruby-gemset"

###
## REMOVING GEMS
###

gsub_file 'Gemfile', /gem 'turbolinks'.+$/, ""
gsub_file 'Gemfile', /gem 'sqlite3'.*$/, ""

###
## GENERAL CONFIGURATION
###

insert_into_file 'config/secrets.yml', after: 'production:' do
<<-CODE
\n  default_host: <%= ENV["DEFAULT_HOST"] %>
  default_protocol: <%= ENV["DEFAULT_PROTOCOL"] %>
  default_mail_from: <%= ENV["DEFAULT_MAIL_FROM"] %>
CODE
end

###
## POSTGRESQL
###

if yes?('Do you want to install postgresql?')
  gem 'pg', '~> 0.18'

  file 'config/database.yml.example', <<-CODE
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
  host: <%= Rails.application.secrets.postgres_host %>
  username: <%= Rails.application.secrets.postgres_username %>
  password: <%= Rails.application.secrets.postgres_password %>
  CODE


  insert_into_file 'config/secrets.yml', after: 'production:' do
  <<-CODE
  \n  postgres_host: <%= ENV["POSTGRES_HOST"] %>
  postgres_username: <%= ENV["POSTGRES_USERNAME"] %>
  postgres_password: <%= ENV["POSTGRES_PASSWORD"] %>
  CODE
  end
end

gem 'autoprefixer-rails'

###
## Turbolinks (classic)
###

if yes?("Do you want to install turbolinks classic?")
  gem 'turbolinks', '2.5.3'
else
  gsub_file 'app/assets/javascripts/application.js', '//= require turbolinks', ''
end

insert_into_file 'Gemfile', after: 'group :development, :test do' do
<<-CODE
\n  gem 'awesome_print'
CODE
end

insert_into_file 'Gemfile', after: 'group :development do' do
<<-CODE
\n  gem 'foreman'
CODE
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

  environment 'config.action_mailer.delivery_method = :letter_opener', env: 'development'
end

###
## GEMS FOR PRODUCTION
###

gem_group :production do
  gem 'rails_12factor'
end

###
## CARRIERWAVE (file uploads)
###

if yes?("Do you want to install carrierwave?")
  gem 'carrierwave'
end

###
## MINI-MAGICK (image processing)
###

if yes?("Do you want to install mini_magick?")
  gem 'mini_magick'
end

###
## SIDEKIQ and SIDEKIQ-CRON (background jobs)
###

if yes?("Do you want to install sidekiq and sidekiq-cron?")
  gem 'sidekiq'
  gem 'sidekiq-cron'
  gem "sinatra", ">= 2.0.0.beta2", require: false

  insert_into_file 'Procfile', after: '0.0.0.0' do
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
\nauthenticate :user, lambda { |u| u.admin? } do
  mount Sidekiq::Web => '/sidekiq'
end
    CODE
  end

  insert_into_file 'config/routes.rb', before: 'Rails.application.routes.draw' do
    <<-CODE
require 'sidekiq/web'
    CODE
  end


  initializer 'sidekiq.rb', <<-CODE
redis_url = "redis://\#{Rails.application.secrets.redis_host}:6379"

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

  insert_into_file 'config/secrets.yml', after: 'production:' do
<<-CODE
\n  redis_host: <%= ENV["REDIS_HOST"] %>
  CODE
  end

  insert_into_file 'config/secrets.yml', after: 'test:' do
<<-CODE
\n  redis_host: localhost
  CODE
  end

  insert_into_file 'config/secrets.yml', after: 'development:', force: true do
<<-CODE
\n  redis_host: localhost
  CODE
  end

  environment 'config.active_job.queue_adapter = :sidekiq'

  file 'tmp/pids/sidekiq.pid', ""
end

###
## KAMINARI (pagination)
###

if yes?("Do you want to install kaminari?")
  gem 'kaminari'
end

###
## Authorization system
###

if want_pundit = yes?("Do you want to install pundit?")
  gem 'pundit'

  insert_into_file 'app/controllers/application_controller.rb', after: 'class ApplicationController < ActionController::Base' do
    <<-CODE
\n  include Pundit
CODE
  end
end

###
## DEVISE (authentication)
###

if want_devise = yes?("Do you want to install devise?")
  gem 'devise'

  environment 'config.to_prepare do
      Devise::Mailer.layout "mailer"
    end'
end

###
## GROWLYFLASH (growl notifications)
###

if yes?("Do you want to install growlyflash?")
  gem 'growlyflash'

  file 'app/assets/javascripts/config/growly_flash.js.coffee', <<-CODE
Growlyflash.defaults = $.extend on, Growlyflash.defaults,
  align:   'right'  # horizontal aligning (left, right or center)
  delay:   3000     # auto-dismiss timeout (0 to disable auto-dismiss)
  dismiss: yes      # allow to show close button
  spacing: 10       # spacing between alerts
  target:  'body'   # selector to target element where to place alerts
  title:   no       # switch for adding a title
  type:    null     #  alert class by default
  class:   ['alert', 'growlyflash', 'fade']
  type_mapping:
    alert:   'warning'
    error:   'danger'
    notice:  'info'
    success: 'success'


$(document).on 'click', '[data-dismiss="alert"]', ->
  $(@).parent().remove()
  CODE

  insert_into_file 'app/assets/javascripts/application.js', before: '//= require_tree' do
    <<-CODE
//= require growlyflash
    CODE
  end
end

###
## FRIENDLY_ID
###

if want_friendly_id = yes?("Do you want to install friendly_id?")
  gem 'friendly_id'
end

run 'rm app/assets/stylesheets/application.css'
run "touch app/assets/stylesheets/application.scss"

###
## TWITTER BOOTSTRAP
###

if yes?("Do you want to install twitter/bootstrap?")
  gem 'bootstrap'
  add_source 'https://rails-assets.org' do
    gem 'rails-assets-tether', '>= 1.1.0'
  end

  insert_into_file "app/assets/javascripts/application.js", before: '//= require_tree' do
      <<-CODE
//= require tether
//= require bootstrap-sprockets
      CODE
  end

  run "echo '@import \"bootstrap\";' >> app/assets/stylesheets/application.scss"
end

###
## MAILING CONFIGURATION
###

environment 'config.action_mailer.default_url_options = { host: Rails.application.secrets.default_host, protocol: Rails.application.secrets.default_protocol }'

environment 'config.action_mailer.smtp_settings = {
    :address   => Rails.application.secrets.smtp_address,
    :port      => Rails.application.secrets.smtp_port,
    :user_name => Rails.application.secrets.smtp_user_name,
    :password  => Rails.application.secrets.smtp_password
  }', env: 'production'

insert_into_file 'config/secrets.yml', after: 'production:' do
<<-CODE
\n  smtp_address: <%= ENV["SMTP_ADDRESS"] %>
  smtp_port: <%= ENV["SMTP_PORT"] %>
  smtp_user_name: <%= ENV["SMTP_USER_NAME"] %>
  smtp_password: <%= ENV["SMTP_PASSWORD"] %>
CODE
end

###
## BOWER
###

if want_bower = yes?("Do you want to install bower?")
  file '.bowerrc', <<-CODE
{
  "directory": "vendor/assets/components"
}
CODE

  inject_into_file 'config/initializers/assets.rb', after: "Rails.application.config.assets.version = '1.0'" do
  <<-CODE
\nRails.application.config.assets.paths << Rails.root.join('vendor', 'assets', 'components').to_s
  CODE
  end
end

###
## DETAILS
###

# make possible to use url helpers in assets
environment 'config.assets.configure do |env|
      env.context_class.class_eval do
        include Rails.application.routes.url_helpers
      end
    end'

# adds database.yml to .gitignore
run "echo /config/database.yml >> .gitignore"

p 'TO FINISH INSTALLATION, DO THE FOLLOWING THINGS'
p "execute command 'cd #{app_name}'"
p "execute command 'bundle install'"
p "execute command 'bower init'" if want_bower
p "execute command 'rails generate pundit:install'" if want_pundit
p "execute command 'rails generate devise:install'" if want_devise
p "execute command 'rails generate friendly_id'" if want_friendly_id
