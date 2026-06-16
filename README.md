# Liferay Monitor Stack

A standalone, plug-in monitoring stack for any Liferay 7.x Docker deployment.
Connects to your existing Liferay Docker network without modifying it.

---

## Components

| Service | Container | Purpose | Host Port |
|---|---|---|---|
| cAdvisor | lf_monitor_cadvisor | Docker container metrics | 18085 |
| JMX Exporter | lf_monitor_jmx | Liferay JVM / Tomcat / HikariCP metrics | 19101 |
| PostgreSQL Exporter | lf_monitor_postgres | Database metrics | 19187 |
| Nginx Exporter | lf_monitor_nginx | Nginx connection metrics | 19113 |
| Prometheus | lf_monitor_prometheus | Metrics storage + alerting | 19090 |
| Grafana | lf_monitor_grafana | Dashboards + notifications | 13000 |

All host ports use the `1xxxx` range to avoid conflicts with your Liferay stack.

---

## Prerequisites

- Docker + docker-compose installed on the same host as Liferay
- Liferay stack running with a named Docker network
- Liferay Tomcat has JMX enabled (see Step 2)
- Nginx has stub_status enabled (see Step 3)

---

## Installation

### Step 1 — Configure

**Option A: Interactive setup (recommended)**
```bash
bash scripts/setup.sh
```

**Option B: Manual — edit `.env` directly**
```bash
cp .env .env.backup
nano .env
```

Minimum required settings in `.env`:
```env
LIFERAY_NETWORK=liferay-backend     # your Docker network name
POSTGRES_USER=liferay
POSTGRES_PASSWORD=your_password
POSTGRES_DB=portal737
GRAFANA_PASSWORD=your_grafana_password
```

Find your Liferay network name:
```bash
docker network ls
# Look for the network your liferay, db, nginx containers share
docker inspect liferay --format='{{range .NetworkSettings.Networks}}{{.NetworkID}}{{end}}'
```

---

### Step 2 — Enable JMX in Liferay

Add these lines to your Liferay `setenv.sh`
(see full file: `docs/01-setenv-additions.sh`):

```bash
CATALINA_OPTS="$CATALINA_OPTS -Dcom.sun.management.jmxremote"
CATALINA_OPTS="$CATALINA_OPTS -Dcom.sun.management.jmxremote.port=9999"
CATALINA_OPTS="$CATALINA_OPTS -Dcom.sun.management.jmxremote.rmi.port=9999"
CATALINA_OPTS="$CATALINA_OPTS -Dcom.sun.management.jmxremote.authenticate=false"
CATALINA_OPTS="$CATALINA_OPTS -Dcom.sun.management.jmxremote.ssl=false"
CATALINA_OPTS="$CATALINA_OPTS -Djava.rmi.server.hostname=127.0.0.1"
```

Expose the JMX port in your Liferay `docker-compose.yml`
(see: `docs/03-liferay-compose-additions.yml`):
```yaml
liferay:
  ports:
    - '127.0.0.1:9999:9999'
```

Restart Liferay:
```bash
docker-compose restart liferay
```

---

### Step 3 — Enable nginx stub_status

Add to your nginx server block
(see full snippet: `docs/02-nginx-additions.conf`):

```nginx
location /stub_status {
    stub_status on;
    allow 172.16.0.0/12;
    allow 127.0.0.1;
    deny  all;
    access_log off;
}
```

Reload nginx:
```bash
docker exec web-server nginx -s reload
```

---

### Step 4 — Create data directories and fix permissions

```bash
mkdir -p monitoring/prometheus/data monitoring/grafana/data
# Fix Grafana directory ownership (runs as UID 472)
chown -R 472:472 monitoring/grafana/data || chmod -R 777 monitoring/grafana/data
```

---

### Step 5 — Start the monitor stack

```bash
docker-compose up -d
```

Verify all containers are running:
```bash
docker-compose ps
```

Expected output — all services `Up`:
```
lf_monitor_cadvisor    Up
lf_monitor_grafana     Up
lf_monitor_jmx         Up
lf_monitor_nginx       Up
lf_monitor_postgres    Up
lf_monitor_prometheus  Up
```

---

### Step 6 — Open Grafana

Direct access: http://YOUR_SERVER_IP:13000
Login: `admin` / (password from `.env`)

Import dashboards via Dashboards → Import → Enter ID:
See `docs/04-grafana-dashboards.txt` for recommended dashboard IDs.

---

## Alerts Configured

Defined in `monitoring/prometheus/alerts.yml`.

