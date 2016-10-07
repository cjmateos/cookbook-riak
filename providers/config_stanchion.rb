# Cookbook Name:: riak
# Provider:: config_stanchion
#

action :config do
  begin
    config_dir = new_resource.config_dir
    logdir = new_resource.logdir
    user = new_resource.user
    group = new_resource.group

    stanchion_ip = new_resource.stanchion_ip
    stanchion_port = new_resource.stanchion_port

    riakcs_ip = new_resource.riakcs_ip
    riakcs_port = new_resource.riakcs_port

    riak_ip = new_resource.riak_ip
    riak_port = new_resource.riak_port

    # Load keys from s3_secrets data bag
    s3_secrets = Chef::DataBagItem.load("passwords", "s3_secrets") rescue s3_secrets = {}

    yum_package "stanchion" do
      action :upgrade
      flush_cache [ :before ]
    end

    user user do
      group group
      action :create
    end

    template "#{config_dir}/stanchion.conf" do
      source "stanchion.conf.erb"
      owner user
      group group
      mode 0644
      retries 2
      notifies :restart, "service[stanchion]", :delayed
      variables(:stanchion_ip => stanchion_ip, :stanchion_port => stanchion_port, \
        :riakcs_ip => riakcs_ip, :riakcs_port => riakcs_port, :riak_ip => riak_ip, :riak_port => riak_port, \
        :key_id => s3_secrets["key_id"], :key_secret => s3_secrets["key_secret"], :logdir => logdir)
    end

    service "stanchion" do
      service_name "stanchion"
      supports :status => true, :reload => true, :restart => true, :start => true, :enable => true
      action [:enable,:start]
    end

    Chef::Log.info("stanchion has been configurated correctly.")
  rescue => e
    Chef::Log.error(e.message)
  end
end

action :remove do
  begin
    config_dir = new_resource.config_dir
    logdir = new_resource.logdir

    service "stanchion" do
      supports :stop => true
      action :stop
    end

    dir_list = [
                 config_dir,
                 logdir
               ]

    # removing directories
    dir_list.each do |dirs|
      directory dirs do
        action :delete
        recursive true
      end
    end

    yum_package 'stanchion' do
      action :remove
    end

    Chef::Log.info("stanchion has been uninstalled correctly.")
  rescue => e
    Chef::Log.error(e.message)
  end
end
