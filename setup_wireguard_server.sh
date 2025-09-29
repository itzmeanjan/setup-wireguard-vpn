#!/bin/bash

# BASH script for easily setting up WireGuard VPN Server and Clients
# Author: Anjan Roy | September, 2025
# Repository: https://github.com/itzmeanjan/setup-wireguard-vpn
# License: BSD 3-Clause License
#
# I have been using WireGuard as my personal VPN solution for couple of years now.
# Before that I fiddled around with OpenVPN, sometimes it worked and sometimes it did not. I didn't actually like it.
# WireGuard is simple and efficient. It just works. Originally I found a really helpful blog post on DigitalOcean,
# titled "How To Set Up WireGuard on Ubuntu 20.04" @ https://www.digitalocean.com/community/tutorials/how-to-set-up-wireguard-on-ubuntu-20-04.
# I followed it step by step to setup my first WireGuard server. But running those same set of commands
# again and again is not really charming! Hence this is an attempt to partially automate setup of new
# WireGuard server on Ubuntu, running on some cloud service provider's shared infra or my little Raspberry Pi.
# I mostly use Ubuntu or Debian as my choice of OS for running servers. But it should not be very hard for one
# to tweak it to support other Linux distributions.
#
# This script doesn't intend to replace DigitalOcean's above linked guide by any means,
# rather it attempts to make it easy when one needs to run those commands again and again.
# A curious soul should definitely go and check the original guide out. DigitalOcean has some of the
# best written guides in Devops domain, so definitely a huge respect for what they are putting out there.
#
# How is one supposed to use it?
#
# - Go to AWS or DigitalOcean to grab a Linux VM.
# - Transfer this little BASH script to that machine.
# - Execute this script `$ sudo bash setup_wireguard_server.sh`.
# - Successful execution should produce another script in the same directory, named `setup_wireguard_client.sh`.
# - Running `sudo wg` should show you the status of running WireGuard server.
# - Go ahead and open default WireGuard server port 51820 in VM provider's firewall configuration page for both IPv4 and IPv6 network stacks.
# - For DNS, HTTP, HTTPS and other protocol traffic, you have to open those ports too.
# - Now that our WireGuard server should be ready to accept traffic, let's setup clients.
# - We can use our generated BASH script `setup_wireguard_client.sh` to setup as many peers as possible.
# - Before setting up first peer, open the `setup_wireguard_client.sh` file once and look for a BASH variable `PEER_ID` defined at top.
# - For first peer, don't change its value. But for any new peer, like second or third, you need to bump up that number.
# - Ideally, for every new peer that you want to add to this WireGuard server, one will increment that number by 1, starting from 2, until it reaches 254.
# - In essence, for this WireGuard server that you just setup, you can connect upto 253 peers.
# - Now go ahead and execute the client setup script, grab the `peer_.conf` file it just output. `_` is `PEER_ID`.
# - Finally, you can use this peer configuration file in your mobile or desktop WireGuard clients.
#
# Enjoy WireGuard!

echo "[+] This BASH script helps you setup WireGuard VPN server and clients."
read -p "[?] Have you read this script and understand what it does to your system? (y/n): " response
if [[ "$response" != "y" && "$response" != "Y" ]]; then
    echo "[!] Please go through the script before running it. Exiting."
    exit 1
fi
echo "[+] Going ahead with setting up WireGuard server."

echo "[+] Updating system and installing WireGuard."
sudo apt-get update
sudo apt-get install wireguard -y

echo "[+] Generating WireGuard server private + public keypair."
WG_PRIV_KEY=$(wg genkey)
WG_PUB_KEY=$(echo $WG_PRIV_KEY | wg pubkey)

echo "[+] Writing WireGuard server private + public keypair to respective files."
echo $WG_PRIV_KEY | sudo tee /etc/wireguard/private.key
echo $WG_PUB_KEY | sudo tee /etc/wireguard/public.key

sudo chmod go= /etc/wireguard/private.key

echo "[+] Computing pseudo-random IPv6 address prefix."
DATE=$(date +%s%N)
MACHINE_ID=$(cat /var/lib/dbus/machine-id)
SHA256_DIGEST=$(printf $DATE$MACHINE_ID | sha256sum)
IPV6_ADDRESS_PREFIX=$(printf $SHA256_DIGEST | cut -c 55-)
IPV6_ADDRESS=$(printf "fd%s:%s:%s::1/64" $(echo $IPV6_ADDRESS_PREFIX | cut -c 1-2) $(echo $IPV6_ADDRESS_PREFIX | cut -c 3-6) $(echo $IPV6_ADDRESS_PREFIX | cut -c 7-10))
WG_CONFIG_FILE="/etc/wireguard/wg0.conf"

echo "[+] Figuring out publicly visible IPv4 address of WireGuard server."
PUBLIC_IP_OF_WG_SERVER=$(curl -s ipinfo.io/ip)

echo "[+] Writing WireGuard server's initial configuration file."
cat << EOF > $WG_CONFIG_FILE
[Interface]
PrivateKey = $WG_PRIV_KEY
Address = 10.8.0.1/24, $IPV6_ADDRESS
ListenPort = 51820
MTU = 1420
SaveConfig = true
EOF

