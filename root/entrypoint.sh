#!/bin/bash

set -e


# connect to PIA using wireguard
cd pia
. ./run_setup.sh
echo "Forwarded port: $PIA_PORT"


# make transmission only use the wireguard interface
WIREGUARDIPV4=$(ip addr show pia | sed -En -e 's/.*inet ([0-9.]+).*/\1/p')
sed -i "/bind-address-ipv4/c\    \"bind-address-ipv4\": \"$WIREGUARDIPV4\"," /etc/transmission-daemon/settings.json

# download Secretmapper/combustion, a great looking transmission web interface
cd /usr/share/transmission/web
rm -rf ./*
wget https://github.com/Secretmapper/combustion/archive/release.zip
unzip release.zip
mv combustion-release/* ./
rm release.zip
rmdir combustion-release

# change rpc-username and rpc-password
if [ -n "$USERNAME" ] && [ -n "$PASSWORD" ]; then
	sed -i '/rpc-authentication-required/c\    "rpc-authentication-required": true,' /etc/transmission-daemon/settings.json
	sed -i "/rpc-username/c\    \"rpc-username\": \"$USERNAME\"," /etc/transmission-daemon/settings.json
	sed -i "/rpc-password/c\    \"rpc-password\": \"$PASSWORD\"," /etc/transmission-daemon/settings.json
fi

# set forwarded port
sed -i "/peer-port\"/c\    \"peer-port\": $PIA_PORT," /etc/transmission-daemon/settings.json

# start transmission
exec /usr/bin/transmission-daemon --foreground --config-dir /etc/transmission-daemon
