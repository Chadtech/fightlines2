#!/usr/bin/env python3
"""Exercise real servers through real Caddy, with private temporary storage.
Use --serve for a manual two-browser rehearsal (enter b to deploy B, q to quit).
"""
import argparse
import contextlib
import http.cookiejar
import json
import os
from pathlib import Path
import shutil
import ssl
import socket
import subprocess
import tempfile
import time
import urllib.error
import urllib.request

REPOSITORY = Path(__file__).resolve().parents[2]


def free_port(excluded=()):
    while True:
        with socket.socket() as sock:
            sock.bind(('127.0.0.1', 0))
            port = sock.getsockname()[1]
        if port not in excluded:
            return port


def read_registry(root):
    path = root / 'registry.json'
    return json.loads(path.read_text()) if path.exists() else {'current': None, 'releases': {}}


def wait_for(check, timeout=15):
    deadline = time.monotonic() + timeout
    last = None
    while time.monotonic() < deadline:
        try:
            return check()
        except (OSError, ValueError, AssertionError, KeyError) as error:
            last = error
            time.sleep(0.1)
    raise RuntimeError(f'timed out: {last}')


def browser(local_https=False):
    handlers = [urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar())]
    if local_https:
        # Trust is scoped to this temporary test client; no system trust changes.
        handlers.append(urllib.request.HTTPSHandler(context=ssl._create_unverified_context()))
    return urllib.request.build_opener(*handlers)


def request(client, url, query=None, origin=None, extra_headers=None):
    headers = {'Accept': 'text/html', **(extra_headers or {})}
    data = None
    if query:
        headers = {'Content-Type': 'application/json', 'Origin': origin}
        data = json.dumps({'query': query}).encode()
    with client.open(urllib.request.Request(url, data=data, headers=headers), timeout=10) as response:
        body = response.read()
        return json.loads(body) if query else (response.url, body.decode(errors='replace'))


