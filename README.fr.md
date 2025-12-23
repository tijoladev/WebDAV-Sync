# webdav-sync

*[English version](README.md)*

> **Projet personnel** — Ce logiciel est fourni tel quel, sans garantie. Assurez-vous de comprendre son fonctionnement avant de l'utiliser en production. Testez d'abord avec des données non critiques. Utilisation à vos risques.

> **Note** : Contrairement aux clients cloud qui synchronisent à chaque modification de fichier, webdav-sync effectue des synchronisations programmées (via cron) ou manuelles. Il est conçu pour des sauvegardes périodiques, pas pour une synchronisation bidirectionnelle continue.

Container Docker léger pour synchroniser automatiquement un serveur WebDAV vers un système de fichiers local, avec interface web temps réel. Idéal pour le homelab, le self-hosting et la sauvegarde NAS. Compatible kDrive, Nextcloud, ownCloud, Synology, QNAP, Seafile, pCloud, Box, Yandex Disk et tout serveur WebDAV.

![WebDAV-Sync Dashboard](WebDAV-Sync.png)

## Services WebDAV Compatibles

| Service | Type | URL WebDAV |
|---------|------|------------|
| **Infomaniak kDrive** | Cloud Suisse | `https://XXXXXX.connect.kdrive.infomaniak.com/` |
| **Nextcloud** | Auto-hébergé / Cloud | `https://cloud.example.com/remote.php/dav/files/USER/` |
| **ownCloud** | Auto-hébergé / Cloud | `https://owncloud.example.com/remote.php/webdav/` |
| **Synology DSM** | NAS | `https://nas.example.com:5006/` |
| **QNAP QTS** | NAS | `https://nas.example.com/share.cgi/webdav/` |
| **Seafile** | Auto-hébergé | `https://seafile.example.com/seafdav/` |
| **Box** | Cloud | `https://dav.box.com/dav/` |
| **pCloud** | Cloud | `https://webdav.pcloud.com/` |
| **4shared** | Cloud | `https://webdav.4shared.com/` |
| **Yandex Disk** | Cloud | `https://webdav.yandex.com/` |
| **Koofr** | Cloud | `https://app.koofr.net/dav/Koofr/` |

> Tout serveur compatible WebDAV fonctionne avec webdav-sync.

## Fonctionnalités

- Synchronisation planifiée (cron) ou manuelle
- Interface web temps réel (progression, vitesse, ETA)
- Contrôles Start / Pause / Resume / Stop
- Support Docker Secrets et Kubernetes
- Gestion PUID/PGID pour NAS (Synology, Unraid, etc.)
- Logs rotatifs avec consultation web

## Démarrage Rapide

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

Accéder à l'interface : http://localhost:8080

## Variables d'Environnement

### Connexion WebDAV (obligatoires)

| Variable | Description |
|----------|-------------|
| `REMOTE_URL` | URL du serveur WebDAV |
| `REMOTE_USER` | Nom d'utilisateur |
| `REMOTE_PASS` | Mot de passe |

### Synchronisation

| Variable | Default | Description |
|----------|---------|-------------|
| `SYNC_OP` | `sync` | Opération : `sync`, `copy`, `move` |
| `SYNC_FLAGS` | `--fast-list --delete-during` | Flags rclone additionnels |
| `CRON_ENABLED` | `true` | Activer le mode planifié |
| `CRON_SCHEDULE` | `0 5 * * *` | Expression cron (5h du matin) |

### Système

| Variable | Default | Description |
|----------|---------|-------------|
| `TZ` | `Europe/Paris` | Fuseau horaire |
| `PUID` | `0` | User ID pour les fichiers |
| `PGID` | `0` | Group ID pour les fichiers |
| `LOG_LEVEL` | `INFO` | Niveau de log : DEBUG, INFO, NOTICE, ERROR |
| `LOG_MAX_DAYS` | `5` | Rétention des logs (jours) |

### Interface Web

| Variable | Default | Description |
|----------|---------|-------------|
| `WEB_USER` | `admin` | Utilisateur HTTP Basic Auth |
| `WEB_PASS` | *(vide)* | Mot de passe (vide = pas d'auth) |

## Docker Compose

### Exemple avec kDrive (Infomaniak)

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
      - WEB_PASS=monsecret
    volumes:
      - ./data:/webdav-sync/local-files
      - ./logs:/webdav-sync/logs
    ports:
      - "8080:8080"
```

### Exemple avec Nextcloud

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

### Exemple avec Synology NAS

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

| Chemin | Description |
|--------|-------------|
| `/webdav-sync/local-files` | Fichiers synchronisés |
| `/webdav-sync/logs` | Logs rotatifs |

## Secrets Docker

Les variables sensibles peuvent être passées via Docker Secrets :

```yaml
services:
  webdav-sync:
    secrets:
      - remote_pass
    environment:
      - REMOTE_URL=https://cloud.example.com/
      - REMOTE_USER=user
      # REMOTE_PASS lu depuis /run/secrets/remote_pass

secrets:
  remote_pass:
    file: ./secrets/remote_pass.txt
```

Ordre de résolution :
1. `/run/secrets/VAR` (Docker Secrets)
2. `VAR_FILE` pointant vers un fichier
3. Variable d'environnement `VAR`

## Interface Web

L'interface accessible sur le port 8080 affiche :

- **Status** : idle (orange), active (vert), paused (bleu), error (rouge)
- **Progression** : barre globale + transferts en cours
- **Stockage** : espace disque local et distant
- **Logs** : consultation avec sélecteur de date

### Contrôles

| Bouton | Action |
|--------|--------|
| Start | Lance une synchronisation |
| Pause | Suspend le transfert (SIGSTOP) |
| Resume | Reprend le transfert (SIGCONT) |
| Stop | Arrête la synchronisation |

## Sécurité

L'authentification intégrée (HTTP Basic Auth) offre une protection minimale. Pour une utilisation en production ou une exposition sur Internet, il est recommandé de placer webdav-sync derrière un reverse proxy (Traefik, Caddy, nginx) avec HTTPS.

## Stack Technique

- **Base** : Alpine Linux + rclone 1.71.2
- **Web** : BusyBox httpd + CGI
- **Frontend** : HTML5/CSS3/JS vanilla (pas de framework)
- **Planification** : crond
- **~1800 lignes** de code total

## Documentation

- [Documentation Technique](TECHNICAL.md)

## Licence

MIT
