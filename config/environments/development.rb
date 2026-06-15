Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # In the development environment your application's code is reloaded on
  # every request. This slows down response time but is perfect for development
  # since you don't have to restart the web server when you make code changes.
  config.cache_classes = false

  # Do not eager load code on boot.
  config.eager_load = false

  # Show full error reports.
  config.consider_all_requests_local = true

  # Enable/disable caching. By default caching is disabled.
  # Run rails dev:cache to toggle caching.
  if Rails.root.join('tmp', 'caching-dev.txt').exist?
    config.action_controller.perform_caching = true

    config.cache_store = :memory_store
    config.public_file_server.headers = {
      'Cache-Control' => "public, max-age=#{2.days.to_i}"
    }
  else
    config.action_controller.perform_caching = false

    config.cache_store = :null_store
  end

  # Store uploaded files on the local file system (see config/storage.yml for options)
  config.active_storage.service = :local

  # Don't care if the mailer can't send.
  config.action_mailer.raise_delivery_errors = true

  config.action_mailer.show_previews = true 
  config.action_mailer.preview_path =  "#{Rails.root}/test/mailers/previews"
  config.action_mailer.delivery_method = :smtp 

  config.action_mailer.show_previews = true
  config.action_mailer.preview_path = "#{Rails.root}/test/mailers/previews"

  smtp_config_path = Rails.root.join('config', 'smtp_settings.yml')

  if File.exist?(smtp_config_path)
    smtp_settings = YAML.load_file(smtp_config_path)
                        .deep_symbolize_keys[:smtp_settings][Rails.env.to_sym]

    config.action_mailer.smtp_settings = {
      address: smtp_settings[:address],
      port: smtp_settings[:port],
      domain: smtp_settings[:domain],
      user_name: smtp_settings[:user_name],
      password: smtp_settings[:password],
      authentication: :login,
      enable_starttls_auto: smtp_settings[:enable_starttls_auto],
      open_timeout: 30,
      read_timeout: 60
    }
  else
     puts "WARNING: SMTP config file not found at #{smtp_config_path}. Skipping SMTP setup."
    # You can choose to set default SMTP settings here or skip entirely.
    # config.action_mailer.smtp_settings = { ...default values... }
  end

  config.action_mailer.perform_caching = false

  # Print deprecation notices to the Rails logger.
  config.active_support.deprecation = :log

  # Raise an error on page load if there are pending migrations.
  config.active_record.migration_error = :page_load

  # Highlight code that triggered database queries in logs.
  config.active_record.verbose_query_logs = true

  # Disable Legacy connection handling
  config.active_record.legacy_connection_handling = false


  # Raises error for missing translations
  # config.action_view.raise_on_missing_translations = true

  # Use an evented file watcher to asynchronously detect changes in source code,
  # routes, locales, etc. This feature depends on the listen gem.
  config.file_watcher = ActiveSupport::EventedFileUpdateChecker

  #Activate Logrotate
  config.logger = Logger.new("#{Rails.root}/log/#{ENV['RAILS_ENV']}.log", 10, 1048576)
  Rails.application.routes.default_url_options[:host] = ENV["DDE_HOST_URL"]

  config.action_cable.allowed_request_origins = [
    /https?:\/\/.*/  # Allows any HTTP or HTTPS origin
  ]
  
  config.hosts.clear
end
