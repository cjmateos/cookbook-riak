# Cookbook Name:: riak
# Provider:: config_riakcs
#

action :install do
  begin
    yum_package "riak-cs" do
      action :upgrade
      flush_cache [ :before ]
    end

    Chef::Log.info("Riak-cs has been installed correctly.")
  rescue => e
    Chef::Log.error(e.message)
  end
end

action :config do
  begin
    config_dir = new_resource.config_dir
    logdir = new_resource.logdir
    user = new_resource.user
    group = new_resource.group

    riakcs_ip = new_resource.riakcs_ip
    riakcs_port = new_resource.riakcs_port

    riak_ip = new_resource.riak_ip
    riak_port = new_resource.riak_port

    stanchion_ip = new_resource.stanchion_ip
    stanchion_port = new_resource.stanchion_port

    cdomain = new_resource.cdomain

    s3user = new_resource.s3user

    # Load keys from s3_secrets File
    #s3_secrets = Chef::DataBagItem.load("passwords", "s3_secrets") rescue s3_secrets = {}
    s3user_file = File.read('s3user') rescue s3user_file = nil
    s3_secrets = JSON.parse(s3user_file) unless s3user_file.nil?

    key_id = s3_secrets.nil? ? s3_secrets['key_id'] : "admin-key"
    key_secret = s3_secrets.nil? ? s3_secrets['key_secret'] : "admin-secret"

    user user do
      group group
      action :create
    end

    template "#{config_dir}/riak-cs.conf" do
      source "riak-cs.conf.erb"
      owner user
      group group
      mode 0644
      retries 2
      notifies :restart, "service[riak-cs]", :delayed
      variables(:riakcs_ip => riakcs_ip, :riakcs_port => riakcs_port, :riak_ip => riak_ip, \
        :riak_port => riak_port, :stanchion_ip => stanchion_ip, :stanchion_port => stanchion_port, \
        :cdomain => cdomain, :key_id => key_id, :key_secret => s3_secrets.nil? ? s3_secrets['key_secret'] : "admin-secret")
    end

    service "riak-cs" do
      service_name "riak-cs"
      supports :status => true, :reload => true, :restart => true, :start => true, :enable => true
      action [:enable,:start]
    end

    Chef::Log.info("Riak-cs has been configurated correctly.")
  rescue => e
    Chef::Log.error(e.message)
  end
end

action :remove do
  begin

    logdir = new_resource.logdir
    config_dir = new_resource.config_dir

    service "riak-cs" do
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

    yum_package 'riak-cs' do
      action :remove
    end

    Chef::Log.info("riak-cs has been uninstalled correctly.")
  rescue => e
    Chef::Log.error(e.message)
  end
end

action :create_user do
  begin
    s3cfg_file = new_resource.s3cfg_file

    # Load keys from s3_secrets data bag
    s3_secrets = Chef::DataBagItem.load("passwords", "s3_secrets") rescue s3_secrets = {}

    #if ((!File.exists?("/etc/redborder/s3user.txt") or !s3_secrets["key_created"] ) and File.exists?("/var/run/stanchion/stanchion.pid") and File.exists?("/var/run/riak-cs/riak-cs.pid"))
    execute "create_s3_user" do
      command "ruby /usr/lib/redborder/bin/rb_s3_user.rb -a" #Create admin user
      ignore_failure true
      not_if { ::File.exists?("/etc/redborder/s3user.txt") or !s3_secrets["key_created"]}
      action :run
      #notifies :run, "execute[force_chef_client_wakeup]", :delayed
    end

    template "#{s3cfg_file}" do
        source "s3cfg.erb"
        owner "root"
        group "root"
        mode 0600
        retries 2
        variables(:key_hostname => s3_secrets["hostname"], :key_location => s3_secrets["location"], :key_id => s3_secrets['key_id'], :key_secret => s3_secrets['key_secret'])
    end

  rescue => e
    Chef::Log.error(e.message)
  end
end

action :set_proxy do
  begin
    proxy_conf = new_resource.proxy_conf
    riakcs_ip = new_resource.riakcs_ip
    riakcs_port = new_resource.riakcs_port
    cdomain = new_resource.cdomain

    template "#{proxy_conf}" do
        source "riak-proxy.conf.erb"
        owner "root"
        group "root"
        mode 0644
        retries 2
        variables(:hostname => node["hostname"], :riakcs_ip => riakcs_ip, :riakcs_port => riakcs_port, :cdomain => cdomain)
        #notifies :restart, "service[nginx]", :delayed # TODO when nginx service is created
        notifies :run, "execute[nginx_restart]", :delayed
    end

    execute "nginx_restart" do
      command "systemctl restart nginx"
      ignore_failure true
      action :nothing
    end

  rescue => e
    Chef::Log.error(e.message)
  end
end

action :create_buckets do
  begin
    # Check if buckets has been created
    redborder-bucket = Chef::DataBagItem.load("rBglobal", "redborder-bucket") rescue bucket_created_dg =  {}
    bucket_created = redborder-bucket["created"]
    bucket_created = false  if bucket_created != true #it can be nil

    execute "create_buckets" do
      command "ruby /usr/lib/redborder/bin/rb_create_buckets.rb"
      ignore_failure true
      #only_if { !bucket_created and s3_secrets["key_created"] and node["redborder"]["services"]["riak"] and File.exists?("/var/run/stanchion/stanchion.pid") and File.exists?("/var/run/riak-cs/riak-cs.pid") }
      only_if { !bucket_created and node["redborder"]["services"]["riak"] and s3_secrets["key_created"]}
      action :run
      #notifies :run, "execute[force_chef_client_wakeup]", :delayed
      #notifies :run, "execute[create_buckets_delayed]", :delayed
    end

  rescue => e
    Chef::Log.error(e.message)
  end
end
