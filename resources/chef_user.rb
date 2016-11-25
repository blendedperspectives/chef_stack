#
# Cookbook Name:: chef
# Resource:: chef_user
#
# Copyright 2016 Chef Software Inc
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
# rubocop:disable LineLength

resource_name 'chef_user'
default_action :create

property :username, String, name_property: true
property :first_name, String, required: true
property :last_name, String, required: true
property :email, String, required: true
property :password, String
property :key, String
property :serveradmin, [TrueClass, FalseClass], default: false

load_current_value do
  node.run_state['chef-users'] ||= Mixlib::ShellOut.new('chef-server-ctl user-list').run_command.stdout
  current_value_does_not_exist! unless node.run_state['chef-users'].index(/^#{username}$/)
end

action :create do
  directory '/etc/opscode/users' do
    owner 'root'
    group 'root'
    mode '0700'
    recursive true
  end

  key = (property_is_set?(:key) ? key : "/etc/opscode/users/#{username}.pem")
  password = (property_is_set?(:password) ? new_resource.password : SecureRandom.base64(36))
  execute "create-user-#{username}" do
    # sensitive true
    retries 3
    command "chef-server-ctl user-create #{username} #{first_name} #{last_name} #{email} #{password} -f #{key}"
    not_if { node.run_state['chef-users'].index(/^#{username}$/) }
  end

  ruby_block 'append-user-to-users' do
    block do
      node.run_state['chef-users'] << "#{username}\n"
    end
  end
  execute "grant-server-admin-#{username}" do
    command "chef-server-ctl grant-server-admin-permissions #{username}"
    only_if { serveradmin }
  end
end

action :delete do
  execute "delete-user-#{username}" do
    retries 3
    command "chef-server-ctl user-delete #{username} --yes --remove-from-admin-groups"
    only_if { node.run_state['chef-users'].index(/^#{username}$/) }
  end

  ruby_block 'delete-user-to-users' do
    block do
      node.run_state['chef-users'] = node.run_state['chef-users'].gsub(/#{username}\n/, '')
    end
  end
end