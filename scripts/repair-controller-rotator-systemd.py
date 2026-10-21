#!/usr/bin/env python3
"""Remove only the rotator's stop coupling from locally managed Runtime units.

Dry-run unless --apply is supplied. Reloads configuration, never restarts services.
Existing mount dependencies and every [Service] directive remain untouched.
"""
import argparse
import datetime
import json
import os
from pathlib import Path
import re
import shlex
import stat
import subprocess
import tempfile

HARD = ("Requires", "Requisite", "BindsTo", "PartOf", "StopPropagatedFrom")
PROPERTIES = (*HARD, "Conflicts", "Wants", "After", "FragmentPath", "DropInPaths")


def detach(text, rotator):
    """Preserve unrelated directives, including existing list resets."""
    section = ""
    result = []
    lines = iter(text.splitlines(keepends=True))
    for line in lines:
        physical = [line]
        logical = line
        while logical.rstrip().endswith("\\"):
            following = next(lines, "")
            physical.append(following)
            logical = logical.rstrip()[:-1] + " " + following
        stripped = logical.strip()
        if stripped.startswith("[") and stripped.endswith("]"):
            section = stripped
        match = re.match(r"\s*([A-Za-z]+)\s*=(.*)", logical, re.S)
        if section == "[Unit]" and match and match[1] in HARD:
            tokens = match[2].split()
            if rotator in tokens:
                kept = [token for token in tokens if token != rotator]
                # Do not introduce an empty assignment: it would reset other
                # dependencies accumulated from earlier lines or drop-ins.
                if kept:
                    result.append(f"{match[1]}={' '.join(kept)}\n")
                continue
        result.extend(physical)
    return "".join(result)


def unit_name(value):
    if not re.fullmatch(r"[A-Za-z0-9_.@:-]+\.service", value):
        raise argparse.ArgumentTypeError("expected a concrete .service unit name")
    return value


def show(command, unit):
    output = subprocess.run([*command, "show", unit, "--no-pager",
                             *[f"--property={p}" for p in PROPERTIES]],
                            check=True, capture_output=True, text=True).stdout
    return dict(line.split("=", 1) for line in output.splitlines() if "=" in line)


def hard_edges(properties, rotator):
    return [key for key in (*HARD, "Conflicts") if rotator in properties.get(key, "").split()]


def write_atomic(path, data, original_stat=None):
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(prefix=".rotator-repair-", dir=path.parent)
    try:
        with os.fdopen(descriptor, "wb") as output:
            output.write(data)
            output.flush()
            os.fsync(output.fileno())
            if original_stat is not None:
                os.fchown(output.fileno(), original_stat.st_uid, original_stat.st_gid)
                os.fchmod(output.fileno(), stat.S_IMODE(original_stat.st_mode))
            else:
                os.fchmod(output.fileno(), 0o644)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def repair(command, unit, rotator, root, apply=False):
    if unit == rotator:
        raise RuntimeError("Runtime and rotator must be different units")
    before = show(command, unit)
    fragment = before.get("FragmentPath", "")
    if not fragment:
        raise RuntimeError("Runtime unit is not installed")
    root = root.resolve()
    files = [Path(fragment), *map(Path, shlex.split(before.get("DropInPaths", "")))]
    changes = {}
    for path in files:
        data = path.read_bytes()
        new = detach(data.decode(), rotator).encode()
        if new != data:
            if root not in path.parents or path.is_symlink() or path.resolve() != path:
                raise RuntimeError(f"refusing to modify a non-local or symlinked unit file: {path}")
            changes[path] = (data, new, path.stat())
    # The repair is deliberately limited to forward hard dependencies. A
    # Conflicts= edge or a reverse dependency/symlink requires separate review.
    if "Conflicts" in hard_edges(before, rotator):
        raise RuntimeError("Runtime conflicts with rotator; review that relationship separately")
    for key in HARD:
        if rotator in before.get(key, "").split() and not any(
                rotator in Path(path).read_text() for path in changes):
            raise RuntimeError(f"{key} is not declared in editable local unit files")
    dropin = root / f"{unit}.d" / "90-openhub-rotator-independent.conf"
    if dropin.is_symlink() or dropin.parent.is_symlink():
        raise RuntimeError("refusing a symlinked repair drop-in")
    content = ("# Rotator availability must not stop the Runtime or RTT workloads.\n"
               f"[Unit]\nWants={rotator}\nAfter={rotator}\n").encode()
    old = dropin.read_bytes() if dropin.exists() else None
    if old != content:
        if old is not None:
            raise RuntimeError("repair drop-in already exists with unexpected content")
        changes[dropin] = (None, content, None)
    plan = {"unit": unit, "rotator": rotator, "apply": apply,
            "files": [str(path) for path in changes], "hardDependenciesBefore": hard_edges(before, rotator),
            "servicesRestarted": False}
    if not changes:
        if hard_edges(before, rotator) or any(rotator not in before.get(key, "").split() for key in ("Wants", "After")):
            raise RuntimeError("effective dependencies did not match the reviewed repair")
        return plan
    if not apply:
        return plan
    backup = root / ".openhub-unit-backups" / datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    if backup.parent.is_symlink():
        raise RuntimeError("refusing a symlinked unit backup directory")
    backup.mkdir(parents=True, mode=0o700)
    backup.parent.chmod(0o700)
    for index, (path, (data, _, _)) in enumerate(changes.items()):
        if data is not None:
            destination = backup / f"{index}-{path.name}"
            destination.write_bytes(data)
            destination.chmod(0o600)
    changed = []
    try:
        for path, (_, data, metadata) in changes.items():
            write_atomic(path, data, metadata)
            changed.append(path)
        subprocess.run([*command, "daemon-reload"], check=True, capture_output=True)
        after = show(command, unit)
        if hard_edges(after, rotator) or any(rotator not in after.get(key, "").split() for key in ("Wants", "After")):
            raise RuntimeError("effective dependencies did not match the reviewed repair")
        for key in HARD:
            if set(before.get(key, "").split()) - {rotator} != set(after.get(key, "").split()):
                raise RuntimeError(f"unrelated {key} dependencies changed")
    except Exception:
        for path in reversed(changed):
            data, _, metadata = changes[path]
            if data is None:
                path.unlink()
            else:
                write_atomic(path, data, metadata)
        subprocess.run([*command, "daemon-reload"], check=True, capture_output=True)
        raise
    plan["backup"] = str(backup)
    plan["hardDependenciesAfter"] = hard_edges(after, rotator)
    return plan


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--unit", type=unit_name, default="uns-controller-podman.service")
    parser.add_argument("--rotator", type=unit_name, default="infisical-rotator.service")
    parser.add_argument("--user", action="store_true", help="repair this user's systemd units (local testing)")
    parser.add_argument("--apply", action="store_true", help="write reviewed repair and daemon-reload only")
    args = parser.parse_args()
    command = ["systemctl", *(["--user"] if args.user else [])]
    root = Path(os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config"))) / "systemd/user" if args.user else Path("/etc/systemd/system")
    try:
        print(json.dumps(repair(command, args.unit, args.rotator, root, args.apply), indent=2))
    except (RuntimeError, OSError, subprocess.CalledProcessError) as error:
        # Never print command output or unit contents (Environment may be secret).
        parser.exit(1, f"Repair failed: {error.__class__.__name__}: {error}\n")


if __name__ == "__main__":
    main()
