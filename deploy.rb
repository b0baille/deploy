# config
APP_ROOT_DIR = "../devops-test"
APP_VERSION = ENV["APP_VERSION"].to_i
SECRET_KEY_BASE = ENV["SECRET_KEY_BASE"] || "super_secret"

DOCKER_HOST = ENV["DOCKER_HOST"] #should match with the output of spawn_server.rb

# config decided during server provisionning
MYSQL_PASSWORD = ENV["MYSQL_PASSWORD"]
MYSQL_PORT = "3306"
MYSQL_USER = "root"
MYSQL_HOST = "127.0.0.1"

# static, should not be changed
DOCKER_PORT = "2375"
APP_PORT = "9999" #if this change nginx should be redeployed
CONTAINER_NAME = "app"

%w(DOCKER_HOST APP_VERSION MYSQL_PASSWORD).each do |var|
  if ENV[var] == nil || ENV[var] == 0
    puts "plase set the #{var} environment variable"
    exit 1
  end
end

# utlities ---------------------------------------------------------------------
def log_info(info)
  puts "-----> #{info}"
end

def exec_docker_command(command, args, env = {})
  cmd = "#{docker_base_cmd} #{command} #{env_hash_to_docker_args(env)} #{args}"
  if !system(cmd)
    puts "Command failed: #{cmd}"
    exit 1
  end
end

def delete_container(name)
  system("#{docker_base_cmd} rm -f #{name}")
end

def docker_base_cmd
  "./vendor/docker -H tcp://#{DOCKER_HOST}:#{DOCKER_PORT}"
end

def env_hash_to_docker_args(env)
  envStr = ""
  env.each {|k, v| envStr = "#{envStr} -e #{k}=#{v}"}
  envStr
end
# ------------------------------------------------------------------------------

default_app_env = {
  MYSQL_PORT: MYSQL_PORT,
  MYSQL_PASSWORD: MYSQL_PASSWORD,
  MYSQL_USER: MYSQL_USER,
  MYSQL_HOST: MYSQL_HOST,
  SECRET_KEY_BASE: SECRET_KEY_BASE
}

# build the app
log_info "Building app version #{APP_VERSION}"

app_image = "#{CONTAINER_NAME}:v#{APP_VERSION}"

exec_docker_command("build", "-t #{app_image} #{APP_ROOT_DIR}")

log_info "Running database migrations"

if APP_VERSION == 1
  name = "db_create"
  exec_docker_command("run", "--net host --name #{name} #{app_image} bundle exec rake db:create", default_app_env)
  delete_container(name)
end

# run migrations
name = "db_migrate"
exec_docker_command("run", "--net host --name #{name} #{app_image} bundle exec rake db:migrate", default_app_env)
delete_container(name)

# start the app

log_info "Starting the app"

if APP_VERSION > 1
  log_info "Deleting previous version"
  delete_container("#{CONTAINER_NAME}_v#{APP_VERSION - 1}")
end

app_container = "#{CONTAINER_NAME}_v#{APP_VERSION}"
exec_docker_command("run", "--name #{app_container} -d --net host --restart always #{app_image} bundle exec puma -p #{APP_PORT}", default_app_env)

# reconfigure nginx
if APP_VERSION == 1
  log_info "Deploying nginx"

  nginx_conf = "
  events {
    worker_connections  19000;
  }
  http {
    server {
      listen 80 default_server;
      listen [::]:80 default_server ipv6only=on;

      try_files $uri/index.html $uri @devops_app;

      location / {
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header Host $http_host;
        proxy_redirect off;

        proxy_pass http://127.0.0.1:#{APP_PORT};
      }

      location ^~ /assets/ {
        gzip_static on;
        expires max;
        add_header Cache-Control public;
      }
    }
  }
  "

  File.write("nginx/nginx.conf", nginx_conf)

  exec_docker_command("build", "-t nginx:v#{APP_VERSION} nginx", [])
  exec_docker_command("run", "-d --name nginx_v#{APP_VERSION} --net host --restart always nginx:v#{APP_VERSION}", [])
end

# summary
puts "\n"
log_info "App version #{APP_VERSION} reachable at http://#{DOCKER_HOST}"
log_info "To see app logs: #{docker_base_cmd} logs #{app_container}"
log_info "To run a command in the app environment: #{docker_base_cmd} run -it --net host #{env_hash_to_docker_args(default_app_env)} #{app_image} <command>"
log_info "To deploy an update run the command again with incremented APP_VERSION config"
