# encoding: UTF-8
#
# Cookbook Name:: postfixadmin
# Recipe:: default
# Author:: Xabier de Zuazo (<xabier@onddo.com>)
# Copyright:: Copyright (c) 2013-2015 Onddo Labs, SL. (www.onddo.com)
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

::Chef::Recipe.send(:include, Opscode::OpenSSL::Password)
::Chef::Recipe.send(:include, PostfixAdmin::PHP)
::Chef::Recipe.send(:include, Chef::EncryptedAttributesHelpers)

if %w(centos).include?(node['platform']) && node['platform_version'].to_i >= 7
  include_recipe 'yum-epel' # required for php-imap
end

db_type = node['postfixadmin']['database']['type']

pkgs_php_db =
  if db_type != 'requirements' && node['postfixadmin']['packages'].key?(db_type)
    node['postfixadmin']['packages'][db_type]
  else
    fail "Unknown database type: #{db_type}"
  end
pkgs_php_db.each do |pkg|
  package pkg do
    action :install
  end
end

node['postfixadmin']['packages']['requirements'].each do |pkg|
  package pkg do
    action :install
  end
end

self.encrypted_attributes_enabled = node['postfixadmin']['encrypt_attributes']

db_password =
  encrypted_attribute_write(%w(postfixadmin database password)) do
    secure_password
  end
setup_password =
  encrypted_attribute_write(%w(postfixadmin setup_password)) do
    secure_password
  end
setup_password_encrypted =
  encrypted_attribute_write(%w(postfixadmin setup_password_encrypted)) do
    encrypt_setup_password(setup_password, generate_setup_password_salt)
  end

chef_gem 'sequel'

if %w(localhost 127.0.0.1).include?(node['postfixadmin']['database']['host'])
  include_recipe "postfixadmin::#{db_type}"

  case db_type
  when 'mysql'

    mysql2_chef_gem 'default' do
      client_version '5.6'
      action :install
    end
    
    service 'mysql' do
      action :restart
    end

    mysql_connection_info = {
      host: node['postfixadmin']['database']['host'],
      username: 'root',
      password: encrypted_attribute_read(
        %w(postfixadmin mysql server_root_password)
      )
    }

    mysql_database node['postfixadmin']['database']['name'] do
      connection mysql_connection_info
      action :create
    end

    mysql_database_user node['postfixadmin']['database']['user'] do
      connection mysql_connection_info
      database_name node['postfixadmin']['database']['name']
      host node['postfixadmin']['database']['host']
      password db_password
      privileges [:all]
      action :grant
    end

  when 'postgresql'

    include_recipe 'postgresql::ruby'

    postgresql_connection_info = {
      host: 'localhost',
      username: 'postgres',
      password: node['postgresql']['password']['postgres']
    }

    postgresql_database node['postfixadmin']['database']['name'] do
      connection postgresql_connection_info
      action :create
    end

    postgresql_database_user node['postfixadmin']['database']['user'] do
      connection postgresql_connection_info
      host node['postfixadmin']['database']['host']
      password db_password
      action :create
    end

    postgresql_database_user node['postfixadmin']['database']['user'] do
      connection postgresql_connection_info
      database_name node['postfixadmin']['database']['name']
      host node['postfixadmin']['database']['host']
      password db_password
      privileges [:all]
      action :grant
    end

    # Based on @phlipper work from:
    # https://github.com/phlipper/chef-postgresql
    language = 'plpgsql'
    dbname = node['postfixadmin']['database']['name']
    execute "createlang #{language} #{dbname}" do
      user 'postgres'
      not_if "psql -c 'SELECT lanname FROM pg_catalog.pg_language' #{dbname} "\
        "| grep '^ #{language}$'", user: 'postgres'
    end

  else
    fail "Unknown database type: #{db_type}"
  end
end # if database in localhost

ark 'postfixadmin' do
  url node['postfixadmin']['url']
  version node['postfixadmin']['version']
  checksum node['postfixadmin']['checksum']
end

web_server = node['postfixadmin']['web_server']
if %w(apache nginx).include?(web_server)
  include_recipe "postfixadmin::#{web_server}"
  web_group = node[web_server]['group']
else
  web_group = nil
end

template 'config.local.php' do
  path "#{node['ark']['prefix_root']}/postfixadmin/config.local.php"
  source 'config.local.php.erb'
  owner 'root'
  group web_group
  mode '0640'
  variables(
    db_type: db_type,
    db_host: node['postfixadmin']['database']['host'],
    db_user: node['postfixadmin']['database']['user'],
    db_password: db_password,
    db_name: node['postfixadmin']['database']['name'],
    setup_password: setup_password_encrypted,
    conf: node['postfixadmin']['conf']
  )
end
