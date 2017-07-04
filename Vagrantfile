PUBLIC_NET="192.168.1."
PRIVATE_NET="192.168.56."
DOMAIN="domain.alt"

begin
	Vagrant.require_version "<= 1.9.4"
	COMPAT="true"
rescue
# Disable compat after ALT Platform support pull request
# will be pushed and new version fo Vagrant will be relased:
# https://github.com/mitchellh/vagrant/pull/8746
#	Vagrant.require_version "> 1.9.6"
	print("note: Current version of Vagrant is not support ALT Platforms with /etc/net yet.\n      Get patch from https://github.com/mitchellh/vagrant/pull/8746\n")
	COMPAT=""
end

hosts=[
{
	:hostname => "server." + DOMAIN,
	:ip => "dhcp", # PUBLIC_NET + "150"
	:ip_int => PRIVATE_NET + "2",
	:ram => 1000
},
{
	:hostname => "client." + DOMAIN,
	:ip => "dhcp", # PUBLIC_NET + "151"
	:ip_int => PRIVATE_NET + "3",
	:ram => 1000,
	:nameserver => PRIVATE_NET + "2"
},
]

Vagrant.configure(2) do |config|
	config.vm.synced_folder ".", "/vagrant", disabled: true

	hosts.each do |machine|
		config.vm.define machine[:hostname] do |node|
			#node.vm.box = "mastersin/basealt-p8-server"
			node.vm.box = "mastersin/basealt-p8-server-systemd"
			#node.vm.box_url = "http://files.vagrantup.com/mastersin/basealt-p8-server.box"
			#node.vm.box_url = "http://files.vagrantup.com/mastersin/basealt-p8-server-systemd.box"

			node.vm.usable_port_range = (2250..2300)
			node.vm.hostname = machine[:hostname]

			if (machine[:ip] == "dhcp")
				node.vm.network "public_network", bridge: 'eth0'
			else
				node.vm.network "public_network", ip: machine[:ip], netmask: 24, bridge: 'eth0'
			end

			if (machine[:ip_int] == "dhcp")
				node.vm.network "private_network", virtualbox__intnet: "intnet"
			else
				node.vm.network "private_network", ip: machine[:ip_int], netmask: 24, virtualbox__intnet: "intnet"
			end

			args = [COMPAT, machine[:ip], machine[:ip_int], machine[:hostname]]
			if (!machine[:nameserver].nil?)
				args << machine[:nameserver]
			end
			node.vm.provision :shell, :path => "install.sh", :args => args

			node.vm.provider "virtualbox" do |vb|
				vb.customize ["modifyvm", :id, "--memory", machine[:ram]]
				vb.name = machine[:hostname]
			end
		end
	end
end
