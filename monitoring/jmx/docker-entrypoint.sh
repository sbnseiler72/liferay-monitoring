#!/bin/sh
set -e

# Substitute environment variables in config.yml before starting the exporter.
# The JMX exporter does not natively support env var expansion in config files.
envsubst < /opt/bitnami/jmx-exporter/config.yml > /tmp/config-resolved.yml

exec java -jar /opt/bitnami/jmx-exporter/jmx_prometheus_httpserver.jar \
    9101 /tmp/config-resolved.yml
