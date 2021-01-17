#!/usr/bin/env ruby

require 'fileutils'
require 'json'
require 'yaml'
require './credentials.rb'

PROFILE = [:static, :dynamic, :neo4j]

# to get development mode, add the following to your ~/.bashrc:
# export QTS_DEVELOPMENT=1

DEVELOPMENT    = !(ENV['QTS_DEVELOPMENT'].nil?)
PROJECT_NAME = 'code' + (DEVELOPMENT ? 'dev' : '')
DEV_NGINX_PORT = 8025
DEV_NEO4J_PORT = 8021
LOGS_PATH = DEVELOPMENT ? './logs' : "/home/qts/logs/#{PROJECT_NAME}"
DATA_PATH = DEVELOPMENT ? './data' : "/home/qts/data/#{PROJECT_NAME}"
NEO4J_DATA_PATH = File::join(DATA_PATH, 'neo4j')
NEO4J_LOGS_PATH = File::join(LOGS_PATH, 'neo4j')
RAW_FILES_PATH = File::join(DATA_PATH, 'raw')
GEN_FILES_PATH = File::join(DATA_PATH, 'gen')

docker_compose = {
    :version => '3',
    :services => {},
}

if PROFILE.include?(:static)
    docker_compose[:services][:nginx] = {
        :build => './docker/nginx',
        :volumes => [
            './src/static:/usr/share/nginx/html:ro',
            "#{RAW_FILES_PATH}:/raw:ro",
            "#{GEN_FILES_PATH}:/gen:ro",
            "#{LOGS_PATH}:/var/log/nginx",
        ]
    }
    if !DEVELOPMENT
        docker_compose[:services][:nginx][:environment] = [
            "VIRTUAL_HOST=#{WEBSITE_HOST}",
            "LETSENCRYPT_HOST=#{WEBSITE_HOST}",
            "LETSENCRYPT_EMAIL=#{LETSENCRYPT_EMAIL}"
        ]
        docker_compose[:services][:nginx][:expose] = ['80']
    end
    if PROFILE.include?(:dynamic)
        docker_compose[:services][:nginx][:links] = ["ruby:#{PROJECT_NAME}_ruby_1",
                                                     "pixelflut:#{PROJECT_NAME}_pixelflut_1"]
    end
    nginx_config = <<~eos
        log_format custom '$http_x_forwarded_for - $remote_user [$time_local] "$request" '
                          '$status $body_bytes_sent "$http_referer" '
                          '"$http_user_agent" "$request_time"';

        server {
            listen 80;
            server_name localhost;
            client_max_body_size 8M;

            access_log /var/log/nginx/access.log custom;

            charset utf-8;

            location /raw/ {
                rewrite ^/raw(.*)$ $1 break;
                root /raw;
            }

            location /gen/ {
                rewrite ^/gen(.*)$ $1 break;
                root /gen;
            }

            location /pixelflut/ {
                try_files $uri @pixelflut;
            }

            location @pixelflut {
                proxy_pass http://#{PROJECT_NAME}_pixelflut_1:9292;
                proxy_set_header Host $host;
                proxy_http_version 1.1;
            }
        
            location / {
                root /usr/share/nginx/html;
                try_files $uri @ruby;
            }

            location @ruby {
                proxy_pass http://#{PROJECT_NAME}_ruby_1:9292;
                proxy_set_header Host $host;
                proxy_http_version 1.1;
                proxy_set_header Upgrade $http_upgrade;
                proxy_set_header Connection Upgrade;
            }
        }

    eos
    File::open('docker/nginx/default.conf', 'w') do |f|
        f.write nginx_config
    end
    if PROFILE.include?(:dynamic)
        docker_compose[:services][:nginx][:depends_on] = [:ruby, :pixelflut]
    end
end

