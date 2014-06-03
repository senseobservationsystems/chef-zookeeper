#
# Cookbook Name:: zookeeper
# Recipe:: Exhibitor
#
# Copyright 2013, Simple Finance Technology Corp.
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

include_recipe "runit"

package 'patch' do
  action :nothing
end.run_action(:install)

include_recipe "zookeeper::zookeeper"

[node[:exhibitor][:install_dir],
  node[:exhibitor][:snapshot_dir],
  node[:exhibitor][:transaction_dir],
  node[:exhibitor][:log_index_dir]
].uniq.each do |dir|
  directory dir do
    owner node[:zookeeper][:user]
    mode "0755"
  end
end

node.default[:exhibitor][:jar_dest] = exhibitor_jar = ::File.join(node[:exhibitor][:install_dir], "#{node[:exhibitor][:version]}.jar")

if !::File.exists?(exhibitor_jar)
  if node[:exhibitor][:install_method] == 'download'
    remote_file ::File.join(exhibitor_jar) do
      owner "root"
      mode "0644"
      source node[:exhibitor][:mirror]
      checksum node[:exhibitor][:checksum]
      action :create
    end
  else  #build exhibitor jar using gradle
    include_recipe "zookeeper::_exhibitor_build"
  end
end

check_script = ::File.join(node[:exhibitor][:script_dir], 'check-local-zk.py')
template check_script do
  owner node[:zookeeper][:user]
  mode "0744"
  variables(
    exhibitor_port: node[:exhibitor][:opts][:port],
    localhost: node[:exhibitor][:opts][:hostname] )
end

if node[:exhibitor][:opts][:configtype] != "file"
    node.default[:exhibitor][:opts].delete(:fsconfigdir)
end

if node[:exhibitor][:opts][:configtype] == 's3' &&
    node[:exhibitor].attribute?(:s3key) &&
    node[:exhibitor].attribute?(:s3secret)
  s3_creds = "#{node[:exhibitor][:install_dir]}/exhibitor.s3.properties"
  node.default[:exhibitor][:opts][:s3credentials] = s3_creds
  template s3_creds do
    source "exhibitor.s3.properties.erb"
    owner node[:zookeeper][:user]
    mode "0440"
    variables(
      :s3key => node[:exhibitor][:s3key],
      :s3secret => node[:exhibitor][:s3secret] )
  end
end

log4j_props = ::File.join(node[:exhibitor][:install_dir], "log4j.properties")
template log4j_props do
  source "log4j.properties.erb"
  owner "root"
  group "root"
  mode "0644"
  variables(
      :loglevel => node[:exhibitor][:loglevel]
  )
end

template node[:exhibitor][:opts][:defaultconfig] do
  source "exhibitor.properties.erb"
  owner node[:zookeeper][:user]
  mode "0644"
  variables(
    :snapshot_dir => node[:exhibitor][:snapshot_dir],
    :transaction_dir => node[:exhibitor][:transaction_dir],
    :log_index_dir => node[:exhibitor][:log_index_dir])
end

runit_service "exhibitor" do
  action [:enable, :start]
  default_logger true
  options({
    user: node[:zookeeper][:user],
    jar: exhibitor_jar,
    log4j_props: log4j_props,
    opts: node[:exhibitor][:opts] 
  })
end
