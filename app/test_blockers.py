#!/usr/bin/env python3
"""Compile and run the Swift regression suite against the app sources."""
from pathlib import Path
import shutil
import subprocess
import tempfile


app = Path(__file__).resolve().parent
sources = sorted((app / "Sources").rglob("*.swift"))
tests = sorted((app / "Tests").rglob("*.swift"))

with tempfile.TemporaryDirectory(prefix="gitlab-blocker-tests-") as temp:
    binary = Path(temp) / Path(temp).name
    shutil.copytree(app / "Resources" / "en.lproj", Path(temp) / "en.lproj")
    subprocess.run([
        "xcrun", "swiftc", *map(str, sources + tests), "-o", str(binary),
        "-module-cache-path", "/tmp/gitlab-widget-swift-cache",
        "-framework", "AppKit", "-framework", "SwiftUI",
        "-framework", "ServiceManagement", "-framework", "Security",
    ], check=True)
    subprocess.run([str(binary)], check=True)
