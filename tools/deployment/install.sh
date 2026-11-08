#!/usr/bin/env bash
# Install supervisor support on an already-provisioned Linux host. Does not
# modify Caddy's site configuration, activate a release, or stop legacy service.
set -euo pipefail
test "$(id -u)" = 0
source_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
supervisor_binary=${1:-$source_dir/../../target/release/fightlines-supervisor}
test -x "$supervisor_binary" || { printf 'Build the native fightlines-supervisor binary first.\n' >&2; exit 1; }
install -d -m 755 /opt/fightlines/deployment
# Replace atomically so an in-flight timer invocation can finish on its binary.
install -m 755 "$supervisor_binary" /opt/fightlines/deployment/fightlines-supervisor.tmp
mv -f /opt/fightlines/deployment/fightlines-supervisor.tmp /opt/fightlines/deployment/fightlines-supervisor
install -m 755 "$source_dir/activate.sh" /opt/fightlines/deployment/activate.sh
install -m 644 "$source_dir/fightlines@.service" "$source_dir/fightlines-retire.service" "$source_dir/fightlines-retire.timer" /etc/systemd/system/
install -d -o fightlines -g fightlines -m 700 /var/lib/fightlines/deployments
if [[ ! -f /etc/fightlines/deployment-supervisor.env ]]; then
    printf 'FIGHTLINES_MAX_DRAIN_SECONDS=21600\n' > /etc/fightlines/deployment-supervisor.env
    chmod 600 /etc/fightlines/deployment-supervisor.env
fi
systemctl daemon-reload
# Enable only after configuring Caddy and activating the first release.
printf 'Supervisor installed. Follow DEPLOYMENT.md for the one-time cutover before enabling fightlines-retire.timer.\n'
