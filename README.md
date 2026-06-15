# Mozambique Demographics Data Exchange (DDE)

National Patient Identity Management Platform for Mozambique

DDE (Demographics Data Exchange) is a highly available Ruby on Rails application designed to centrally manage, allocate, and synchronize National Patient IDs (NPIDs) across health facilities in Mozambique.

Maintained by the **Ministério da Saúde (MISAU)**, DDE utilizes a distributed **Master/Proxy architecture** that allows health facilities to continue registering patients even during internet outages.

---

## Features

* Centralized National Patient ID (NPID) management
* Offline-first clinic operations
* Distributed Master/Proxy synchronization model
* Automated NPID allocation and replenishment
* JWT-based API authentication
* Background synchronization via Sidekiq
* Interactive Swagger/OpenAPI documentation
* Fully containerized deployment using Docker

---

## Architecture

```text
                    ┌─────────────────────┐
                    │     DDE Master      │
                    │ National Registry   │
                    └──────────┬──────────┘
                               │
                     Secure Synchronization
                               │
      ┌────────────────────────┼────────────────────────┐
      │                        │                        │
      ▼                        ▼                        ▼
┌─────────────┐       ┌─────────────┐         ┌─────────────┐
│ DDE Proxy   │       │ DDE Proxy   │         │ DDE Proxy   │
│ Clinic A    │       │ Clinic B    │         │ Clinic C    │
└─────────────┘       └─────────────┘         └─────────────┘

```

### Components

| Component  | Purpose                                                                 |
| ---------- | ----------------------------------------------------------------------- |
| DDE Master | National registry containing all NPIDs and patient footprints           |
| DDE Proxy  | Local clinic instance used for patient registration and synchronization |
| MySQL      | Persistent data storage                                                 |
| Redis      | Queue and caching backend                                               |
| Sidekiq    | Background processing and synchronization                               |
| Docker     | Deployment and runtime environment                                      |

---

## Technology Stack

* Ruby on Rails
* MySQL 8
* Redis
* Sidekiq
* Docker
* Docker Compose
* s6-overlay
* Swagger / OpenAPI

---

## Prerequisites

DDE is deployed exclusively using Docker to ensure environment consistency across all facilities.

### Required Software

* Docker Engine
* Docker Compose Plugin

> Legacy bare-metal deployments are deprecated and no longer supported.

---

## Configuration

DDE follows Twelve-Factor App principles and is configured entirely through environment variables.

Create a `.env` file in the project root using `.env.example` as a template.

### Critical Variables

| Variable     | Description                                        |
| ------------ | -------------------------------------------------- |
| MASTER       | `true` for Master deployments, `false` for Proxies |
| DDE_HOST_URL | Public URL where the instance is reachable         |
| DB_HOST      | MySQL host                                         |
| DB_PORT      | MySQL port                                         |
| DB_NAME      | Database name                                      |
| DB_USERNAME  | Database username                                  |
| DB_PASSWORD  | Database password                                  |
| REDIS_URL    | Redis connection URL                               |
| RAILS_ENV    | Rails environment                                  |

> The application performs startup validation and will refuse to boot if required variables are missing.

---

# Deploying a DDE Master

The Master instance operates at the national data center.

## 1. Clone the Repository

```bash
git clone git@github.com:MISAU-DIS/MPI.git dde_master
cd dde_master
```

## 2. Configure Environment

```env
MASTER=true
DDE_HOST_URL=https://sisma.misau.gov.mz/dde-master
```

## 3. Start Services

```bash
docker compose up -d
```

Database creation, migrations, and default user seeding occur automatically during startup.

### Generate Test NPIDs (Optional)

```bash
docker compose exec mpi bundle exec rails runner bin/npids_faker.rb
```

---

# Deploying a DDE Proxy

Proxy instances run within health facilities and synchronize with the Master.

## 1. Clone the Repository

```bash
git clone git@github.com:MISAU-DIS/MPI.git dde_proxy
cd dde_proxy
```

## 2. Configure Environment

```env
MASTER=false

DDE_HOST_URL=http://<CLINIC_IP_ADDRESS>/dde

# Master Synchronization
DDE_SYNC_PROTOCOL=https
DDE_SYNC_HOST=sisma.misau.gov.mz
DDE_SYNC_PORT=443

DDE_SYNC_USER=your_assigned_sync_username
DDE_SYNC_PASS=your_assigned_sync_password
```

## 3. Start Services

```bash
docker compose up -d
```

---

# API Documentation

DDE includes an interactive Swagger UI for testing and exploring API endpoints.

Open:

```text
http://<HOST>:<PORT>/api-docs/index.html
```

---

## Authentication

A default administrative account is created during initial setup.

| Username | Password |
| -------- | -------- |
| admin    | admin123 |

### Generate a JWT Token

1. Open Swagger UI
2. Execute `/v1/login`
3. Copy the returned access token
4. Click **Authorize**
5. Paste the token
6. Execute authenticated API requests

---

## Health Checks

Verify all services are running:

```bash
docker compose ps
```

View logs:

```bash
docker compose logs -f
```

View Sidekiq logs:

```bash
docker compose logs -f sidekiq
```

---

## Troubleshooting

### Container exits immediately

Verify all required environment variables are present in `.env`.

### Synchronization failures

Verify:

* DDE_SYNC_HOST
* DDE_SYNC_PORT
* DDE_SYNC_USER
* DDE_SYNC_PASS
* Internet connectivity to the Master server

### Background jobs not processing

Verify Redis and Sidekiq containers are healthy:

```bash
docker compose ps
```

---

## License

Copyright © Ministério da Saúde (MISAU)

All rights reserved.
