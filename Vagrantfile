PUBLIC_NET="192.168.1."
PRIVATE_NET="192.168.56."
DOMAIN="domain.alt"

begin
	Vagrant.require_version ">= 2.0.0"
	COMPAT=""
rescue
	print("note: Current version of Vagrant is not support ALT Platforms with /etc/net.\n      Please, update Vagrant to version greater than 2.0.0\n")
	Vagrant.require_version "<= 1.9.4"
	COMPAT="true"
end

# Available ALT Platform based boxes:
# "mastersin/basealt-p8-server"
# "mastersin/basealt-p8-server-systemd"
# "mastersin/sisyphus-server-systemd"
# "mastersin/basealt-p8-workstation"

hosts=[
{
	:box => "mastersin/basealt-p8-server-systemd",
	:hostname => "server." + DOMAIN,
	:ip => "dhcp", # PUBLIC_NET + "150",
	:ip_int => PRIVATE_NET + "2",
	:ram => 1000
},
{
	:box => "mastersin/basealt-p8-workstation",
	:hostname => "client." + DOMAIN,
	:ip => "dhcp", # PUBLIC_NET + "151",
	:ip_int => PRIVATE_NET + "3",
	:ram => 1000,
	:nameserver => PRIVATE_NET + "2"
},
]

Vagrant.configure(2) do |config|
	config.vm.synced_folder ".", "/vagrant", disabled: true

	hosts.each do |machine|
		config.vm.define machine[:hostname] do |node|
			node.vm.box = machine[:box]

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
