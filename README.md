# webdav-sync

*[Version française](README.fr.md)*

> **Personal project** — This software is provided as-is, without warranty. Make sure you understand how it works before using it in production. Test with non-critical data first. Use at your own risk.

> **Note**: Unlike cloud sync clients that monitor file changes in real-time, webdav-sync performs scheduled synchronizations (via cron) or manual triggers. It's designed for periodic backups, not continuous bidirectional sync.

Lightweight Docker container for automatic WebDAV to local filesystem synchronization, with real-time web UI. Ideal for homelab, self-hosting and NAS backup. Works with kDrive, Nextcloud, ownCloud, Synology, QNAP, Seafile, pCloud, Box, Yandex Disk and any WebDAV server.

<p align="center">
  <img src="WebDAV-Sync.png" alt="WebDAV-Sync Dashboard" width="700">
</p>

## Compatible WebDAV Services

| Service | Type | WebDAV URL |
|---------|------|------------|
| **Infomaniak kDrive** | Swiss Cloud | `https://XXXXXX.connect.kdrive.infomaniak.com/` |
| **Nextcloud** | Self-hosted / Cloud | `https://cloud.example.com/remote.php/dav/files/USER/` |
| **ownCloud** | Self-hosted / Cloud | `https://owncloud.example.com/remote.php/webdav/` |
| **Synology DSM** | NAS | `https://nas.example.com:5006/` |
| **QNAP QTS** | NAS | `https://nas.example.com/share.cgi/webdav/` |
| **Seafile** | Self-hosted | `https://seafile.example.com/seafdav/` |
| **Box** | Cloud | `https://dav.box.com/dav/` |
| **pCloud** | Cloud | `https://webdav.pcloud.com/` |
| **4shared** | Cloud | `https://webdav.4shared.com/` |
| **Yandex Disk** | Cloud | `https://webdav.yandex.com/` |
| **Koofr** | Cloud | `https://app.koofr.net/dav/Koofr/` |

> Any WebDAV-compatible server works with webdav-sync.

## Features

- Scheduled (cron) or manual synchronization
- Real-time web interface (progress, speed, ETA)
- Start / Pause / Resume / Stop controls
- Docker Secrets and Kubernetes support
- PUID/PGID management for NAS (Synology, Unraid, etc.)
- Rotating logs with web viewer

## Quick Start

```bash
docker run -d \
  --name webdav-sync \
  -p 8080:8080 \
  -e REMOTE_URL=https://cloud.example.com/remote.php/dav/files/user/ \
  -e REMOTE_USER=user@example.com \
  -e REMOTE_PASS=secret \
  -e CRON_SCHEDULE="0 5 * * *" \
  -v ./data:/webdav-sync/local-files \
  -v ./logs:/webdav-sync/logs \
  webdav-sync
```

Access the interface: http://localhost:8080

## Environment Variables

### WebDAV Connection (required)

| Variable | Description |
|----------|-------------|
| `REMOTE_URL` | WebDAV server URL |
| `REMOTE_USER` | Username |
| `REMOTE_PASS` | Password |

### Synchronization

| Variable | Default | Description |
|----------|---------|-------------|
| `SYNC_OP` | `sync` | Operation: `sync`, `copy`, `move` |
| `SYNC_FLAGS` | `--fast-list --delete-during` | Additional rclone flags |
| `CRON_ENABLED` | `true` | Enable scheduled mode |
| `CRON_SCHEDULE` | `0 5 * * *` | Cron expression (5 AM) |

### System

| Variable | Default | Description |
|----------|---------|-------------|
| `TZ` | `Europe/Paris` | Timezone |
| `PUID` | `0` | User ID for files |
| `PGID` | `0` | Group ID for files |
| `LOG_LEVEL` | `INFO` | Log level: DEBUG, INFO, NOTICE, ERROR |
| `LOG_MAX_DAYS` | `5` | Log retention (days) |

### Web Interface

| Variable | Default | Description |
|----------|---------|-------------|
| `WEB_USER` | `admin` | HTTP Basic Auth username |
| `WEB_PASS` | *(empty)* | Password (empty = no auth) |

## Docker Compose

### Example with kDrive (Infomaniak)

```yaml
services:
  webdav-sync:
    build: .
    environment:
      - REMOTE_URL=https://123456.connect.kdrive.infomaniak.com/
      - REMOTE_USER=user@example.com
      - REMOTE_PASS=secret
      - TZ=Europe/Paris
      - CRON_SCHEDULE=0 5 * * *
      - WEB_PASS=mysecret
    volumes:
      - ./data:/webdav-sync/local-files
      - ./logs:/webdav-sync/logs
    ports:
      - "8080:8080"
```

### Example with Nextcloud

```yaml
services:
  webdav-sync:
    build: .
    environment:
      - REMOTE_URL=https://nextcloud.example.com/remote.php/dav/files/username/
      - REMOTE_USER=username
      - REMOTE_PASS=app-password
      - TZ=Europe/Paris
      - CRON_SCHEDULE=0 */6 * * *
    volumes:
      - ./data:/webdav-sync/local-files
      - ./logs:/webdav-sync/logs
    ports:
      - "8080:8080"
```

### Example with Synology NAS

```yaml
services:
  webdav-sync:
    build: .
    environment:
      - REMOTE_URL=https://nas.local:5006/
      - REMOTE_USER=admin
      - REMOTE_PASS=secret
      - PUID=1000
      - PGID=1000
      - SYNC_OP=copy
    volumes:
      - ./data:/webdav-sync/local-files
      - ./logs:/webdav-sync/logs
    ports:
      - "8080:8080"
```

## Volumes

| Path | Description |
|------|-------------|
| `/webdav-sync/local-files` | Synchronized files |
| `/webdav-sync/logs` | Rotating logs |

## Docker Secrets

Sensitive variables can be passed via Docker Secrets:

```yaml
services:
  webdav-sync:
    secrets:
      - remote_pass
    environment:
      - REMOTE_URL=https://cloud.example.com/
      - REMOTE_USER=user
      # REMOTE_PASS read from /run/secrets/remote_pass

secrets:
  remote_pass:
    file: ./secrets/remote_pass.txt
```

Resolution order:
1. `/run/secrets/VAR` (Docker Secrets)
2. `VAR_FILE` pointing to a file
3. Environment variable `VAR`

## Web Interface

The interface accessible on port 8080 displays:

- **Status**: idle (orange), active (green), paused (blue), error (red)
- **Progress**: global bar + current transfers
- **Storage**: local and remote disk space
- **Logs**: viewer with date selector

### Controls

| Button | Action |
|--------|--------|
| Start | Starts a synchronization |
| Pause | Suspends the transfer (SIGSTOP) |
| Resume | Resumes the transfer (SIGCONT) |
| Stop | Stops the synchronization |

## Security

The built-in authentication (HTTP Basic Auth) provides minimal protection. For production use or internet exposure, it is recommended to place webdav-sync behind a reverse proxy (Traefik, Caddy, nginx) with HTTPS.

## Tech Stack

- **Base**: Alpine Linux + rclone 1.71.2
- **Web**: BusyBox httpd + CGI
- **Frontend**: HTML5/CSS3/JS vanilla (no framework)
- **Scheduling**: crond
- **~1800 lines** of code total

## Documentation

- [Technical Documentation](TECHNICAL.md)

## License

MIT
