# docker-pia-wireguard-transmission
Docker image for running Transmission over a WireGuard connection to Private Internet Access, based on Alpine Linux.

## Usage

### docker run
```
docker build . -t docker-wireguard-transmission
docker run --privileged \
  -e "USERNAME=transmission" \
  -e "PASSWORD=transmission" \
  -e "PIA_USER=piauser" \
  -e "PIA_PASS=piapassword" \
  -p 51820:51820/udp \
  -p 9091:9091 \
  -v "/path/to/transmission/conf:/etc/transmission-daemon" \
  -v "/path/to/transmission/complete:/transmission/complete" \
  -v "/path/to/transmission/incomplete:/transmission/incomplete" \
  docker-wireguard-transmission:latest
```

### docker-compose.yml
```
version: '3.7'
services:
    wireguard-transmission:
        container_name: wireguard-transmission
        privileged: true
        environment:
            - USERNAME=transmission
            - PASSWORD=transmission
            - PIA_USER=piauser
            - PIA_PASS=piapassword
        ports:
            - '51820:51820/udp'
            - '9091:9091'
        volumes:
            - '/path/to/transmission-conf-dir:/etc/transmission-daemon'
            - '/path/to/transmission-complete-dir:/transmission/complete'
            - '/path/to/transmission-incomplete-dir:/transmission/incomplete'
        image: wireguard-transmission:latest
```
