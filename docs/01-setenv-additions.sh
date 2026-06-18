#!/usr/bin/env sh
# =============================================================================
# ADD these lines to your Liferay setenv.sh
# File location: liferay/conf/tomcat/bin/setenv.sh
# Place BEFORE the final "export CATALINA_OPTS" line
# =============================================================================

# JMX remote — required for jmx_exporter Prometheus metrics
#
# java.rmi.server.hostname MUST be set to the Liferay container's hostname
# on the shared Docker network (not 127.0.0.1).
#
# How JMX/RMI works over Docker:
#   Step 1 — jmx_exporter connects to liferay:9999 to fetch the RMI stub.
#   Step 2 — the stub tells the client "now reconnect to <hostname>:<rmi.port>".
#   If hostname is 127.0.0.1, step 2 tries the exporter's own loopback → refused.
#   Setting it to the service name makes step 2 resolve correctly inside Docker.
#
# Replace "liferay" below with your actual Docker service / container name
# if it differs (check: docker inspect <container> | grep '"Name"').
CATALINA_OPTS="$CATALINA_OPTS -Dcom.sun.management.jmxremote"
CATALINA_OPTS="$CATALINA_OPTS -Dcom.sun.management.jmxremote.port=9999"
CATALINA_OPTS="$CATALINA_OPTS -Dcom.sun.management.jmxremote.rmi.port=9999"
CATALINA_OPTS="$CATALINA_OPTS -Dcom.sun.management.jmxremote.authenticate=false"
CATALINA_OPTS="$CATALINA_OPTS -Dcom.sun.management.jmxremote.ssl=false"
CATALINA_OPTS="$CATALINA_OPTS -Djava.rmi.server.hostname=liferay"
