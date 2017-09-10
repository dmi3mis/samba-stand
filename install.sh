#!/bin/bash -x

create_iface()
{
	local iface="$1"; shift
	local bootproto="$1"; shift
	mkdir -p /etc/net/ifaces/$iface
	cat > /etc/net/ifaces/$iface/options <<__EOF
BOOTPROTO=$bootproto
TYPE=eth
__EOF
	if [ "$bootproto" == "static" ]; then
		echo "$1/24" > /etc/net/ifaces/$iface/ipv4address
		shift
	fi
	iface_restart $iface
}

set_nameserver()
{
	local iface="$(get_host_iface)"
	local nameserver="$1"; shift
	local domain="${1-}"
	if [ -n "$domain" ]; then
		echo "domain $domain" > /etc/net/ifaces/$iface/resolv.conf
		echo "search $domain" >> /etc/net/ifaces/$iface/resolv.conf
	fi
	echo "nameserver $nameserver" >> /etc/net/ifaces/$iface/resolv.conf
	grep -q "interface_order=.*$iface " /etc/resolvconf.conf || sed -i "s/interface_order='\(.*\)'/interface_order='$iface \1'/" /etc/resolvconf.conf
	iface_restart $iface
}

iface_restart()
{
	local iface="$1"; shift
	ifdown $iface
	ifup $iface
}

set_hostname()
{
	sed -i "s/HOSTNAME=.*/HOSTNAME=$1/" /etc/sysconfig/network
	hostname $1
}

init_krb5_conf()
{
	local realm="$1"
	sed -i "s/#\?\(\s*default_realm\s*=\s*\).*/\1$realm/" /etc/krb5.conf
	sed -i "s/#\?\(\s*dns_lookup_kdc\s*=\s*\).*/\1true/" /etc/krb5.conf
	sed -i "s/#\?\(\s*dns_lookup_realm\s*=\s*\).*/\1false/" /etc/krb5.conf
}

update_smb_conf()
{
	local iface="$(get_host_iface)"
	if grep -q '^\s*interfaces\s*=' /etc/samba/smb.conf; then
		sed -i "s/\(\s*interfaces\s*=\).*/\1 lo $iface/" /etc/samba/smb.conf
	else
		sed -i "s/\(\[global\]\)/\1\n\tinterfaces = lo $iface/" /etc/samba/smb.conf
	fi
}

get_ip()
{
	local ip="$1"
	[ "$ip" == "dhcp" ] || echo -n "static "
	echo "$ip"
}

ip_link_grep_regexp='^[0-9]\+: \([[:alnum:]]\+\):'
ip_link_sed_regexp='s/^[0-9]\+: \([[:alnum:]]\+\):.*/\1/g'
get_host_iface()
{
	local iface_name="eth2"
	local iface_addr
	ip link show | grep "$ip_link_grep_regexp" | sed "$ip_link_sed_regexp" | while read iface; do
		iface_name="$iface"
		iface_addr=$(get_iface_ip "$iface")
		[ "$iface_addr" != "$host_ip" ] || break
	done
	echo $iface_name
}

ip_addr_awk_code='$1 == "inet" && $3 == "brd" { sub (/\/.*/,""); print $2 }'
get_iface_ip()
{
    local iface="$1"
    ip addr show $iface | awk "$ip_addr_awk_code"
}

disable_dhcpcd_resolvconf_hook()
{
	echo "nohook resolv.conf" >>/etc/dhcpcd.conf
	iface_restart eth0
	iface_restart eth1
}

set_etc_hosts()
{
	local ip="$1"; shift
	local host="$1"; shift
	local short="${host%%.*}"

	if grep -w -q "^[.:0-9a-f]\+.*\s$host" /etc/hosts; then
		sed -i "s/^\([.0-9a-f]\+.*\s$host\)/#\1/" /etc/hosts
	fi

	if grep -q "^$ip\s" /etc/hosts; then
		sed -i "s/^\($ip\s\).*/\1$host $short/" /etc/hosts
	else
		echo -e "$ip\t$host $short" >>/etc/hosts
	fi
}

disable_clear_on_logout()
{
	sed -i 's/^\(clear\)/#\1/' .bash_logout
}

disable_networkmanager_dns()
{
	test /etc/NetworkManager/NetworkManager.conf || return
	if grep -q '^\s*dns\s*=' /etc/NetworkManager/NetworkManager.conf; then
		sed -i "s/\(\s*dns\s*=\).*/\1=none/" /etc/NetworkManager/NetworkManager.conf
	else
		sed -i "s/\(\[main\]\)/\1\n\tdns=none/" /etc/NetworkManager/NetworkManager.conf
	fi
	systemctl restart NetworkManager
	if resolvconf -l | grep -q NetworkManager; then
		resolvconf -d NetworkManager
	fi
	resolvconf -u
}

compat="$1"; shift
pub_ip="$1"; shift
host_ip="$1"; shift
host_name="$1"; shift
host_nameserver="${1-}"

if [ "$compat" == "true" ]; then
	create_iface eth1 $(get_ip "$pub_ip")
	create_iface eth2 $(get_ip "$host_ip")
	set_hostname "$host_name"
fi

apt-get update
apt-get dist-upgrade -y -qq
apt-get clean

HOST=$(hostname -s)
DOMAIN=$(hostname -d)
REALM="$(hostname -d | tr [a-z] [A-Z])"
WORKGROUP=${REALM%%.*}
PASSWORD='Pa$$word'

COMMON_TOOLS="bind-utils krb5-kinit"

# Due https://bugzilla.altlinux.org/show_bug.cgi?id=33427
COMMON_TOOLS+=" ldb-tools"

disable_clear_on_logout

case "$(hostname -s)" in
	client)
		if rpm -q samba --queryformat= 2>/dev/null; then
			service smb stop
			chkconfig smb off
		fi
		apt-get install -y -qq samba-client sssd-ad $COMMON_TOOLS
		apt-get clean
		apt-get install -y -qq task-auth-ad-sssd
		apt-get clean
		init_krb5_conf "$REALM"
		ln -s /usr/lib64/ldb/modules/ldb /usr/lib64/samba/ldb
		if [ -n "$host_nameserver" ]; then
			disable_networkmanager_dns
			disable_dhcpcd_resolvconf_hook
			set_nameserver "$host_nameserver" "$DOMAIN"
		fi
		system-auth write ad $DOMAIN $HOST $WORKGROUP 'Administrator' "$PASSWORD"
		;;
	server)
		apt-get install -y -qq samba-DC samba-DC-client $COMMON_TOOLS
		apt-get clean
		mv /etc/samba/smb.conf /etc/samba/smb.conf.saved
		init_krb5_conf "$REALM"
		samba-tool domain provision --realm="$REALM" --domain "$WORKGROUP" --adminpass="$PASSWORD" --dns-backend=SAMBA_INTERNAL --server-role=dc --use-rfc2307 --host-ip="$host_ip"
		disable_dhcpcd_resolvconf_hook
		set_etc_hosts "$host_ip" "$host_name"
		update_smb_conf
		set_nameserver 127.0.0.1 "$DOMAIN"
		service samba start
		chkconfig samba on
		;;
esac