if PROFILE.include?(:dynamic)
    env = []
    env << 'DEVELOPMENT=1' if DEVELOPMENT
    docker_compose[:services][:ruby] = {
        :build => './docker/ruby',
        :volumes => ['./src/ruby:/app:ro',
                     './src/static:/static:ro',
                     './src/tasks:/tasks:ro',
                     "#{RAW_FILES_PATH}:/raw",
                     "#{GEN_FILES_PATH}:/gen",
                     "/var/run/docker.sock:/var/run/docker.sock"],
        :environment => env,
        :privileged => true,
        :working_dir => '/app',
        :entrypoint =>  DEVELOPMENT ?
            'rerun -b --dir /app -s SIGKILL \'rackup --host 0.0.0.0\'' :
            'rackup --host 0.0.0.0'
    }
    docker_compose[:services][:pysandbox] = {
        :build => './docker/pysandbox',
        :entrypoint =>  '/usr/bin/tail -f /dev/null',
        :volumes => ["#{RAW_FILES_PATH}/sandbox:/sandbox"],
        :links => ['pixelflut:pixelflut']
    }
    docker_compose[:services][:pixelflut] = {
        :build => './docker/pixelflut',
        :volumes => ['./src/pixelflut:/app:ro',
                     "#{RAW_FILES_PATH}/pixelflut:/raw"],
        :environment => env,
        :working_dir => '/app',
        :entrypoint =>  DEVELOPMENT ?
            'rerun -b --dir /app -s SIGKILL \'rackup --quiet --host 0.0.0.0\'' :
            'rackup --quiet --host 0.0.0.0'
    }
    if PROFILE.include?(:neo4j)
        docker_compose[:services][:ruby][:depends_on] ||= []
        docker_compose[:services][:ruby][:depends_on] << :neo4j
        docker_compose[:services][:ruby][:depends_on] << :pysandbox
        docker_compose[:services][:ruby][:links] = ['neo4j:neo4j']
    end
end

if PROFILE.include?(:neo4j)
    docker_compose[:services][:neo4j] = {
        :build => './docker/neo4j',
        :volumes => ["#{NEO4J_DATA_PATH}:/data",
                     "#{NEO4J_LOGS_PATH}:/logs"]
    }
    docker_compose[:services][:neo4j][:environment] = [
        'NEO4J_AUTH=none',
        'NEO4J_dbms_logs__timezone=SYSTEM',
    ]
    docker_compose[:services][:neo4j][:user] = "#{UID}"
end

docker_compose[:services].values.each do |x|
    x[:network_mode] = 'default'
end

if DEVELOPMENT
    docker_compose[:services][:nginx][:ports] = ["127.0.0.1:#{DEV_NGINX_PORT}:80"]
    if PROFILE.include?(:neo4j)
        docker_compose[:services][:neo4j][:ports] = ["127.0.0.1:#{DEV_NEO4J_PORT}:7474",
                                                     "127.0.0.1:7687:7687"]
    end
else
    docker_compose[:services].values.each do |x|
        x[:restart] = :always
    end
end

File::open('docker-compose.yaml', 'w') do |f|
    f.puts "# NOTICE: don't edit this file directly, use config.rb instead!\n"
    f.write(JSON::parse(docker_compose.to_json).to_yaml)
end

FileUtils::mkpath(LOGS_PATH)
if PROFILE.include?(:dynamic)
    FileUtils::cp('src/ruby/Gemfile', 'docker/ruby/')
    FileUtils::cp('credentials.rb', 'docker/ruby/')
    FileUtils::cp('src/pixelflut/Gemfile', 'docker/pixelflut/')
    FileUtils::mkpath(File::join(RAW_FILES_PATH, 'uploads'))
    system("cp -purv src/static/avatars/* #{File::join(RAW_FILES_PATH, 'uploads')}")
    FileUtils::mkpath(File::join(RAW_FILES_PATH, 'code'))
    FileUtils::mkpath(File::join(RAW_FILES_PATH, 'sandbox'))
    FileUtils::mkpath(File::join(RAW_FILES_PATH, 'pixelflut'))
    FileUtils::mkpath(GEN_FILES_PATH)
end
if PROFILE.include?(:pysandbox)
    FileUtils::cp('src/pysandbox/Gemfile', 'docker/pysandbox/')
end
if PROFILE.include?(:neo4j)
    FileUtils::mkpath(NEO4J_DATA_PATH)
    FileUtils::mkpath(NEO4J_LOGS_PATH)
end

system("docker-compose --project-name #{PROJECT_NAME} #{ARGV.join(' ')}")
