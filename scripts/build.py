#!/usr/bin/env python3
"""Build a relocatable, native plugin marketplace for this machine."""
import hashlib
import json
import platform
import re
import shutil
import subprocess
import tarfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def run(*args, cwd=ROOT):
    subprocess.run(args, cwd=cwd, check=True)

def main():
    system = {"Darwin": "macos", "Linux": "linux"}.get(platform.system())
    arch = {"arm64": "arm64", "aarch64": "arm64", "x86_64": "x64", "AMD64": "x64"}.get(platform.machine())
    if (system, arch) not in [("macos", "arm64"), ("linux", "x64")]:
        raise SystemExit("This experiment packages macOS arm64 and Linux x64 only.")
    manifest = json.loads((ROOT / "plugin/plugin.json").read_text())
    server_version = re.search(r"^version: (.+)$", (ROOT / "server/pubspec.yaml").read_text(), re.M).group(1).strip()
    if server_version != manifest["version"]:
        raise SystemExit("Server and plugin versions must match.")
    name = f'todo-agent-app-{manifest["version"]}-{system}-{arch}'
    destination = ROOT / "dist" / name
    if destination.exists():
        shutil.rmtree(destination)
    plugin = destination / "plugins/todo-agent-app"
    plugin.parent.mkdir(parents=True, exist_ok=True)
    run("npm", "ci", cwd=ROOT / "web")
    run("npm", "run", "build", cwd=ROOT / "web")
    run("dart", "pub", "get", cwd=ROOT / "server")
    run("dart", "build", "cli", "--target", "bin/todo_agent_app.dart", "--output", str(ROOT / "build/native"), cwd=ROOT / "server")
    shutil.copytree(ROOT / "plugin", plugin)
    shutil.copytree(ROOT / "build/native/bundle", plugin, dirs_exist_ok=True)
    shutil.copytree(ROOT / "web/dist", plugin / "web")
    shutil.copy2(ROOT / "README.md", destination / "README.md")
    catalog = destination / ".agents/plugins/marketplace.json"
    catalog.parent.mkdir(parents=True)
    catalog.write_text(json.dumps({
        "name": "todo-agent-app-lab",
        "interface": {"displayName": "To Do Agent App Lab"},
        "plugins": [{"name": "todo-agent-app", "source": {"source": "local", "path": "./plugins/todo-agent-app"}, "policy": {"installation": "AVAILABLE", "authentication": "ON_INSTALL"}, "category": "Productivity"}]
    }, indent=2) + "\n")
    archive = ROOT / "dist" / f"{name}.tar.gz"
    with tarfile.open(archive, "w:gz") as tar:
        tar.add(destination, arcname=name)
    checksum = hashlib.sha256(archive.read_bytes()).hexdigest()
    archive.with_suffix(archive.suffix + ".sha256").write_text(f"{checksum}  {archive.name}\n")
    print(f"Marketplace: {destination}\nArchive: {archive}")

if __name__ == "__main__":
    main()
