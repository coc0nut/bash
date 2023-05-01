# This bash script sets up initiative ubuntu server for virtual systems
# It asks how many network cards and if you are using vmware or virtualbox.
# Depending on your answers, it sets up networkinterfaces, dhcp-server and iptables rules.
# It's for personal purposes. Not intended for public use.

# Author Harald Trohne

#!/bin/bash
# run as sudo

echo "This script assumes that you only operate with /24 networks."

echo "Set a password for root:"
passwd root

echo "Installing software..."
sleep 1
apt update && apt upgrade -y
apt install net-tools isc-dhcp-server iptables-persistent -y

echo "Activating ip routing..."
sleep 1
sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf && sysctl -p

echo "How many network cards is intalled?"
read ANSWER

while [ "$CHOICE" != "1" ] && [ "$CHOICE" != "2" ]
do
    read -p "Type "1" for virtualbox or "2" for vmware: " CHOICE
    #read CHOICE
    if [ "$CHOICE" = "1" ]; then
        for (( i = 0, a=7; i<$ANSWER; i++, a++ )); do
            if [ "$i" = 0 ]; then
                eval "eth0=enp0s3"
            else
                var_name="eth$i"
                eval "${var_name}"=enp0s$a
            fi
        done
    elif [ "$CHOICE" = "2" ]; then
        for (( i = 0, a=33; i<$ANSWER; i++, a++ )); do
            var_name="eth$i"
            eval "${var_name}"=ens$a
        done
    fi
done

case $ANSWER in
    1)
        netplan_text="network:\n  renderer: networkd\n  ethernets:\n    ${eth0}:\n      dhcp4: true\n  version: 2"
        ;;
    2)
        read -p "Network ID for your network (e.g 192.168.0.0): " net_1
        read -p "Node number: " a
        netplan_text="network:\n  renderer: networkd\n  ethernets:\n    ${eth0}:\n      dhcp4: true\n    ${eth1}:\n      addresses:\n        - ${net_1::-1}${a}/24\n  version: 2"
        ;;
    3)
        read -p "Network ID for your first network (e.g 192.168.0.0): " net_1
        read -p "Network ID for your second network (e.g 10.0.1.0): " net_2
        read -p "Node number: " a
        netplan_text="network:\n  renderer: networkd\n  ethernets:\n    ${eth0}:\n      dhcp4: true\n    ${eth1}:\n      addresses:\n        - ${net_1::-1}${a}/24\n    ${eth2}:\n      addresses:\n        - ${net_2::-1}1/24\n  version: 2"
        ;;
esac

echo "Setting up netplan config..."
sleep 1
echo -e "$netplan_text" > /etc/netplan/net_cfg.yaml
rm -rf /etc/netplan/00-installer-config.yaml
netplan apply

read -p "Set up dhcpd..? [y/N]: " ANSWER_dhcp
case "$ANSWER_dhcp" in
    [yY] | [yY][eE][sS])
        if [ "$ANSWER" = "2" ]; then
            dhcp_range="$net_1"
        elif [ "$ANSWER" = "3" ]; then
            dhcp_range="$net_2"
        else
            echo "No interface available for dhcpd"
        fi
        if [ "$dhcp_range" ]; then
            dhcp_text="subnet $dhcp_range netmask 255.255.255.0 {\n    range ${dhcp_range::-1}20 ${dhcp_range::-1}100;\n    option routers ${dhcp_range::-1}1;\n}"
            sed -i '42i'"$dhcp_text" /etc/dhcp/dhcpd.conf
            systemctl restart isc-dhcp-server
        fi
        ;;
    [nN] | [nN][oO])
        echo "Continuing..."
        ;;
esac

read -p "Would you like to set up routes? [y/N]: " ANSWER
case "$ANSWER" in
    [yY] | [yY][eE][sS])
        read -p "Route to: " route_to
        read -p "Route via: " route_via
        routing="\     \ routes:\n\        \- to: ${route_to}/24\n\         \ via: ${route_via}"
        sed -i '9i'"$routing" /etc/netplan/net_cfg.yaml
        netplan apply
        ;;
    [nN] | [nN][oO])
        echo "Continuing..."
        ;;
esac

echo "Setting up simple iptables rules for sharing internet connection..."
read -p "Do you want to set up iptables? [y/N]: " ANSWER
case "$ANSWER" in
    [yY] | [yY][eE][sS])
        read -p "Is the server a wan interface? y/N " ANSWER
        case "$ANSWER" in
            [yY] | [yY][eE][sS])
                iptables -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
                iptables -A INPUT -p udp -m udp --dport 53 -j ACCEPT
                iptables -A INPUT -p tcp -m tcp --dport 22 -j ACCEPT
                iptables -A INPUT -p icmp -m icmp --icmp-type 8 -j ACCEPT
                iptables -A INPUT -j DROP                
                iptables -A FORWARD -j DROP
                if [ "$eth2" ]; then
                    iptables -I FORWARD -i "$eth0" -o "$eth2" -m state --state RELATED,ESTABLISHED -j ACCEPT
                    iptables -I FORWARD -i "$eth2" -o "$eth0" -j ACCEPT
                    iptables -I FORWARD -i "$eth1" -o "$eth2" -j ACCEPT
                    iptables -I FORWARD -i "$eth2" -o "$eth1" -j ACCEPT
                fi
                if [ "$eth1" ]; then
                    iptables -I FORWARD -i "$eth0" -o "$eth1" -m state --state RELATED,ESTABLISHED -j ACCEPT 
                    iptables -I FORWARD -i "$eth1" -o "$eth0" -j ACCEPT
                    iptables -t nat -A POSTROUTING -o "$eth0" -j MASQUERADE
                    
                fi
                iptables-save > /etc/iptables/rules.v4
                ;;
            [nN] | [nN][oO])
                iptables -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
                iptables -A INPUT -i "$eth0" -p udp -m udp --dport 53 -j ACCEPT
                iptables -A INPUT -p tcp -m tcp --dport 80 -j ACCEPT
                iptables -A INPUT -p tcp -m tcp --dport 22 -j ACCEPT
                iptables -A INPUT -p icmp -m icmp --icmp-type 8 -j ACCEPT
                iptables -A INPUT -j DROP             
                iptables -A FORWARD -j DROP
                if [ "$eth1" ]; then
                    iptables -I FORWARD -i "$eth1" -o "$eth0" -j ACCEPT
                    iptables -I FORWARD -i "$eth0" -o "$eth1" -j ACCEPT
                fi
                iptables-save > /etc/iptables/rules.v4
                ;;
        esac
        ;;
    [nN] | [nN][oO])
        echo "Continuing..."
        ;;
esac

echo "Operation successful..."
