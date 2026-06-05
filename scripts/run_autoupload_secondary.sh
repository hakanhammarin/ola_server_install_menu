#!/bin/bash
# ============================================================
#  10mila Auto-Upload Runner — Secondary Server
#  Called by systemd 10mila-autoupload-secondary.service.
#  Only uploads .sql files that are missing on the remote.
# ============================================================

CONFIG_FILE="$HOME/.10mila_menu.conf"
PASS_FILE="$HOME/.10mila_secondary.pass"

log() { echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) $*"; }

if [ ! -f "$CONFIG_FILE" ]; then log "ERROR: Config not found: $CONFIG_FILE"; exit 1; fi
if [ ! -f "$PASS_FILE" ];   then log "ERROR: Password file not found: $PASS_FILE"; exit 1; fi

source "$CONFIG_FILE"

LOCAL_DIR="${BACKUP_DIR:-$HOME/backups}"
SEC_HOST="$SECONDARY_HOST"
SEC_USER="$SECONDARY_USER"
SEC_PATH="${SECONDARY_PATH:-~/backups}"
SSH_PASS="$(cat "$PASS_FILE")"

if [ -z "$SEC_HOST" ] || [ -z "$SEC_USER" ]; then
    log "ERROR: SECONDARY_HOST or SECONDARY_USER not set in $CONFIG_FILE"
    exit 1
fi

# ---- List local backup files (basename only, skip files younger than 3 min) ----
mapfile -t LOCAL_FILES < <(
    find "$LOCAL_DIR" -maxdepth 1 -name "*.sql" -mmin +3 \
        -printf "%f\n" 2>/dev/null | sort
)

if [ ${#LOCAL_FILES[@]} -eq 0 ]; then
    log "No local backups ready to upload (all either absent or too recent)."
    exit 0
fi

# ---- List files already on remote ----
mapfile -t REMOTE_FILES < <(
    SSHPASS="$SSH_PASS" sshpass -e ssh \
        -o StrictHostKeyChecking=accept-new \
        -o ConnectTimeout=15 \
        -o BatchMode=no \
        "$SEC_USER@$SEC_HOST" \
        "ls \"$SEC_PATH\"/*.sql 2>/dev/null | xargs -r -n1 basename | sort" 2>/dev/null
)

if [ $? -ne 0 ]; then
    log "ERROR: Could not reach $SEC_USER@$SEC_HOST — skipping this run."
    exit 1
fi

# ---- Compute delta: local files not present on remote ----
declare -A REMOTE_SET
for f in "${REMOTE_FILES[@]}"; do REMOTE_SET["$f"]=1; done

MISSING=()
for f in "${LOCAL_FILES[@]}"; do
    [ -z "${REMOTE_SET[$f]+x}" ] && MISSING+=("$f")
done

if [ ${#MISSING[@]} -eq 0 ]; then
    log "Remote is up to date — nothing to upload. (${#LOCAL_FILES[@]} local, ${#REMOTE_FILES[@]} remote)"
    exit 0
fi

log "Delta: ${#MISSING[@]} file(s) to upload out of ${#LOCAL_FILES[@]} local."

# ---- Upload missing files one by one ----
UPLOADED=0
FAILED=0
for fname in "${MISSING[@]}"; do
    LOCAL_FILE="$LOCAL_DIR/$fname"
    SIZE=$(du -sh "$LOCAL_FILE" 2>/dev/null | cut -f1)
    log "Uploading: $fname ($SIZE) ..."

    SSHPASS="$SSH_PASS" sshpass -e scp \
        -o StrictHostKeyChecking=accept-new \
        -o ConnectTimeout=30 \
        -o BatchMode=no \
        "$LOCAL_FILE" "$SEC_USER@$SEC_HOST:$SEC_PATH/$fname"

    if [ $? -eq 0 ]; then
        log "  OK: $fname"
        (( UPLOADED++ ))
    else
        log "  FAILED: $fname"
        (( FAILED++ ))
    fi
done

log "Done. Uploaded: $UPLOADED  Failed: $FAILED"
[ $FAILED -gt 0 ] && exit 1 || exit 0
