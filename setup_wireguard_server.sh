# BASH script for easily setting up WireGuard VPN Server and Clients
# Author: Anjan Roy | September, 2025
#
# I have been using WireGuard as my personal VPN solution for couple of years now.
# Before that I fiddled around with OpenVPN, sometimes it worked and sometimes it did not. I didn't actually like it.
# WireGuard is simple and efficient. It just works. Originally I found a really helpful blog post on DigitalOcean,
# titled "How To Set Up WireGuard on Ubuntu 20.04" @ https://www.digitalocean.com/community/tutorials/how-to-set-up-wireguard-on-ubuntu-20-04.
# I followed it step by step to setup my first WireGuard server. But running those same set of commands
# again and again is not charming! Hence this is an attempt to help partially automate setup of new
# WireGuard server on Ubuntu machine running on some cloud service provider's shared infra or my little Raspberry Pi.
# I mostly use Ubuntu or Debian as my choice of OS for running servers. But it should not be very hard for one
# to tweak it to support other Linux distributions.
#
# This script doesn't intend to replace DigitalOcean's above linked guide by any means,
# rather it attempts to make it easy when one needs to run those commands again and again.
# A curious soul should definitely go and check the guide out. DigitalOcean has some of the
# best guides written in Devops domain, so definitely a huge respect to what they are putting out there.
#
# How is one supposed to use it?
#
# - I'll just go to AWS or DigitalOcean to grab a Linux VM.
# - Transfer this little BASH script to that machine.
# - Execute this script.
# - Successful execution should produce another script in the same directory, named `setup_wireguard_client.sh`.
# - Running `sudo wg` should show you the status of running WireGuard server.
# - Go ahead and open default WireGuard server port 51820 in VM provider's firewall configuration page for both IPv4 and IPv6 network stacks.
# - For DNS, HTTP, HTTPS and other protocol traffic, you have to open those ports too.
# - Now that our WireGuard server should be ready to accept traffic, let's setup clients.
# - We can use our generated BASH script `setup_wireguard_client.sh` to setup as many peers as possible.
# - Before setting up first peer, open the `setup_wireguard_client.sh` file once and check a BASH variable `PEER_ID` defined at top.
# - For first peer, it should be fine. But for any new peer, like second or third, you need to bump up that number.
# - Ideally, for every new peer that you want to add to this WireGuard server, one will increment that number by 1, starting from 2, until it reaches 254.
# - In essence, for this WireGuard server that you just setup, you can connect upto 253 peers.
# - Now go ahead and execute the client setup script, grab the `peer_.conf` file it just output. `_` is `PEER_ID`.
# - You can use this peer configuration file in your mobile or desktop WireGuard clients.

echo "This BASH script helps you setup WireGuard VPN server and clients."
read -p "Have you read this script and understand what it does to your system? (y/n): " response
if [[ "$response" != "y" && "$response" != "Y" ]]; then
    echo "Please go through the script before running it. Exiting."
    exit 1
fi
echo "Going ahead with setting up WireGuard server"

echo "Updating system and installing WireGuard"
sudo apt update
sudo apt install wireguard -y

echo "Generating WireGuard server private + public keypair"
WG_PRIV_KEY=$(wg genkey)
WG_PUB_KEY=$(echo $WG_PRIV_KEY | wg pubkey)

echo "Writing WireGuard server private + public keypair to respective files"
echo $WG_PRIV_KEY | sudo tee /etc/wireguard/private.key
echo $WG_PUB_KEY | sudo tee /etc/wireguard/public.key

sudo chmod go= /etc/wireguard/private.key

echo "Computing pseudo-random IPv6 address prefix"
DATE=$(date +%s%N)
MACHINE_ID=$(cat /var/lib/dbus/machine-id)
SHA256_DIGEST=$(printf $DATE$MACHINE_ID | sha256sum)
IPV6_ADDRESS_PREFIX=$(printf $SHA256_DIGEST | cut -c 55-)
IPV6_ADDRESS=$(printf "fd%s:%s:%s::1/64" $(echo $IPV6_ADDRESS_PREFIX | cut -c 1-2) $(echo $IPV6_ADDRESS_PREFIX | cut -c 3-6) $(echo $IPV6_ADDRESS_PREFIX | cut -c 7-10))
WG_CONFIG_FILE="/etc/wireguard/wg0.conf"

echo "Figuring out publicly visible IPv4 address of WireGuard server"
PUBLIC_IP_OF_WG_SERVER=$(curl ipinfo.io/ip)