echo "[+] Updating WireGuard server's network configuration to forward both IPv4 and IPv6 traffic."
echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf
echo "net.ipv6.conf.all.forwarding=1" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

echo "[+] Updating WireGuard server configuration file to add firewall rules."
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

echo "[+] Enabling and starting the WireGuard server with systemd."
sudo systemctl enable wg-quick@wg0.service
sudo systemctl start wg-quick@wg0.service
sudo systemctl status wg-quick@wg0.service

echo "[+] Wireguard server should be running."
sudo wg

# ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

echo "[+] Generating WireGuard client setup BASH script."
WG_CLIENT_SETUP_SCRIPT="setup_wireguard_client.sh"

# We use 'EOF' (with single quotes) to prevent the shell from expanding
# variables within this block. This treats the entire block as a literal string.
# We then use `sed` to selectively replace the placeholders we need with
# values from our running server script.
cat << 'EOF' > "$WG_CLIENT_SETUP_SCRIPT"
#!/bin/bash

# This script is generated by the WireGuard server setup script.
# It helps you add new peers (clients) to the WireGuard server.
#
# For setting up first WireGuard peer, simply execute this script `$ sudo bash setup_wireguard_client.sh`.
# After this, for every new client, be sure to increment `PEER_ID` by 1 and execute the script.
# You can continue doing this till `PEER_ID=254`.

echo "[+] This BASH script helps you setup a WireGuard VPN client."
read -p "[?] Have you read this script and understand what it does? (y/n): " response
if [[ "$response" != "y" && "$response" != "Y" ]]; then
    echo "[!] Please go through the script before running it. Exiting."
    exit 1
fi
echo "[+] Going ahead with setting up a WireGuard client."

# For the first peer, keep PEER_ID=2.
# For every new peer, increment this number by 1.
# The max value can be 254.
# It allows you to add at max 253 peers to a WireGuard server.
PEER_ID=2
echo "[+] Setting up WireGuard peer with ID: $PEER_ID."

echo "[+] Generating WireGuard peer private + public keypair."
PEER_PRIV_KEY=$(wg genkey)
PEER_PUB_KEY=$(echo $PEER_PRIV_KEY | wg pubkey)

# These placeholders will be replaced by the server script
SERVER_PUB_KEY="__SERVER_PUB_KEY__"
SERVER_ENDPOINT="__SERVER_ENDPOINT__"
SERVER_IPV6_PREFIX="__SERVER_IPV6_PREFIX__"

# Calculate peer-specific IP addresses
PEER_IPV4_ADDRESS="10.8.0.$PEER_ID"
PEER_IPV6_ADDRESS=$(printf "fd%s:%s:%s::%s" $(echo $SERVER_IPV6_PREFIX | cut -c 1-2) $(echo $SERVER_IPV6_PREFIX | cut -c 3-6) $(echo $SERVER_IPV6_PREFIX | cut -c 7-10) $PEER_ID)

CONFIG_FILE="peer$PEER_ID.conf"

echo "[+] Writing WireGuard peer configuration to '$CONFIG_FILE'."
cat << EOF_CLIENT > "$CONFIG_FILE"
[Interface]
PrivateKey = $PEER_PRIV_KEY
Address = $PEER_IPV4_ADDRESS/32
Address = $PEER_IPV6_ADDRESS/128
DNS = 1.1.1.1, 1.0.0.1, 2606:4700:4700::1111, 2606:4700:4700::1001
MTU = 1420

[Peer]
PublicKey = $SERVER_PUB_KEY
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = $SERVER_ENDPOINT:51820
PersistentKeepalive = 25
EOF_CLIENT

echo "[+] Adding peer to the WireGuard server configuration."
sudo wg set wg0 peer "$PEER_PUB_KEY" allowed-ips "$PEER_IPV4_ADDRESS/32,$PEER_IPV6_ADDRESS/128"

echo "[+] WireGuard peer configuration file '$CONFIG_FILE' is ready."
echo "[+] Use it with your WireGuard client application."
EOF

# Now, use `sed` to substitute the placeholder values with the actual
# variables from the server script. This is a safer and clearer way
# to inject server-side variables into the generated script.
sed -i "s|__SERVER_PUB_KEY__|$WG_PUB_KEY|" "$WG_CLIENT_SETUP_SCRIPT"
sed -i "s|__SERVER_ENDPOINT__|$PUBLIC_IP_OF_WG_SERVER|" "$WG_CLIENT_SETUP_SCRIPT"
sed -i "s|__SERVER_IPV6_PREFIX__|$IPV6_ADDRESS_PREFIX|" "$WG_CLIENT_SETUP_SCRIPT"

# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

sudo chmod +x $WG_CLIENT_SETUP_SCRIPT

echo "[+] WireGuard client setup script '$WG_CLIENT_SETUP_SCRIPT' should be ready to use."
echo "[+] Go ahead and give it a read, before you run it."
