"""Ephemeral loopback certificates. Never installs keys or changes system trust."""
from datetime import datetime, timedelta, timezone
import ssl
import subprocess


def make_context(directory, certificate):
    def openssl(*arguments):
        subprocess.run(['/usr/bin/openssl', *map(str, arguments)], check=True,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    openssl('req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-keyout', directory / 'ca.key',
            '-out', directory / 'ca.pem', '-days', 2, '-subj', '/CN=MailSearch Loopback Fixture CA',
            '-addext', 'basicConstraints=critical,CA:TRUE')
    openssl('x509', '-in', directory / 'ca.pem', '-outform', 'DER', '-out', directory / 'root.der')
    openssl('req', '-new', '-newkey', 'rsa:2048', '-nodes', '-keyout', directory / 'server.key',
            '-out', directory / 'server.csr', '-subj', '/CN=localhost')
    (directory / 'index').touch()
    (directory / 'serial').write_text('01\n')
    (directory / 'ca.cnf').write_text(f'''[ca]
default_ca=fixture
[fixture]
database={directory}/index
serial={directory}/serial
new_certs_dir={directory}
certificate={directory}/ca.pem
private_key={directory}/ca.key
default_md=sha256
policy=policy
[policy]
commonName=supplied
''')
    hostname = 'wrong.example.test' if certificate == 'wrong-host' else 'localhost'
    (directory / 'extensions').write_text(
        'basicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature,keyEncipherment\n'
        f'extendedKeyUsage=serverAuth\nsubjectAltName=DNS:{hostname}\n')
    now = datetime.now(timezone.utc)
    start = '20200101000000Z' if certificate == 'expired' else (now - timedelta(minutes=1)).strftime('%Y%m%d%H%M%SZ')
    end = '20200102000000Z' if certificate == 'expired' else (now + timedelta(days=1)).strftime('%Y%m%d%H%M%SZ')
    openssl('ca', '-batch', '-config', directory / 'ca.cnf', '-in', directory / 'server.csr',
            '-out', directory / 'server.pem', '-startdate', start, '-enddate', end,
            '-extfile', directory / 'extensions', '-notext')
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.minimum_version = ssl.TLSVersion.TLSv1_2
    context.load_cert_chain(directory / 'server.pem', directory / 'server.key')
    return context
