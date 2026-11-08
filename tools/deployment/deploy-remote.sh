#!/usr/bin/env bash
# Executed over SSH by deploy.sh, on the already-provisioned Ubuntu Droplet.
set -euo pipefail

release_id=${1:?release ID required}
bundle_sha=${2:?bundle SHA-256 required}
public_url=${3:?public HTTPS origin required}
install_dir=/opt/fightlines
build_home=${FIGHTLINES_BUILD_HOME:-/var/lib/fightlines-build}

if [[ ! $release_id =~ ^release-[0-9]{8}t[0-9]{6}z-[a-f0-9]{12}$ \
    || ! $bundle_sha =~ ^[a-f0-9]{64}$ \
    || ! $public_url =~ ^https://[a-zA-Z0-9.-]+(:[0-9]+)?$ ]]; then
    printf 'Invalid deployment arguments.\n' >&2
    exit 2
fi
test "$(id -u)" = 0 || { printf 'Remote deployment requires root.\n' >&2; exit 1; }

# Serialize the entire build/activation so overlapping deployments cannot mix artifacts.
exec 9>"$install_dir/.deploy.lock"
flock -n 9 || { printf 'Another deployment is already running.\n' >&2; exit 1; }
test -x /opt/fightlines/deployment/fightlines-supervisor || { printf 'Install deployment supervisor first; see DEPLOYMENT.md.\n' >&2; exit 1; }
upload_dir="$build_home/uploads/$release_id"
source_dir="$build_home/builds/$release_id"
release_dir="$install_dir/releases/$release_id"
test ! -e "$source_dir"
test ! -e "$release_dir"
printf '%s  %s\n' "$bundle_sha" "$upload_dir/release.tar.gz" | sha256sum -c
mkdir -p "$source_dir"
tar -xzf "$upload_dir/release.tar.gz" -C "$source_dir"
test -s "$source_dir/public/elm.js"
grep -q 'isProduction: true' "$source_dir/public/build-config.js"
for file in dev-tools.html dev-tools.js elm-dev-tools.js; do test ! -e "$source_dir/public/$file"; done
chown -R fightlines-build:fightlines-build "$source_dir"

printf '\nBuilding Linux server; the current release is still running.\n'
runuser -u fightlines-build -- env \
    PATH="$build_home/.cargo/bin:/usr/local/bin:/usr/bin:/bin" \
    CARGO_BUILD_JOBS=1 CARGO_TARGET_DIR="$build_home/source/target" \
    FIGHTLINES_BUILD_REVISION="$release_id" \
    bash -c 'cd "$1" && cargo build --locked --release' bash "$source_dir"

mkdir -p "$release_dir"
install -m 755 "$build_home/source/target/release/fightlines-server" "$release_dir/fightlines-server"
cp -R "$source_dir/public" "$source_dir/maps" "$release_dir/"
cp "$source_dir/RELEASE.json" "$release_dir/RELEASE.json"
printf '%s\n' "$bundle_sha" > "$release_dir/bundle.sha256"
chown -R root:root "$release_dir"
find "$release_dir" -type d -exec chmod 755 {} +
find "$release_dir" -type f -exec chmod 644 {} +
chmod 755 "$release_dir/fightlines-server"

# Supervisor code stays compatible across overlapping releases. Deployments
# retain their own binary/assets/maps and private writable storage.
bash "$source_dir/tools/deployment/install.sh" "$build_home/source/target/release/fightlines-supervisor"
bash /opt/fightlines/deployment/activate.sh "$release_id"
systemctl enable --now fightlines-retire.timer
printf '\nRelease active: %s\n' "$release_dir"

# Failure after cutover leaves admitted sessions alive for inspection/recovery.
curl --fail --silent --show-error --max-time 15 "$public_url/_releases/$release_id/graphql" \
    -H 'Content-Type: application/json' --data '{"query":"{ health }"}' | grep -Eq '"health"[[:space:]]*:[[:space:]]*true'
expected_frontend=$(sha256sum "$release_dir/public/elm.js" | awk '{print $1}')
served_frontend=$(curl --fail --silent --show-error --max-time 30 "$public_url/_releases/$release_id/elm.js" | sha256sum | awk '{print $1}')
test "$served_frontend" = "$expected_frontend"