echo "Writing WireGuard server's initial configuration file"
cat << EOF > $WG_CONFIG_FILE
[Interface]
PrivateKey = $WG_PRIV_KEY
Address = 10.8.0.1/24, $IPV6_ADDRESS
ListenPort = 51820
SaveConfig = true
EOF

echo "Updating WireGuard server's network configuration to forward both IPv4 and IPv6 traffic"
echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf
echo "net.ipv6.conf.all.forwarding=1" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

echo "Updating WireGuard server configuration file to add firewall rules"
INTERFACE=$(ip route list default | awk '{for (i=1; i<=NF; i++) if ($i == "dev") {print $(i+1); exit}}')

{
    printf "PostUp = ufw route allow in on wg0 out on %s\n" "$INTERFACE"
    printf "PostUp = iptables -t nat -I POSTROUTING -o %s -j MASQUERADE\n" "$INTERFACE"
    printf "PostUp = ip6tables -t nat -I POSTROUTING -o %s -j MASQUERADE\n" "$INTERFACE"
    printf "PreDown = ufw route delete allow in on wg0 out on %s\n" "$INTERFACE"
    printf "PreDown = iptables -t nat -D POSTROUTING -o %s -j MASQUERADE\n" "$INTERFACE"
    printf "PreDown = ip6tables -t nat -D POSTROUTING -o %s -j MASQUERADE\n" "$INTERFACE"
} >> "$WG_CONFIG_FILE"

sudo ufw allow 51820/udp
sudo ufw allow OpenSSH

sudo ufw disable
sudo ufw enable
sudo ufw status

echo "Enabling and starting the WireGuard server with systemd"
sudo systemctl enable wg-quick@wg0.service
sudo systemctl start wg-quick@wg0.service
sudo systemctl status wg-quick@wg0.service

echo "Wireguard server should be running"
sudo wg

# ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

WG_CLIENT_SETUP_SCRIPT="setup_wireguard_client.sh"
cat << EOF > $WG_CLIENT_SETUP_SCRIPT
echo "This BASH script helps you setup WireGuard VPN client for an already setup WireGuard server."
read -p "Have you read this script and understand what it does to your system? (y/n): " response
if [[ "\$response" != "y" && "\$response" != "Y" ]]; then
    echo "Please go through the script before running it. Exiting."
    exit 1
fi
echo "Going ahead with setting up WireGuard client"

# For setting up first peer, do not change PEER_ID, keep it 2.
# For every new peer that you setup for this WireGuard server, continue to increment it by 1.
# The max value you can set for PEER_ID is 254. Meaning a total of 253 peers can be setup for a single WireGuard server.
PEER_ID=2
echo "Setting up WireGuard peer with ID: \$PEER_ID"

echo "Generating WireGuard server private + public keypair"
WG_PRIV_KEY=\$(wg genkey)
WG_PUB_KEY=\$(echo \$WG_PRIV_KEY | wg pubkey)

IPV6_ADDRESS_PREFIX=$(echo $IPV6_ADDRESS_PREFIX)
IPV6_ADDRESS=$(printf "fd%s:%s:%s::%s/64" $(echo $IPV6_ADDRESS_PREFIX | cut -c 1-2) $(echo $IPV6_ADDRESS_PREFIX | cut -c 3-6) $(echo $IPV6_ADDRESS_PREFIX | cut -c 7-10) \$PEER_ID)
WG_CONFIG_FILE=\$(printf "peer%s.conf" \$PEER_ID)

echo "Writing WireGuard peer configuration file"
cat << EOF > \$WG_CONFIG_FILE
[Interface]
PrivateKey = \$WG_PRIV_KEY
Address = \$(printf "10.8.0.%s/24" \$PEER_ID)
Address = \$IPV6_ADDRESS

[Peer]
PublicKey = $WG_PUB_KEY
AllowedIPs = 10.8.0.0/24, $IPV6_ADDRESS
Endpoint = $PUBLIC_IP_OF_WG_SERVER:51820
EOF

echo "Adding WireGuard peer's public key to the WireGuard server"
sudo wg set wg0 peer \$WG_PUB_KEY allowed-ips \$(printf "10.8.0.%s/24" $PEER_ID),\$IPV6_ADDRESS

echo "Now WireGuard client configuration file \$WG_CONFIG_FILE should be ready to add to the application"
EOF

# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

echo "WireGuard client setup script $WG_CLIENT_SETUP_SCRIPT should be ready to use"
echo "Go ahead and give it a read, before you run it"
