# Documentation Technique - webdav-sync

## Vue d'ensemble

**webdav-sync** est un orchestrateur Docker pour synchroniser un serveur WebDAV (kDrive, Nextcloud, ownCloud, Synology, etc.) avec un système de fichiers local via rclone. L'application fonctionne comme une appliance autonome avec interface web de monitoring.

---

## Stack Technique

### Backend (Shell/Docker)
| Composant | Version/Détails |
|-----------|-----------------|
| Image base | rclone 1.71.2 (Alpine Linux) |
| Shell | POSIX sh (compatible BusyBox) |
| Serveur web | BusyBox httpd |
| Planification | crond |
| JSON | jq |
| Synchronisation | flock |

### Frontend (Web)
- HTML5 sémantique avec attributs ARIA
- CSS3 (Grid, Flexbox, variables CSS)
- JavaScript ES6 vanilla (sans framework)
- Fetch API pour communication CGI

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    entrypoint.sh                        │
│         (Orchestrateur, chargement config & helpers)    │
└────────────────────────┬────────────────────────────────┘
                         │
           ┌─────────────┴─────────────┐
           │                           │
           v                           v
      Mode CRON                   Mode Manuel
           │                           │
           └─────────────┬─────────────┘
                         │
                         v
              ┌─────────────────────┐
              │      do_run()       │
              │  - ensure_remote()  │
              │  - rotate_logs()    │
              │  - kctl op          │
              └──────────┬──────────┘
                         │
              ┌──────────v──────────┐
              │    wdsync.sh     │
              │   (Wrapper JSON)    │
              └──────────┬──────────┘
                         │
              ┌──────────v──────────┐
              │   rclone binary     │
              │   (RC API + sync)   │
              └─────────────────────┘
```

### Architecture Web

```
┌─────────────────────────────────────────┐
│            index.html (SPA)             │
│  ┌───────────────────────────────────┐  │
│  │      Composants UI (DOM + CSS)    │  │
│  └───────────────────────────────────┘  │
│  ┌───────────────────────────────────┐  │
│  │         Fetch API Client          │  │
│  │  - Live refresh: 4s               │  │
│  │  - Render tick: 50ms              │  │
│  │  - Snapshot: 12s                  │  │
│  └───────────────────────────────────┘  │
└───────────────────┬─────────────────────┘
                    │ :8080
         ┌──────────v──────────┐
         │    busybox httpd    │
         └──────────┬──────────┘
                    │
         ┌──────────v────────────────┐
         │  /cgi-bin/live.sh         │
         │  /cgi-bin/snapshot.sh     │
         │  /cgi-bin/control.sh      │
         └───────────────────────────┘
```

---

## Structure des Fichiers

```
webdav-sync/
├── Dockerfile                  # Image Docker avec rclone 1.71.2
├── entrypoint.sh               # Point d'entrée (88 lignes)
├── wdsync.sh                # CLI wrapper JSON (161 lignes)
├── webdav-sync-internal.json   # Schéma de configuration
│
├── helpers/                    # Modules utilitaires (~880 lignes)
│   ├── paths.sh                # Chemins constants
│   ├── secrets.sh              # Gestion secrets Docker/K8s
│   ├── user.sh                 # Gestion PUID/PGID
│   ├── logs.sh                 # Centralisation logs
│   ├── config_json.sh          # Validation config JSON
│   ├── sync.sh                 # Orchestration rclone
│   ├── cron.sh                 # Mode planifié
│   ├── status.sh               # Collecte statuts
│   ├── web.sh                  # Serveur web CGI
│   ├── auth.sh                 # HTTP Basic Auth
│   ├── live.sh                 # CGI stats temps réel
│   ├── snapshot.sh             # CGI snapshot statique
│   ├── control.sh              # CGI contrôle (start/pause/stop/bwlimit)
│   └── kctl.sh                 # Driver wdsync
│
└── www/
    └── index.html              # Interface web (~420 lignes)
```

---

## Configuration

### Variables d'Environnement

#### Connexion WebDAV (critiques)
| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `REMOTE_URL` | string | "" | URL du serveur WebDAV |
| `REMOTE_USER` | string | "" | Utilisateur WebDAV |
| `REMOTE_PASS` | string | "" | Mot de passe WebDAV |
| `SYNC_OP` | choice | "sync" | Opération: sync, copy, move |
| `SYNC_FLAGS` | string | voir Dockerfile | Flags rclone |

**Exemples d'URLs WebDAV:**
| Service | URL |
|---------|-----|
| kDrive | `https://123456.connect.kdrive.infomaniak.com/` |
| Nextcloud | `https://cloud.example.com/remote.php/dav/files/user/` |
| ownCloud | `https://owncloud.example.com/remote.php/webdav/` |
| Synology | `https://nas.example.com:5006/` |

