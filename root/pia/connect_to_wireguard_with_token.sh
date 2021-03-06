#!/bin/bash
# Copyright (C) 2020 Private Internet Access, Inc.
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

# Create ephemeral wireguard keys, that we don't need to save to disk.
privKey="$(wg genkey)"
pubKey="$( echo "$privKey" | wg pubkey)"

# Authenticate via the PIA WireGuard RESTful API.
# This will return a JSON with data required for authentication.
# The certificate is required to verify the identity of the VPN server.
# In case you didn't clone the entire repo, get the certificate from:
# https://github.com/pia-foss/manual-connections/blob/master/ca.rsa.4096.crt
# In case you want to troubleshoot the script, replace -s with -v.
echo Trying to connect to the PIA WireGuard API on $WG_SERVER_IP...
wireguard_json="$(curl -s -G \
  --connect-to "$WG_HOSTNAME::$WG_SERVER_IP:" \
  --cacert "ca.rsa.4096.crt" \
  --data-urlencode "pt=${PIA_TOKEN}" \
  --data-urlencode "pubkey=$pubKey" \
  "https://${WG_HOSTNAME}:1337/addKey" )"

# Check if the API returned OK and stop this script if it didn't.
if [ "$(echo "$wireguard_json" | jq -r '.status')" != "OK" ]; then
  >&2 echo "Server did not return OK. Stopping now."
  exit 1
fi

# Multi-hop is out of the scope of this repo, but you should be able to
# get multi-hop running with both WireGuard and OpenVPN by playing with
# these scripts. Feel free to fork the project and test it out.
echo
echo Trying to disable a PIA WG connection in case it exists...
wg-quick down pia && echo Disconnected!
echo

# Create the WireGuard config based on the JSON received from the API
# This uses a PersistentKeepalive of 25 seconds to keep the NAT active
# on firewalls. You can remove that line if your network does not
# require it.
echo -n "Trying to write /etc/wireguard/pia.conf... "
mkdir -p /etc/wireguard
echo "
[Interface]
Address = $(echo "$wireguard_json" | jq -r '.peer_ip')
PrivateKey = $privKey
DNS = $(echo "$wireguard_json" | jq -r '.dns_servers[0]')
[Peer]
PersistentKeepalive = 25
PublicKey = $(echo "$wireguard_json" | jq -r '.server_key')
AllowedIPs = 0.0.0.0/0
Endpoint = ${WG_SERVER_IP}:$(echo "$wireguard_json" | jq -r '.server_port')
" > /etc/wireguard/pia.conf || exit 1
echo OK!

# Start the WireGuard interface.
# If something failed, stop this script.
# If you get DNS errors because you miss some packages,
# just hardcode /etc/resolv.conf to "nameserver 10.0.0.242".
echo
echo Trying to create the wireguard interface...
wg-quick up pia || exit 1
echo "The WireGuard interface got created.
At this point, internet should work via VPN."

echo -n "
We will allow WireGuard to fully
initialize: "
for i in {5..1}; do
  echo -n "$i... "
  sleep 1
done
echo

PIA_GATEWAY="$(echo "$wireguard_json" | jq -r '.server_vip')"
export PIA_GATEWAY
