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


# This allows you to set the maximum allowed latency in seconds.
# All servers that respond slower than this will be ignored.
# You can inject this with the environment variable MAX_LATENCY.
# The default value is 50 milliseconds.
MAX_LATENCY=${MAX_LATENCY:-0.05}
export MAX_LATENCY

serverlist_url='https://serverlist.piaservers.net/vpninfo/servers/v4'

# This function checks the latency you have to a specific region.
# It will print a human-readable message to stderr,
# and it will print the variables to stdout
printServerLatency() {
  serverIP="$1"
  regionID="$2"
  regionName="$(echo ${@:3} |
    sed 's/ false//' | sed 's/true/(geo)/')"
  time=$(LC_NUMERIC=en_US.utf8 curl -o /dev/null -s \
    --connect-timeout $MAX_LATENCY \
    --write-out "%{time_connect}" \
    http://$serverIP:443)
  if [ $? -eq 0 ]; then
    >&2 echo Got latency ${time}s for region: $regionName
    echo $time $regionID $serverIP
  fi
}
export -f printServerLatency

echo -n "Getting the server list... "
# Get all region data since we will need this on multiple occasions
all_region_data=$(curl -s "$serverlist_url" | head -1)

# If the server list has less than 1000 characters, it means curl failed.
if [[ ${#all_region_data} -lt 1000 ]]; then
  echo "Could not get correct region data. To debug this, run:"
  echo "$ curl -v $serverlist_url"
  echo "If it works, you will get a huge JSON as a response."
  exit 1
fi
# Notify the user that we got the server list.
echo "OK!"

# Test one server from each region to get the closest region.
# Filter out regions that don't support it.
echo "Port Forwarding is enabled, so regions that do not support"
echo "port forwarding will get filtered out."
summarized_region_data="$( echo $all_region_data |
  jq -r '.regions[] | select(.port_forward==true) |
  .servers.meta[0].ip+" "+.id+" "+.name+" "+(.geo|tostring)' )"

echo Testing regions that respond \
  faster than $MAX_LATENCY seconds:
bestRegion="$(echo "$summarized_region_data" |
  xargs -I{} bash -c 'printServerLatency {}' |
  sort | head -1 | awk '{ print $2 }')"

if [ -z "$bestRegion" ]; then
  echo ...
  echo No region responded within ${MAX_LATENCY}s, consider using a higher timeout.
  echo For example, to wait 1 second for each region, inject MAX_LATENCY=1 like this:
  echo $ MAX_LATENCY=1 ./get_region_and_token.sh
  exit 1
fi

# Get all data for the best region
regionData="$( echo $all_region_data |
  jq --arg REGION_ID "$bestRegion" -r \
  '.regions[] | select(.id==$REGION_ID)')"

echo -n The closest region is "$(echo $regionData | jq -r '.name')"
if echo $regionData | jq -r '.geo' | grep true > /dev/null; then
  echo " (geolocated region)."
else
  echo "."
fi
echo
bestServer_meta_IP="$(echo $regionData | jq -r '.servers.meta[0].ip')"
bestServer_meta_hostname="$(echo $regionData | jq -r '.servers.meta[0].cn')"
bestServer_WG_IP="$(echo $regionData | jq -r '.servers.wg[0].ip')"
bestServer_WG_hostname="$(echo $regionData | jq -r '.servers.wg[0].cn')"

echo "The script found the best servers from the region closest to you.
When connecting to an IP (no matter which protocol), please verify
the SSL/TLS certificate actually contains the hostname so that you
are sure you are connecting to a secure server, validated by the
PIA authority. Please find below the list of best IPs and matching
hostnames for each protocol:
Meta Services: $bestServer_meta_IP // $bestServer_meta_hostname
WireGuard: $bestServer_WG_IP // $bestServer_WG_hostname
"

echo "Trying to get a new token by authenticating with the meta service..."
generateTokenResponse=$(curl -s -u "$PIA_USER:$PIA_PASS" \
  --connect-to "$bestServer_meta_hostname::$bestServer_meta_IP:" \
  --cacert "ca.rsa.4096.crt" \
  "https://$bestServer_meta_hostname/authv3/generateToken")

if [ "$(echo "$generateTokenResponse" | jq -r '.status')" != "OK" ]; then
  echo "Could not get a token. Please check your account credentials."
  echo
  echo "You can also try debugging by manually running the curl command:"
  echo $ curl -vs -u \"$PIA_USER:$PIA_PASS\" --cacert ca.rsa.4096.crt \
    --connect-to \"$bestServer_meta_hostname::$bestServer_meta_IP:\" \
    https://$bestServer_meta_hostname/authv3/generateToken
  exit 1
fi

token="$(echo "$generateTokenResponse" | jq -r '.token')"
echo "This token will expire in 24 hours."

PIA_TOKEN="$token"
export PIA_TOKEN
WG_SERVER_IP=$bestServer_WG_IP
export WG_SERVER_IP
WG_HOSTNAME=$bestServer_WG_hostname
export WG_HOSTNAME
