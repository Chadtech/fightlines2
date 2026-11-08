#!/usr/bin/env bash
# Called by the remote installer after an immutable release is built and installed.
set -euo pipefail
release_id=${1:?release id required}
[[ $release_id =~ ^[a-z0-9-]{1,100}$ ]] || exit 2
release_dir=/opt/fightlines/releases/$release_id
runtime_dir=/var/lib/fightlines/deployments/$release_id
environment_file=/etc/fightlines/deployments/$release_id.env
test "$(id -u)" = 0
supervisor=/opt/fightlines/deployment/fightlines-supervisor
test -x "$supervisor"
test -f "$release_dir/fightlines-server"
if [[ -e $runtime_dir || -e $environment_file ]]; then
    printf 'Deployment already has runtime state or service configuration; use a fresh deployment id.\n' >&2
    exit 1
fi
# Keep the caller's deployment lock through port allocation and activation.
port=$("$supervisor" --root /var/lib/fightlines/deployments available-port)
install -d -o fightlines -g fightlines -m 700 "$runtime_dir"
install -d -m 700 /etc/fightlines/deployments
set -o noclobber
cat > "$environment_file" <<ENV
FIGHTLINES_ADDR=127.0.0.1:$port
FIGHTLINES_DEPLOYMENT_ID=$release_id
FIGHTLINES_DEPLOYMENTS_DIR=/var/lib/fightlines/deployments
FIGHTLINES_FRONTEND_DIR=$release_dir/public
FIGHTLINES_MAP_DIR=$release_dir/maps
FIGHTLINES_GAME_LOG_DIR=$runtime_dir/game-logs
FIGHTLINES_FEEDBACK_DIR=$runtime_dir/feedback
FIGHTLINES_SERVER_LOG_DIR=$runtime_dir/server-logs
ENV
chmod 600 "$environment_file"
# The timer and activation share this config; changing it cannot extend an
# already-recorded drain deadline.
source /etc/fightlines/deployment-supervisor.env
"$supervisor" \
    --root /var/lib/fightlines/deployments \
    --routes /etc/caddy/fightlines-routes.caddy \
    --caddy-config /etc/caddy/Caddyfile \
    --max-drain-seconds "$FIGHTLINES_MAX_DRAIN_SECONDS" \
    activate "$release_id" --port "$port"
printf 'Activated %s on private port %s; previous deployments are draining.\n' "$release_id" "$port"
