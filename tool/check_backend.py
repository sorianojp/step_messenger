#!/usr/bin/env python3
"""Exercise Dart API/Reverb clients against an isolated running Laravel app."""
import argparse
import base64
import os
from pathlib import Path
import secrets
import shutil
import signal
import socket
import subprocess
import tempfile
import time


def port():
    with socket.socket() as server:
        server.bind(('127.0.0.1', 0))
        return server.getsockname()[1]


def ready(server_port, process):
    for _ in range(100):
        if process.poll() is not None:
            raise RuntimeError('A test server exited before becoming ready.')
        try:
            with socket.create_connection(('127.0.0.1', server_port), timeout=.2):
                return
        except OSError:
            time.sleep(.1)
    raise RuntimeError('A test server did not become ready within 10 seconds.')


def main():
    project = Path(__file__).resolve().parents[1]
    backend = project.parent / 'chat-app'
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--php', default=shutil.which('php') or str(Path.home() / 'Library/Application Support/Herd/bin/php'))
    parser.add_argument('--dart', default=shutil.which('dart') or str(Path.home() / 'Development/flutter/bin/dart'))
    args = parser.parse_args()
    os.umask(0o077)
    with tempfile.TemporaryDirectory(prefix='step-mobile-check-') as directory:
        root = Path(directory)
        for folder in ['storage/framework/cache/data', 'storage/framework/views', 'storage/framework/sessions', 'storage/logs', 'storage/app/private']:
            (root / folder).mkdir(parents=True, exist_ok=True)
        (root / 'database.sqlite').touch()
        api_port, reverb_port = port(), port()
        while reverb_port == api_port:
            reverb_port = port()
        env = {**os.environ, 'APP_ENV': 'testing', 'APP_DEBUG': 'false',
               'APP_URL': f'http://127.0.0.1:{api_port}',
               'APP_KEY': 'base64:' + base64.b64encode(secrets.token_bytes(32)).decode(),
               'DB_CONNECTION': 'sqlite', 'DB_DATABASE': str(root / 'database.sqlite'), 'DB_URL': '',
               'CACHE_STORE': 'database', 'SESSION_DRIVER': 'array', 'QUEUE_CONNECTION': 'sync',
               'FILESYSTEM_DISK': 'local', 'LOG_CHANNEL': 'single',
               'LARAVEL_STORAGE_PATH': str(root / 'storage'), 'STEP_SMOKE_DIR': str(root),
               'APP_CONFIG_CACHE': str(root / 'config.php'), 'APP_ROUTES_CACHE': str(root / 'routes.php'),
               'BROADCAST_CONNECTION': 'reverb', 'REVERB_HOST': '127.0.0.1', 'REVERB_SCHEME': 'http',
               'REVERB_PORT': str(reverb_port), 'REVERB_APP_ID': 'mobile-smoke',
               'REVERB_APP_KEY': secrets.token_hex(16), 'REVERB_APP_SECRET': secrets.token_hex(32),
               'REVERB_SCALING_ENABLED': 'false', 'MAIL_MAILER': 'array'}
        subprocess.run([args.php, str(backend / 'tests/Support/mobile_smoke_seed.php')], cwd=backend, env=env, check=True, timeout=60)
        processes = []
        with (root / 'servers.log').open('w+') as log:
            try:
                api = subprocess.Popen([args.php, '-S', f'127.0.0.1:{api_port}', '-t', str(backend / 'public'),
                                        str(backend / 'vendor/laravel/framework/src/Illuminate/Foundation/resources/server.php')],
                                       cwd=backend / 'public', env=env, stdout=log, stderr=log, start_new_session=True)
                processes.append(api)
                reverb = subprocess.Popen([args.php, 'artisan', 'reverb:start', '--host=127.0.0.1', f'--port={reverb_port}', '--no-interaction'],
                                          cwd=backend, env=env, stdout=log, stderr=log, start_new_session=True)
                processes.append(reverb)
                ready(api_port, api)
                ready(reverb_port, reverb)
                subprocess.run([args.dart, 'run', 'tool/backend_smoke.dart', str(root / 'fixture.json')], cwd=project, check=True, timeout=90)
                print('Integration check passed. Temporary users, tokens, files, and servers removed on exit.')
            except Exception:
                log.flush()
                log.seek(0)
                print(log.read()[-6000:])
                raise
            finally:
                for process in reversed(processes):
                    if process.poll() is None:
                        os.killpg(process.pid, signal.SIGTERM)
                        try:
                            process.wait(timeout=5)
                        except subprocess.TimeoutExpired:
                            os.killpg(process.pid, signal.SIGKILL)
                            process.wait()


if __name__ == '__main__':
    main()
