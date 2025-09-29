# setup-wireguard-vpn

BASH script for easy set up of WireGuard VPN Server and Clients

## How to setup a WireGuard server on Linux VM and connect clients to it?

> [!NOTE]
> A blog post on "Host Your Own VPN Server" @ <https://itzmeanjan.in/pages/host-your-own-vpn_server.html>, guides you through using this BASH script.

- Get yourself a $5/month VPS on AWS Lightsail or DigitalOcean.
- SSH into the machine, clone this repository.

```bash
git clone https://github.com/itzmeanjan/setup-wireguard-vpn
```

- Execute BASH script on the machine. It should setup a WireGuard VPN server on your VPS.

```bash
pushd setup-wireguard-vpn
sudo ./setup_wireguard_server.sh
```

- Check the status of WireGuard VPN server running with following command.

```bash
sudo wg
```

- Go to network configuration page of VPS console and open port `51820`. The WireGuard VPN server is expecting peer connection on that port.
- Executing WireGuard server setup script should generate another script `setup_wireguard_client.sh`. Let's execute that for setting up our first WireGuard client.

```bash
sudo ./setup_wireguard_client.sh
```

- It should produce a WireGuard peer configuration file `peer2.conf`. You can import this configuration file in your WireGuard client application to connect to the VPN server, setting up a secure tunnel.
- To check if tunneling is working, lookup your public IP address @ <https://ipinfo.io/ip>.

```bash
curl -s https://ipinfo.io | jq
```

- Also check if your DNS lookups are leaking @ <https://www.dnsleaktest.com/>. We want all the traffic to flow through WireGuard secure tunnel and exit into public Internet, from our VPN server.
- For setting up another WireGuard peer, SSH back into VPS, running WireGuard server, open WireGuard client configuration script `setup_wireguard_client.sh`. Find a BASH variable named `PEER_ID`, increment its value to 3. Save the script and re-execute it. It should produce another WireGuard peer configuration file `peer3.conf`. You can import this peer configuration file in another WireGuard client app.
- Simply put, for every new WireGuard client you setup, after the first client, you have to increment the `PEER_ID` by 1, to assign correct IP addresses to the peers. If you don't do that, tunneling won't work as expected.
- If you restart VPS, running WireGuard server, you have to reload the IPv4+IPv6 packet forwarding configuration, from `/etc/sysctl.conf`.

```bash
sudo sysctl -p
```

![sceen-capture-of-the-flow-of-setting-up-a-wireguard-server](./setup_wg.gif)

> [!TIP]
> Prefer to watch the walk through with some background music? Play [./setup_wg_with_bgm.mp4](./setup_wg_with_bgm.mp4) with your local media player.

> [!NOTE]
> This script is an implementation of the steps described in DigitalOcean blog post on "How To Set Up WireGuard on Ubuntu 20.04" @ <https://www.digitalocean.com/community/tutorials/how-to-set-up-wireguard-on-ubuntu-20-04>. This script makes the setup process much easier.
