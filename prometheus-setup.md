## To add Prometheus profiling and Grafana visualization

Please run the following instructions or create a bash scripts to automate it

`#!/bin/bash`

`mkdir -p ~/Downloads/`

`cd ~/Downloads`

## Prometheus profiling

`wget https://github.com/prometheus/prometheus/releases/download/v2.45.0/prometheus-2.45.0.linux-amd64.tar.gz`

`tar xvf prometheus-2.45.0.linux-amd64.tar.gz`

`cd prometheus-2.45.0.linux-amd64`

## Configuring Prometheus profiling

Edit prometheus.yml to add target servers to profile

`vim ./prometheus.yml`

Sample edits: Uncomment and edit the following lines
```
scrape_configs:
- job_name: "prometheus"  # static_configs:
- targets: # - "<local-ip>:2379"
      - "10.140.83.236:2379"
      - "10.140.83.249:2379"
      - "10.140.81.235:2379"
```

## Launch prometheus
`./prometheus --config.file=./prometheus.yml &`

## Disable the firewall and ensure ports are open
`sudo ufw disable`

Make sure the ports 2379 and 9090 are enabled for listening

`sudo netstat -tuln | grep 2379`

`sudo netstat -tuln | grep 9090`

## Launch etcd with --metrics enabled

` cat cloud_benchmark.sh | grep metrics`

Make sure bin/etcd to launch servers has --metrics enabled either with 'extensive' or 'basic'

# Grafana visualization

`cd ~/Downloads`

`sudo add-apt-repository "deb https://packages.grafana.com/oss/deb stable main"`
`curl -s https://packages.grafana.com/gpg.key | sudo apt-key add -`

`sudo apt-get install grafana`

`sudo systemctl start grafana-server`

`sudo systemctl enable grafana-server`

## Check Prometheus and Grafana Setup

Now you should be able to see Prometheus metrics at 
> http://public-ip:2379/metrics

Make sure port 3000 is open
`sudo netstat -tuln | grep 3000`

Grafana etcd visualization at
> http://public-ip:3000/

Use the default Etcd by Prometheus visualization; You can extend dashboards to monitor additional metrics

Soujanya Ponnapalli | 2025-04-01 | soujanya@berkeley.edu