def hold_orders(snapshot):
    player = next(player for player in snapshot['players'] if player['isYou'])
    orders = []
    for unit in snapshot['scenario']['units']:
        if unit['playerNumber'] != player['playerNumber']:
            continue
        # Every unit in a fresh authored game starts on the map.
        position = unit['location']['position']
        orders.append('{unitId:' + json.dumps(unit['id']) + ',path:[{x:' + str(position['x']) + ',y:' + str(position['y']) + '}]}')
    return ','.join(orders)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--caddy', default=shutil.which('caddy'))
    parser.add_argument('--serve', action='store_true')
    parser.add_argument('--https', action='store_true', help='exercise production cookies through local HTTPS without installing a CA')
    args = parser.parse_args()
    if not args.caddy:
        parser.error('install Caddy or supply --caddy /path/to/caddy')
    binary = REPOSITORY / 'target/debug/fightlines-server'
    supervisor_binary = REPOSITORY / 'target/debug/fightlines-supervisor'
    if not binary.exists() or not supervisor_binary.exists() or not (REPOSITORY / 'public/elm.js').exists():
        parser.error('run make frontend and cargo build --locked first')
    with tempfile.TemporaryDirectory(prefix='fightlines-rehearsal-') as temporary, contextlib.ExitStack() as cleanup:
        root = Path(temporary)
        runtime = root / 'deployments'
        runtime.mkdir()
        routes = root / 'routes.caddy'
        routes.write_text('respond "no deployment" 503\n')
        config = root / 'Caddyfile'
        port = free_port()
        origin = f'https://localhost:{port}' if args.https else f'http://127.0.0.1:{port}'
        config.write_text(f'{{\n admin 127.0.0.1:{free_port()}\n auto_https disable_redirects\n skip_install_trust\n}}\n{origin} {{\n' + (' tls internal\n' if args.https else '') + f' bind 127.0.0.1\n import {routes}\n}}\n')
        log = cleanup.enter_context((root / 'processes.log').open('w'))
        caddy = subprocess.Popen([args.caddy, 'run', '--config', str(config), '--adapter', 'caddyfile'], stdout=log, stderr=log,
                                 env={**os.environ, 'XDG_DATA_HOME': str(root / 'caddy-data'), 'XDG_CONFIG_HOME': str(root / 'caddy-config')})
        processes = [caddy]
        def stop_all():
            for process in reversed(processes):
                if process.poll() is None:
                    process.terminate()
            for process in processes:
                try:
                    process.wait(timeout=20)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
        cleanup.callback(stop_all)
        # A precomputed test-only Argon2id hash. It is unrelated to production credentials.
        password_hash = '$argon2id$v=19$m=19456,t=2,p=1$4seKJL2gDbLs+YyhilxCPg$2gtCjdc0biEXLYWu8jYs6aqa1IAyHZCY9tuL8PT4Z3c'
        releases = {}
        def reserved_ports():
            return set(json.loads(subprocess.check_output([
                str(supervisor_binary), '--root', str(runtime), 'reserved-ports'], text=True)))
        def start(deployment_id, server_port=None):
            reserved = reserved_ports()
            if server_port is None:
                server_port = free_port(reserved)
            if server_port in reserved:
                raise ValueError('cannot start a release on a reserved port')
            directory = runtime / deployment_id
            directory.mkdir()
            frontend = root / f'frontend-{deployment_id}'
            # Immutable copies of entry points; large read-only asset directories can
            # be shared in this harness. Production installs full release copies.
            frontend.mkdir()
            for source in (REPOSITORY / 'public').iterdir():
                target = frontend / source.name
                if source.is_dir():
                    target.symlink_to(source)
                else:
                    shutil.copyfile(source, target)
            (frontend / 'release-marker.txt').write_text(deployment_id)
            environment = {**os.environ, 'FIGHTLINES_ENV': 'production' if args.https else 'development', 'FIGHTLINES_ADDR': f'127.0.0.1:{server_port}',
                           'FIGHTLINES_DEPLOYMENT_ID': deployment_id, 'FIGHTLINES_DEPLOYMENTS_DIR': str(runtime),
                           'FIGHTLINES_FRONTEND_DIR': str(frontend), 'FIGHTLINES_MAP_DIR': str(REPOSITORY / 'maps'),
                           'FIGHTLINES_GAME_LOG_DIR': str(directory / 'game-logs'), 'FIGHTLINES_FEEDBACK_DIR': str(directory / 'feedback'),
                           'FIGHTLINES_SERVER_LOG_DIR': str(directory / 'server-logs')}
            environment.pop('FIGHTLINES_SEED', None)
            # Override any private .env admin configuration with a rehearsal-only hash.
            environment['FIGHTLINES_ADMIN_PASSWORD_HASH'] = password_hash
            process = subprocess.Popen([str(binary)], cwd=root, env=environment, stdout=log, stderr=log)
            processes.append(process)
            releases[deployment_id] = (process, server_port)
            wait_for(lambda: json.loads((directory / 'status.json').read_text()))

        manage = [str(supervisor_binary), '--root', str(runtime), '--routes', str(routes),
                  '--caddy-config', str(config), '--caddy', args.caddy, '--local', '--max-drain-seconds', '30' if not args.serve else '600']
        def activate(deployment_id):
            process, server_port = releases[deployment_id]
            subprocess.run([*manage, 'activate', deployment_id, '--port', str(server_port), '--pid', str(process.pid)], check=True, stdout=log, stderr=log)
        def sweep():
            subprocess.run([*manage, 'sweep'], check=True, stdout=log, stderr=log)
        start('a')
        activate('a')
        host, guest = browser(args.https), browser(args.https)
        api = lambda deployment_id: origin + f'/_releases/{deployment_id}/graphql'
        def query(client, deployment_id, document):
            result = request(client, api(deployment_id), document, origin)
            assert not result.get('errors'), result
            return result['data']
        def assert_draining():
            assert query(host, 'a', '{ deploymentStatus { draining } }')['deploymentStatus']['draining']
        def status(deployment_id):
            return json.loads((runtime / deployment_id / 'status.json').read_text())
        def assert_status(path, expected, headers=None):
            try:
                request(host, origin + path, extra_headers=headers)
                raise AssertionError(f'{path} should return {expected}')
            except urllib.error.HTTPError as error:
                assert error.code == expected, (path, error.code)
        start('b')
        if args.serve:
            print(f'Open {origin} in two browser profiles. Admin password: local-rehearsal-only')
            print(f'Runtime: {root}\nEnter b to activate B, s to sweep retirement, q to quit.', flush=True)
            while True:
                command = input('rehearsal> ').strip().lower()
                if command == 'q':
                    break
                try:
                    if command == 'b':
                        if 'b' in read_registry(runtime)['releases']:
                            print('Release B is already registered. Enter s to check routing and retirement.', flush=True)
                            continue
                        activate('b')
                    sweep()
                except subprocess.CalledProcessError as error:
                    print(f'Control command failed (exit {error.returncode}). Rehearsal remains open; see {root / "processes.log"}. Enter s to retry routing and retirement.', flush=True)
            return
        created = query(host, 'a', 'mutation { createLobby(name:"host", lobbyName:"survives cutover") { id } }')
        game_id = created['createLobby']['id']
        # Routing must work immediately, without waiting for a heartbeat/sweep.
        assert '<base href="/_releases/a/">' in request(host, origin + f'/lobby/{game_id}')[1]
        first_match, second_match = browser(args.https), browser(args.https)
        match_selection = ' { ... on MatchMakingMatched { gameId } }'
        query(first_match, 'a', 'mutation { joinMatchMaking(name:"match one")' + match_selection + ' }')
        paired = query(second_match, 'a', 'mutation { joinMatchMaking(name:"match two")' + match_selection + ' }')['joinMatchMaking']['gameId']
        waiter = browser(args.https)
        waiting = query(waiter, 'a', 'mutation { joinMatchMaking(name:"waiting") { ... on MatchMakingWaiting { ticket } } }')['joinMatchMaking']
        activate('b')
        wait_for(assert_draining)
        recovered = query(second_match, 'a', 'mutation { joinMatchMaking(name:"match two")' + match_selection + ' }')['joinMatchMaking']['gameId']
        assert recovered == paired, 'pairing recovery must survive cutover'
        queue_result = request(waiter, api('a'), 'mutation { pollMatchMaking(ticket:' + json.dumps(waiting['ticket']) + ') { ... on MatchMakingWaiting { ticket } } }', origin)
        assert queue_result['errors'][0]['extensions']['code'] == 'DEPLOYMENT_DRAINING', queue_result
        entry_url = request(host, origin + '/match-making')[0]
        assert entry_url == origin + '/match-making', entry_url
        assert '<base href="/_releases/b/">' in request(host, entry_url)[1]
        assert f'<base href="/_releases/a/">' in request(host, origin + f'/lobby/{game_id}')[1]
        assert request(guest, origin + f'/lobby/{game_id}')[0] == origin + f'/lobby/{game_id}'
        assert '<base href="/_releases/a/">' in request(guest, origin + f'/lobby/{game_id}/maps')[1]
        assert '<base href="/_releases/a/">' in request(host, origin + f'/game/{paired}')[1]
        assert request(host, origin + '/_releases/a/release-marker.txt')[1] == 'a'
        assert request(host, origin + '/_releases/b/release-marker.txt')[1] == 'b'
        for path in ['/_routing', '/_releases/a/_routing', '/_releases/b/_routing', '/lobby/invalid/maps', '/game/invalid']:
            assert_status(path, 404)
        assert_status('/game/' + 'f' * 32, 404, {'X-Fightlines-Upstream': '127.0.0.1:1'})
        # A broken ownership registry must fail closed, even with a forged target.
        registry_path = runtime / 'registry.json'
        registry_bytes = registry_path.read_bytes()
        try:
            registry_path.write_text('invalid')
            assert_status(f'/lobby/{game_id}', 503, {'X-Fightlines-Upstream': '127.0.0.1:1'})
        finally:
            registry_path.write_bytes(registry_bytes)
        rejected = request(host, api('a'), 'mutation { createLobby(name:"host", lobbyName:"must move") { id } }', origin)
        assert rejected['errors'][0]['extensions']['code'] == 'DEPLOYMENT_DRAINING', rejected
        # Existing invite still admits the guest and can transition into a game.
        query(guest, 'a', f'mutation {{ joinLobby(id:"{game_id}", name:"guest") {{ id }} }}')
        query(host, 'a', f'mutation {{ startGame(id:"{game_id}") {{ id }} }}')
        # Read each player's actual board, independent of the authored default map.
        for client in [host, guest]:
            snapshot = query(client, 'a', f'''{{ game(id:"{game_id}") {{
                turnNumber players {{ isYou playerNumber }}
                scenario {{ units {{ id playerNumber
                    location {{ ... on OnMap {{ position {{ x y }} }} }}
                }} }}
            }} }}''')['game']
            holds = hold_orders(snapshot)
            query(client, 'a', f'mutation {{ submitTurn(id:"{game_id}", turnNumber:{snapshot["turnNumber"]}, orders:[{holds}]) {{ id }} }}')
        new_lobby = query(host, 'b', 'mutation { createLobby(name:"host", lobbyName:"new deployment") { id } }')['createLobby']['id']
        assert '<base href="/_releases/b/">' in request(host, origin + f'/lobby/{new_lobby}')[1]
        assert '<base href="/_releases/a/">' in request(host, origin + f'/game/{game_id}')[1]
        query(guest, 'a', f'mutation {{ resignGame(id:"{game_id}") {{ id }} }}')
        def assert_postgame():
            assert status('a')['retained_finished_games'] == 1
        wait_for(assert_postgame)
        admin = browser(args.https)
        query(admin, 'b', 'mutation { adminLogin(password:"local-rehearsal-only") }')
        overview = query(admin, 'b', '{ adminDashboard { deployments { id available status { concurrentGames retainedFinishedGames } } } }')['adminDashboard']['deployments']
        assert len(overview) == 2, overview
        assert all(deployment['available'] for deployment in overview), overview
        assert query(admin, 'b', '{ adminRecordings { total } }')['adminRecordings']['total'] == 2
        sweep()
        assert releases['a'][0].poll() is None, 'postgame viewing must keep A alive'
        # Shorten only the test clock's stored deadline to exercise the actual
        # supervisor cutoff without waiting six hours. Production never extends it.
        drain = json.loads((runtime / 'a/drain.json').read_text())
        drain['deadline_unix_ms'] = int(time.time() * 1000) - 1
        (runtime / 'a/drain.json').write_text(json.dumps(drain))
        # Force retirement while the live proxy still has A's old route loaded.
        broken_manage = manage.copy()
        broken_manage[broken_manage.index('--caddy') + 1] = str(root / 'missing-caddy')
        failed = subprocess.run([*broken_manage, 'sweep'], stdout=log, stderr=log)
        assert failed.returncode != 0, 'the injected Caddy reload failure must be observed'
        releases['a'][0].wait(timeout=20)
        retired = read_registry(runtime)['releases']['a']
        assert not retired['running'] and not retired['port_reusable']
        try:
            start('c', server_port=releases['a'][1])
            raise AssertionError('a stopped port must stay reserved while Caddy has its route')
        except ValueError:
            pass
        # Reconcile the stale route before allowing that same port to be reused.
        sweep()
        assert read_registry(runtime)['releases']['a']['port_reusable']
        assert query(host, 'b', '{ health }')['health']
        assert_status(f'/game/{game_id}', 410)
        assert_status(f'/lobby/{game_id}', 410)
        assert_status('/_releases/a/graphql', 410)
        start('c', server_port=releases['a'][1])
        activate('c')
        assert_status('/_releases/a/graphql', 410)
        assert_status(f'/game/{game_id}', 410)
        query(host, 'b', 'mutation { closeLobby(id:' + json.dumps(new_lobby) + ') }')
        def assert_empty():
            assert status('b')['safe_to_stop']
        wait_for(assert_empty)
        sweep()
        releases['b'][0].wait(timeout=20)
        assert query(host, 'c', '{ health }')['health']
        print('PASS: real Caddy cutover, stable entry/invite/game URLs, owner-selected documents/assets, stale-tab rejection, invite joining, turn resolution, postgame retention, deadline retirement, failed-reload port reservation and safe reuse, empty-server retirement, Admin aggregation, and current-release continuity.')


if __name__ == '__main__':
    main()
