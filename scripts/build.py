"""Build the standalone macOS menu bar app and a distributable ZIP."""
from pathlib import Path
import plistlib
import shutil
import subprocess

ROOT = Path(__file__).resolve().parent.parent
BUILD = ROOT / 'build'
DIST = ROOT / 'dist'
BUILD.mkdir(exist_ok=True)
DIST.mkdir(exist_ok=True)
app = DIST / 'OU VPN.app'
if app.exists():
    shutil.rmtree(app)
macos = app / 'Contents' / 'MacOS'
resources = app / 'Contents' / 'Resources'
macos.mkdir(parents=True)
resources.mkdir(parents=True)
binaries = []
for arch in ['arm64', 'x86_64']:
    binary = BUILD / f'OUVPN-{arch}'
    subprocess.run([
        'xcrun', 'swiftc', '-parse-as-library', '-swift-version', '5', '-O',
        '-framework', 'AppKit', '-target', f'{arch}-apple-macos13.0',
        str(ROOT / 'Sources' / 'Controller.swift'),
        str(ROOT / 'Sources' / 'Main.swift'), '-o', str(binary),
    ], check=True)
    binaries.append(binary)
executable = macos / 'OUVPN'
subprocess.run(['lipo', '-create', *map(str, binaries), '-output', str(executable)], check=True)
executable.chmod(0o755)
for name in ['AppIcon.icns', 'OUMonogram.png']:
    shutil.copyfile(ROOT / 'Assets' / name, resources / name)
shutil.copyfile(ROOT / 'Assets' / 'SOURCE.txt', resources / 'OU Logo Source.txt')
info = {
    'CFBundleExecutable': 'OUVPN',
    'CFBundleIdentifier': 'local.ou-vpn.menubar',
    'CFBundleName': 'OU VPN',
    'CFBundleDisplayName': 'OU VPN',
    'CFBundlePackageType': 'APPL',
    'CFBundleShortVersionString': '2.1',
    'CFBundleVersion': '3',
    'CFBundleIconFile': 'AppIcon',
    'LSMinimumSystemVersion': '13.0',
    'LSUIElement': True,
    'NSHighResolutionCapable': True,
    'NSPrincipalClass': 'NSApplication',
}
with (app / 'Contents' / 'Info.plist').open('wb') as file:
    plistlib.dump(info, file)
(app / 'Contents' / 'PkgInfo').write_bytes(b'APPL????')
subprocess.run(['codesign', '--force', '--sign', '-', str(app)], check=True)
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
archive = DIST / 'GlobalProtect-Toggle-macOS.zip'
if archive.exists():
    archive.unlink()
subprocess.run(['ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', str(app), str(archive)], check=True)
print(archive)