| Alert | Condition | Severity |
|---|---|---|
| JvmHeapCritical | heap > 85% for 2m | CRITICAL |
| JvmHeapHigh | heap > 70% for 5m | WARNING |
| JvmFullGcDetected | G1 Old GC triggered | WARNING |
| JvmGcPauseHigh | avg pause > 500ms for 3m | WARNING |
| JvmMetaspaceHigh | metaspace > 480MB | WARNING |
| JvmFileDescriptorHigh | fd > 80% of limit | WARNING |
| TomcatThreadPoolCritical | threads busy > 80% for 1m | CRITICAL |
| TomcatThreadPoolHigh | threads busy > 60% for 3m | WARNING |
| TomcatErrorRateHigh | error rate > 5% for 3m | WARNING |
| LiferayMemoryCritical | container RAM > 13GB | CRITICAL |
| LiferayMemoryHigh | container RAM > 11GB | WARNING |
| LiferayCpuSustainedHigh | CPU > 90% for 5m | WARNING |
| ElasticsearchMemoryHigh | ES RAM > 3.5GB | WARNING |
| ContainerOomKilled | OOM kill event | CRITICAL |
| ContainerRestartDetected | container restart | CRITICAL |
| PostgresConnectionsHigh | connections > 40 | WARNING |
| PostgresConnectionsCritical | connections > 48 | CRITICAL |
| HikariCpPendingConnections | pending > 5 for 1m | WARNING |
| PostgresDown | exporter cannot connect | CRITICAL |
| NginxDown | stub_status unreachable | CRITICAL |
| NginxConnectionsHigh | active > 500 for 2m | WARNING |
| DiskSpaceHigh | disk > 80% | WARNING |
| DiskSpaceCritical | disk > 90% | CRITICAL |

To enable email/Telegram/Slack notifications:
Grafana → Alerting → Contact Points → Add contact point

---

## Daily Health Check

```bash
bash scripts/health-check.sh
```

Sample output:
```
╔════════════════════════════════════════════════════╗
║     Liferay Portal — Health Check                  ║
║     2026-06-16 09:00:00 +0330                      ║
╚════════════════════════════════════════════════════╝

[ Container Status ]
──────────────────────────────────────────────────────
  ✓ liferay: running | restarts=0 | oom_killed=false
  ✓ db: running | restarts=0 | oom_killed=false
  ✓ web-server: running | restarts=0 | oom_killed=false
  ✓ elasticsearch: running | restarts=0 | oom_killed=false

[ GC Health (today) ]
──────────────────────────────────────────────────────
  ✓ to-space exhausted events: 0
  ✓ humongous allocations: 4
  ✓ full GC (G1 Old) events: 0
  ✓ broken pipe errors today: 2
  ✓ PDF processor failures today: 0

[ Nginx Cache Stats ]
──────────────────────────────────────────────────────
  Hit rate: 98.3% (186860/190073 requests)
  ✓ Cache performance excellent
```

Add to crontab for automated daily report:
```bash
0 8 * * * bash /path/to/liferay-monitor/scripts/health-check.sh >> /var/log/liferay-health.log 2>&1
```

---

## Management Commands

```bash
# Start monitoring stack
docker-compose up -d

# Stop without removing data
docker-compose stop

# Stop and remove containers (data preserved in monitoring/ volumes)
docker-compose down

# View logs of a specific exporter
docker-compose logs -f jmx_exporter
docker-compose logs -f prometheus

# Reload Prometheus config without restart
curl -X POST http://localhost:19090/-/reload

# Check Prometheus targets (all should be UP)
curl -s http://localhost:19090/api/v1/targets | python3 -m json.tool | grep -E "job|health"

# Reconfigure for a different Liferay stack
nano .env
docker-compose up -d --force-recreate
```

---

## File Structure

```
liferay-monitor/
├── docker-compose.yml                          ← main compose file
├── .env                                        ← all configuration here
├── monitoring/
│   ├── prometheus/
│   │   ├── prometheus.yml                      ← scrape config
│   │   ├── alerts.yml                          ← 22 alert rules
│   │   └── data/                              ← time series storage (gitignored)
│   ├── grafana/
│   │   ├── data/                              ← grafana state (gitignored)
│   │   └── provisioning/
│   │       ├── datasources/prometheus.yml      ← auto-wires Prometheus
│   │       └── dashboards/dashboards.yml       ← dashboard loader
│   └── jmx/
│       └── config.yml                          ← JVM metric mappings
├── scripts/
│   ├── setup.sh                                ← interactive first-time setup
│   └── health-check.sh                         ← daily health check report
└── docs/
    ├── 01-setenv-additions.sh                  ← JMX lines for setenv.sh
    ├── 02-nginx-additions.conf                 ← stub_status nginx block
    ├── 03-liferay-compose-additions.yml        ← port 9999 for your compose
    └── 04-grafana-dashboards.txt               ← recommended dashboard IDs
```

---

## Compatibility

| Component | Version | Notes |
|---|---|---|
| Liferay | 7.1 — 7.4 | Any Tomcat bundle |
| Java | 8, 11, 17 | JMX available in all |
| PostgreSQL | 10 — 15 | Tested with 12.8 |
| Nginx | 1.18+ | stub_status required |
| Docker | 20.10+ | |
| docker-compose | 1.29+ / v2 | |

---

*Liferay Monitor — Generic standalone monitoring for Liferay Docker deployments*
