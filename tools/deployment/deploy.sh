#!/usr/bin/env bash
# Run on the Mac: snapshot -> check -> build frontend -> upload -> build Linux -> activate.
set -euo pipefail

repository=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
ssh_target=${FIGHTLINES_SSH_TARGET:-root@167.71.23.178}
public_url=${FIGHTLINES_PUBLIC_URL:-https://fightlines.online}
known_hosts=${FIGHTLINES_KNOWN_HOSTS:-$repository/deploy/known_hosts}
mode=deploy

usage() {
    cat <<'HELP'
Usage: ./tools/deployment/deploy.sh [--dry-run | --prepare | --help]

  --dry-run  Describe the deployment. No builds, uploads, or server changes.
  --prepare  Check and package a local snapshot. No SSH or server changes.
  no flag    Prepare, upload, build on the Droplet, and activate the release.

Includes saved tracked and relevant untracked build inputs. Never commits, pushes,
or bumps VERSION. Activation starts a new deployment and drains existing sessions.

Optional environment: FIGHTLINES_SSH_TARGET, FIGHTLINES_PUBLIC_URL,
FIGHTLINES_KNOWN_HOSTS. Defaults target the existing FightLines Droplet.
HELP
}

case "${1:-}" in
    --help|-h) usage; exit 0 ;;
    --dry-run) mode=preview ;;
    --prepare) mode=prepare ;;
    '') ;;
    *) usage >&2; exit 2 ;;
esac
if (( $# > 1 )); then usage >&2; exit 2; fi
if [[ ! $ssh_target =~ ^[a-zA-Z0-9_.@:-]+$ || $ssh_target == -* ]]; then
    printf 'Invalid SSH target: %s\n' "$ssh_target" >&2
    exit 2
fi
public_url=${public_url%/}
if [[ ! $public_url =~ ^https://[a-zA-Z0-9.-]+(:[0-9]+)?$ ]]; then
    printf 'FIGHTLINES_PUBLIC_URL must be an HTTPS origin without a path.\n' >&2
    exit 2
fi

cat <<PLAN
Target: $ssh_target
Website: $public_url
1. Copy saved build inputs into a private temporary snapshot.
2. Generate silent truck audio, install npm dependencies, and run make check.
3. Run make frontend PRODUCTION=true and package the checked snapshot.
4. Upload over SSH, verifying the recorded host key and archive SHA-256.
5. Build the Linux server as fightlines-build while the current game stays up.
6. Install and health-check a new process, switch Caddy, and drain old releases.
7. Verify public health and the exact frontend checksum; preserve sessions on failure.
Activation drains existing games and lobbies. Feedback, archives, HTTPS, and config stay in place.
PLAN
if [[ $mode == preview ]]; then exit 0; fi

for command in node npm cargo elm elm-format make git tar ffmpeg shasum; do
    command -v "$command" >/dev/null || { printf 'Required command missing: %s\n' "$command" >&2; exit 1; }
done
node -e 'if (Number(process.versions.node.split(".")[0]) < 22) { console.error("Node.js 22+ is required."); process.exit(1); }'
if [[ $mode == deploy ]]; then
    for command in ssh scp; do command -v "$command" >/dev/null; done
    test -f "$known_hosts" || { printf 'SSH known-hosts file missing: %s\n' "$known_hosts" >&2; exit 1; }
fi

work_dir=$(mktemp -d "${TMPDIR:-/tmp}/fightlines-deploy.XXXXXX")
printf '\nLocal preparation directory: %s\n' "$work_dir"
node "$repository/tools/deployment/snapshot.cjs" "$repository" "$work_dir/source"
(
    cd "$work_dir/source"
    # Keep the audition clip off the server; its runtime path remains valid.
    ffmpeg -hide_banner -loglevel error -f lavfi -i anullsrc=r=48000:cl=mono \
        -t 6.6 -c:a libvorbis -metadata title='Silent replacement for unlicensed truck preview' \
        public/audio/movement/truck-volvo-6s.ogg
    npm ci
    # Share only Cargo's build cache; all generated source/frontend files stay in the snapshot.
    export CARGO_TARGET_DIR="$repository/target"
    make check
    make frontend PRODUCTION=true
    # Suppress macOS AppleDouble metadata; Linux would treat ._*.json as maps.
    # Also exclude private runtime files if a check creates any inside the snapshot.
    COPYFILE_DISABLE=1 tar --exclude='._*' \
        --exclude=./node_modules --exclude=./target --exclude=./elm-stuff \
        --exclude=./game-logs --exclude=./server-logs --exclude=./feedback \
        --exclude=./.git --exclude='.env' --exclude='.env.*' \
        -czf "$work_dir/release.tar.gz" .
)
bundle_sha=$(shasum -a 256 "$work_dir/release.tar.gz" | awk '{print $1}')
release_id="release-$(date -u +%Y%m%dt%H%M%Sz)-${bundle_sha:0:12}"
printf '\nPrepared %s\nArchive: %s\nSHA-256: %s\n' "$release_id" "$work_dir/release.tar.gz" "$bundle_sha"
if [[ $mode == prepare ]]; then exit 0; fi

ssh_options=(-o BatchMode=yes -o ConnectTimeout=15 -o StrictHostKeyChecking=yes -o "UserKnownHostsFile=$known_hosts")
upload_dir="/var/lib/fightlines-build/uploads/$release_id"
ssh "${ssh_options[@]}" "$ssh_target" "mkdir -p '$upload_dir' && chmod 700 '$upload_dir'"
scp "${ssh_options[@]}" "$work_dir/release.tar.gz" "$ssh_target:$upload_dir/release.tar.gz"
# %q quotes every argument for the Droplet's bash login shell.
printf -v remote_command '%q ' bash -s -- "$release_id" "$bundle_sha" "$public_url"
ssh "${ssh_options[@]}" "$ssh_target" "$remote_command" < "$work_dir/source/tools/deployment/deploy-remote.sh"
printf '\nDeployed %s to %s\n' "$release_id" "$public_url"