#### Optionnelles
| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `TZ` | string | "Europe/Paris" | Fuseau horaire |
| `NO_LOG` | bool | false | Désactiver logs fichiers |
| `LOG_MAX_DAYS` | int | 5 | Rétention logs (jours) |
| `LOG_LEVEL` | choice | "INFO" | Niveau log rclone (DEBUG, INFO, NOTICE, ERROR) |
| `PUID` | int | 0 | UID utilisateur |
| `PGID` | int | 0 | GID groupe |
| `CRON_ENABLED` | bool | true | Activer mode cron |
| `CRON_SCHEDULE` | cron | "0 5 * * *" | Expression cron |
| `WEB_USER` | string | "admin" | Utilisateur HTTP Basic Auth |
| `WEB_PASS` | string | "" | Mot de passe (vide = pas d'auth) |

### Gestion des Secrets

Ordre de résolution (priorité décroissante):
1. `/run/secrets/VAR` (Docker Secrets)
2. `VAR_FILE` pointant vers un fichier
3. Variable d'environnement `VAR`

### Chemins Fixes
| Chemin | Usage |
|--------|-------|
| `/var/lib/webdav-sync/` | Configuration interne |
| `/webdav-sync/local-files` | Fichiers à synchroniser |
| `/webdav-sync/logs` | Logs rotatifs |
| `/var/lib/webdav-sync/www` | Fichiers web |
| `127.0.0.1:5572` | rclone RC API |

---

## API wdsync

Toutes les commandes retournent un JSON uniforme:

```json
{
  "cmd": "commande exécutée",
  "rc": 0,
  "stdout": "sortie standard",
  "stderr": "sortie erreur",
  "data": null,
  "artifact": null,
  "start_at": "2025-12-23T14:30:00+01:00",
  "end_at": "2025-12-23T14:30:01+01:00",
  "duration_s": 1
}
```

### Commandes Disponibles
| Commande | Description |
|----------|-------------|
| `init-remote` | Initialiser configuration rclone |
| `check-remote` | Vérifier connectivité |
| `op` | Exécuter synchronisation |
| `live` | Stats temps réel via RC API |
| `version` | Version rclone |
| `about-remote` | Espace disque distant |
| `quit` | Arrêter rclone proprement (RC core/quit) |
| `pause` | Suspendre le transfert (SIGSTOP) |
| `resume` | Reprendre le transfert (SIGCONT) |

---

## Interface Web

### Sections
1. **Header** - Status (dot coloré) + titre + texte état
2. **Control Panel** - Boutons Start/Pause/Resume/Stop
3. **Progress Grid** - Progression globale + transferts en cours
4. **Storage** - Barres disque distant et local
5. **Last Run** - Informations dernier lancement
6. **Logs** - Consultation des logs avec sélecteur de date
7. **Rclone Info** - Version et détails

### Contrôles
| Action | Endpoint | Effet |
|--------|----------|-------|
| Start | `/cgi-bin/control.sh?action=start` | Lance une sync en arrière-plan |
| Pause | `/cgi-bin/control.sh?action=pause` | Suspend le processus rclone (SIGSTOP) |
| Resume | `/cgi-bin/control.sh?action=resume` | Reprend le processus (SIGCONT) |
| Stop | `/cgi-bin/control.sh?action=stop` | Arrête rclone via core/quit |
| Logs | `/cgi-bin/logs.sh?lines=100&date=today` | Récupère les dernières lignes de logs |

### Logs

| Fonctionnalité | Détail |
|----------------|--------|
| **Fichiers** | `/webdav-sync/logs/webdav-sync-YYYY-MM-DD.log` |
| **Rotation** | Suppression auto après `LOG_MAX_DAYS` jours |
| **Niveau** | Configurable via `LOG_LEVEL` (DEBUG, INFO, NOTICE, ERROR) |
| **Format** | `[YYYY-MM-DDTHH:MM:SS+TZ] [LEVEL] message` |
| **UI** | Section avec sélecteur de date, coloration syntaxique, téléchargement |
| **Refresh auto** | Toutes les 5s si sync active |

Couleurs dans l'interface :
- 🔴 `[ERROR]` - Rouge
- 🟠 `[WARN]` - Orange
- ⚪ `[INFO]` - Gris
- 🔵 Banner (`===`, `>>`) - Cyan

### États visuels
| État | Dot | Boutons |
|------|-----|---------|
| idle | orange | Start actif, Pause/Stop grisés |
| active | vert | Start grisé, Pause/Stop actifs |
| paused | bleu (accent) | "Reprendre" actif, Pause grisé, Stop actif |
| error | rouge | - |

### Feedback utilisateur
- **Toast** : notification temporaire (2.5s) après chaque action
- **Refresh auto** : mise à jour 500ms après une action
- **Message vide** : "Aucun transfert en cours" si liste vide

### Timings
| Action | Intervalle |
|--------|------------|
| Refresh live | 4000ms |
| Render tick | 50ms |
| Snapshot static | 1x au chargement |
| Snapshot dynamic | 30000ms |

### Design System (CSS Variables)
```css
--bg: #0b0d10        /* Fond principal */
--panel: #12161a     /* Fond panneau */
--muted: #2a3138     /* Bordures */
--text: #e6eef7      /* Texte principal */
--sub: #a7b3c3       /* Texte secondaire */
--accent: #5dd1ff    /* Accent cyan / état paused */
--good: #38d39f      /* Succès vert / état active */
--warn: #ffcc66      /* Avertissement orange / état idle */
--bad: #ff6b81       /* Erreur rouge */
```

---

## Flux d'Exécution

### Démarrage (entrypoint.sh)
1. Chargement de tous les helpers
2. `load_remote_secrets()` - Résolution secrets WebDAV
3. `kcfg_load_and_persist()` - Chargement/validation config
4. `apply_timezone()` - Configuration TZ
5. Choix mode CRON vs Manuel

### Synchronisation (do_run)
1. `ensure_remote()` - Vérifier/recréer config rclone si nécessaire
2. `rotate_logs()` - Supprimer vieux logs
3. `log_banner()` - Afficher en-tête
4. `kctl op` - Exécuter wdsync op (→ rclone sync)
5. Retourner code retour

### Mode CRON
1. `write_cron_wrapper()` - Créer wrapper avec flock
2. `install_crontab()` - Écrire crontab
3. `start_cron_foreground()` - Lancer crond -f (bloquant)

---

## Patterns de Code

### Modularité par Helpers
- Chaque helper = une responsabilité
- Préfixes de fonctions: `kcfg_*`, `log_*`, `kctl_*`
- Pas de dépendances circulaires

### Sécurité
- Validation stricte des types (pas d'eval)
- Obscurcissement mots de passe rclone
- MD5 pour détecter changements credentials
- Permissions 600 sur fichiers sensibles

### Concurrence
- flock sur `/var/lock/rclone.cron.lock`
- Évite exécutions parallèles
- Fichiers temporaires avec mktemp

### Gestion Utilisateurs
- Support su-exec, gosu, setpriv
- Setup user/group idempotent
- Re-exécution avec bon UID/GID

---

## Métriques

| Composant | Lignes |
|-----------|--------|
| entrypoint.sh | ~100 |
| wdsync.sh | ~185 |
| index.html | ~555 |
| helpers/* | ~950 |
| **Total** | **~1790** |

---

## Docker

### Volumes
| Volume | Usage |
|--------|-------|
| `/webdav-sync/local-files` | Fichiers à synchroniser |
| `/webdav-sync/logs` | Logs rotatifs |

### Port
- 8080 (interface web)

### Exemple docker-compose

**Avec kDrive:**
```yaml
version: '3.8'
services:
  webdav-sync:
    build: .
    environment:
      - REMOTE_URL=https://123456.connect.kdrive.infomaniak.com/
      - REMOTE_USER=user@example.com
      - REMOTE_PASS=secret
      - TZ=Europe/Paris
      - CRON_SCHEDULE=0 5 * * *
      - WEB_PASS=monsecret  # Active l'auth HTTP (user: admin)
    volumes:
      - ./data:/webdav-sync/local-files
      - ./logs:/webdav-sync/logs
    ports:
      - "8080:8080"
```

**Avec Nextcloud:**
```yaml
version: '3.8'
services:
  webdav-sync:
    build: .
    environment:
      - REMOTE_URL=https://nextcloud.example.com/remote.php/dav/files/username/
      - REMOTE_USER=username
      - REMOTE_PASS=app-password
      - TZ=Europe/Paris
      - CRON_SCHEDULE=0 */6 * * *  # Toutes les 6 heures
    volumes:
      - ./data:/webdav-sync/local-files
      - ./logs:/webdav-sync/logs
    ports:
      - "8080:8080"
```
