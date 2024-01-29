require './hyperv/tools.rb'
require 'json'

ENV["VAGRANT_DEFAULT_PROVIDER"] = "hyperv"

PUBLIC_SWITCH = "Ceph (Public)"

CLUSTER_SUBNET = "192.168.10"
CLUSTER_SWITCH = "Ceph (Cluster)"
N_NODES = 5

ssh_pub_key = File.readlines("ssh/id_rsa_vagrant.pub").first.strip

netcfg_shell = "cat <<EOL > /etc/netplan/02-netcfg.yaml
network:
  version: 2
  ethernets:
    eth1:
      dhcp4: no
      dhcp6: no
      addresses:
        - ADDRESS
EOL
"
# TRY to create Hyper-V virtual Switches if not exists
# Comment this section if you have trouble or you want to use existing switches
if ARGV[0] == "up"
  begin
    physical_adapters = list_physical_net_adapter
    physical_adapter = physical_adapters.find { |adapter| adapter["status"] == "Up" }
    unless switch_index(PUBLIC_SWITCH, "External", physical_adapter["description"])
      create_switch(PUBLIC_SWITCH, "External", physical_adapter["description"])
    end
    unless switch_index(CLUSTER_SWITCH, "Private")
      create_switch(CLUSTER_SWITCH, "Private")
    end
  rescue StandardError
    puts StandardError
    return
  end
end

Vagrant.configure("2") do |config|

  config.vm.box = "generic/ubuntu2004"
  config.vm.synced_folder ".", "/vagrant", disabled: true
  config.vm.provider :hyperv do |hv|
    hv.cpus = 4
    hv.enable_virtualization_extensions = true
    hv.memory = 4096
    hv.maxmemory = 4096
    hv.linked_clone = true
  end

  config.hostmanager.enabled = true
  config.hostmanager.manage_host = false # put true if you use your host to run ansible
  config.hostmanager.manage_guest = false # put true if you use vm to run ansible
  config.hostmanager.ignore_private_ip = false
  config.hostmanager.include_offline = true

  (1..N_NODES).each do |i|
    name = "node-#{i}"
    cluster_ip = "#{CLUSTER_SUBNET}.1#{i}/24"
    config.vm.define name do |node|
      node.vm.hostname = name

      # Hyper-V
      node.vm.provider :hyperv do |hv|
        hv.vmname = name
        # CHECK YOUR VIRTUAL SWITCH MANAGER RANGE IN YOUR HYPER-V
        hv.mac = "00155D38010#{i - 1}"
      end

      node.vm.network :public_network, bridge: PUBLIC_SWITCH

      node.trigger.after :all do |trigger|
        trigger.ruby do |env, machine|
          puts machine.config.vm.disks
          machine.config.vm.disks.each do |disk|
            puts disk.provider_config
          end
        end
      end

      # AFTER VagrantPlugins::HyperV::Action::Configure
      node.trigger.after :"VagrantPlugins::HyperV::Action::Configure", type: :action do |trigger|
        trigger.ruby do |env, machine|
          if "#{machine.provider_name}" == "hyperv"
            # Add CLUSTER_SWITCH adapter
            unless list_net_adapter(name).any? { |adapter| adapter["switch_name"] == CLUSTER_SWITCH }
              # CHECK YOUR VIRTUAL SWITCH MANAGER RANGE IN YOUR HYPER-V
              add_net_adapter(name, CLUSTER_SWITCH, "00155D38011#{i - 1}")
            end
          end
        end
      end

      # AFTER PROVISION
      node.trigger.after :provisioner_run, type: :hook do |trigger|

        trigger.ruby do |env, machine|
          if "#{machine.provider_name}" == "hyperv"
            (1..2).each do |d|
              disk_path = "./.vagrant/machines/#{name}/hyperv/Virtual Hard Disks/disk#{d}.vhdx"
              unless File.exist?(disk_path)
                create_vhd(disk_path, 20)
              end
              unless get_disks(name).any? { |disk| File.absolute_path(disk["path"]) == File.absolute_path(disk_path) }
                add_vhd(name, disk_path, "SCSI")
              end
            end
          end
        end
      end

      node.vm.provision "shell" do |shell|
        shell.inline = <<-SHELL
          if ! grep -q "#{ssh_pub_key}" "/home/vagrant/.ssh/authorized_keys"; then
            echo #{ssh_pub_key} >> /home/vagrant/.ssh/authorized_keys
          fi
        SHELL
      end

      netcfg = netcfg_shell.gsub("ADDRESS", cluster_ip)
      node.vm.provision "shell", inline: netcfg
      node.vm.provision "shell", inline: "netplan apply"
      node.vm.provision "shell", inline: "sysctl -w net.ipv6.conf.all.disable_ipv6=1"
    end
  end

  #   config.vm.define "ansible" do |ansible|
  #
  #     ansible.vm.hostname = "ansible"
  #     # Hyper-V
  #     ansible.vm.provider :hyperv do |hv|
  #       hv.vmname = "ansible"
  #       # CHECK YOUR VIRTUAL SWITCH MANAGER RANGE IN YOUR HYPER-V
  #       hv.mac = "00155D380120"
  #     end
  #     # disable ipv6
  #     ansible.vm.provision "shell", inline: "sysctl -w net.ipv6.conf.all.disable_ipv6=1"
  #
  #     # add ssh keys ans config
  #     ansible.vm.provision "shell" do |shell|
  #       ssh_priv_key = File.read("ssh/id_rsa_vagrant").strip
  #       config = File.read("ssh/config").strip
  #       ansible_nodes = File.read("ssh/config.d/ansible_nodes").strip
  #       shell.inline = <<-SHELL
  # mkdir -p /home/vagrant/.ssh/config.d
  # cat <<EOL > /home/vagrant/.ssh/id_rsa_vagrant.pub
  # #{ssh_pub_key}
  # EOL
  #
  # cat <<EOL > /home/vagrant/.ssh/id_rsa_vagrant
  # #{ssh_priv_key}
  # EOL
  #
  # chmod 600 /home/vagrant/.ssh/id_rsa_vagrant.pub
  # chmod 600 /home/vagrant/.ssh/id_rsa_vagrant
  # chown vagrant: /home/vagrant/.ssh/id_rsa_vagrant.pub
  # chown vagrant: /home/vagrant/.ssh/id_rsa_vagrant
  #
  # cat <<EOL > /home/vagrant/.ssh/config
  # #{config}
  # EOL
  #
  # cat <<EOL > /home/vagrant/.ssh/config.d/ansible_nodes
  # #{ansible_nodes}
  # EOL
  #       SHELL
  #     end
  #     # install pip
  #     ansible.vm.provision "shell" do |shell|
  #       # install apt install python3-pip
  #       shell.inline = <<-SHELL
  #         add-apt-repository -y ppa:ansible/ansible
  #         apt update
  #         apt install -y python3-pip
  #       SHELL
  #     end
  #   end
end