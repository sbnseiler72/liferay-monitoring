#!/bin/sh
set -e

# Substitute environment variables in config.yml before starting the exporter.
# The JMX exporter does not natively support env var expansion in config files.
sed "s/\${LIFERAY_JMX_HOST}/${LIFERAY_JMX_HOST}/g; s/\${LIFERAY_JMX_PORT}/${LIFERAY_JMX_PORT}/g" \
    /opt/bitnami/jmx-exporter/config.yml > /tmp/config-resolved.yml

exec java -jar /opt/bitnami/jmx-exporter/jmx_prometheus_httpserver.jar \
    9101 /tmp/config-resolved.yml
