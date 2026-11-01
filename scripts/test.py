"""Run controller checks without changing the actual VPN state."""
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parent.parent
BUILD = ROOT / 'build'
BUILD.mkdir(exist_ok=True)
binary = BUILD / 'controller-tests'
subprocess.run([
    'xcrun', 'swiftc', '-parse-as-library', '-swift-version', '5', '-O',
    str(ROOT / 'Sources' / 'Controller.swift'),
    str(ROOT / 'Tests' / 'ControllerTests.swift'), '-o', str(binary),
], check=True)
subprocess.run([str(binary)], check=True)
