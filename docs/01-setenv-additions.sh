#!/usr/bin/env sh
# =============================================================================
# ADD these lines to your Liferay setenv.sh
# File location: liferay/conf/tomcat/bin/setenv.sh
# Place BEFORE the final "export CATALINA_OPTS" line
# =============================================================================

# JMX remote — required for jmx_exporter Prometheus metrics
# Bound to 127.0.0.1 only — NEVER expose port 9999 publicly
CATALINA_OPTS="$CATALINA_OPTS -Dcom.sun.management.jmxremote"
CATALINA_OPTS="$CATALINA_OPTS -Dcom.sun.management.jmxremote.port=9999"
CATALINA_OPTS="$CATALINA_OPTS -Dcom.sun.management.jmxremote.rmi.port=9999"
CATALINA_OPTS="$CATALINA_OPTS -Dcom.sun.management.jmxremote.authenticate=false"
CATALINA_OPTS="$CATALINA_OPTS -Dcom.sun.management.jmxremote.ssl=false"
CATALINA_OPTS="$CATALINA_OPTS -Djava.rmi.server.hostname=127.0.0.1"
