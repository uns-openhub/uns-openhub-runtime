#!/usr/bin/env python3
"""Preview/apply one narrowly reviewed persistent SELinux storage context.

No Unix permission changes, process control, file-body reads or recursive repairs.
Apply uses semanage and fd-bound label writes to the exact reviewed inodes. The
same saved plan can reconcile an interrupted apply. New files need a fresh plan
or the owning writer's restorecon step; an fcontext rule is not a background job.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess

CONTEXT = "system_u:object_r:container_file_t:s0"
LIMIT = 2048


def canonical(value):
    return (json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n").encode()


def command(args):
    # Do not print raw policy/daemon output on failure.
    p = subprocess.run(args, capture_output=True, timeout=45,
                       env={**os.environ, "LC_ALL": "C"})
    if p.returncode or len(p.stdout) > 2 * 1024 * 1024:
        raise RuntimeError("SELinux management command failed; no process or Unix permission was changed")
    return p.stdout.decode()


def tools():
    for name in ("semanage", "matchpathcon", "getenforce"):
        if not shutil.which(name):
            raise RuntimeError("Missing standard SELinux tool: " + name)
    if command(["getenforce"]).strip() != "Enforcing":
        raise RuntimeError("This procedure requires SELinux Enforcing; do not change enforcement to pass it")


def open_root(value):
    if not re.fullmatch(r"/[A-Za-z0-9_./-]+", value) or str(Path(value)) != value or ".." in Path(value).parts or len(Path(value).parts) < 5:
        raise RuntimeError("Choose one normalized narrow physical storage root")
    fd = os.open("/", os.O_RDONLY | os.O_DIRECTORY)
    try:
        for part in Path(value).parts[1:]:
            nxt = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
            os.close(fd)
            fd = nxt
        return fd
    except BaseException:
        os.close(fd)
        raise


def metadata(fd):
    s = os.fstat(fd)
    if not (stat.S_ISDIR(s.st_mode) or stat.S_ISREG(s.st_mode)) or (stat.S_ISREG(s.st_mode) and s.st_nlink != 1):
        raise RuntimeError("Only directories and unlinked regular files may be labelled")
    return {"device": s.st_dev, "inode": s.st_ino, "uid": s.st_uid, "gid": s.st_gid,
            "mode": stat.S_IMODE(s.st_mode), "size": s.st_size, "mtimeNs": s.st_mtime_ns,
            "directory": stat.S_ISDIR(s.st_mode)}


def snapshot(rootfd):
    result = []
    device = os.fstat(rootfd).st_dev

    def visit(fd, relative, depth):
        if len(result) >= LIMIT or depth > 8:
            raise RuntimeError("Storage tree exceeds the bounded label review; nothing was applied")
        item = metadata(fd)
        if item["device"] != device:
            raise RuntimeError("Nested filesystems require separate label reviews")
        item.update({"relative": relative, "context": os.getxattr(fd, "security.selinux").rstrip(b"\0").decode()})
        result.append(item)
        if item["directory"]:
            names = []
            with os.scandir(fd) as entries:
                for entry in entries:
                    names.append(entry.name)
                    if len(names) > LIMIT:
                        raise RuntimeError("Storage directory exceeds label review bound")
            for name in sorted(names):
                child = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=fd)
                try:
                    visit(child, name if relative == "." else relative + "/" + name, depth + 1)
                finally:
                    os.close(child)
    visit(rootfd, ".", 0)
    return result


def local_rules():
    rules = []
    for line in command(["semanage", "fcontext", "-l", "-C"]).splitlines():
        parts = line.split()
        if len(parts) >= 3 and re.fullmatch(r"[^: ]+:[^: ]+:[^: ]+:[^ ]+", parts[-1]):
            rules.append({"expression": parts[0], "kind": " ".join(parts[1:-1]), "context": parts[-1]})
    return sorted(rules, key=lambda x: (x["expression"], x["kind"], x["context"]))


def validate_rule(rules, expression):
    exact = [r for r in rules if r["expression"] == expression]
    if exact and exact != [{"expression": expression, "kind": "all files", "context": CONTEXT}]:
        raise RuntimeError("An existing rule for this exact root differs; do not overwrite it")
    return bool(exact)


def plan(root):
    tools()
    fd = open_root(root)
    try:
        entries = snapshot(fd)
    finally:
        os.close(fd)
    expression = re.escape(root) + "(/.*)?"
    rules = local_rules()
    validate_rule(rules, expression)
    return {"schemaVersion": 1, "root": root, "expression": expression, "context": CONTEXT,
            "entries": entries, "otherLocalRules": [r for r in rules if r["expression"] != expression]}


def without_context(entries):
    return [{k: v for k, v in item.items() if k != "context"} for item in entries]


def apply(review):
    tools()
    if os.geteuid() != 0:
        raise RuntimeError("The storage owner must apply this reviewed policy with root privileges")
    if review.get("schemaVersion") != 1 or review.get("context") != CONTEXT or review.get("expression") != re.escape(review["root"]) + "(/.*)?":
        raise RuntimeError("Invalid storage label review")
    rootfd = open_root(review["root"])
    try:
        current = snapshot(rootfd)
        if without_context(current) != without_context(review["entries"]):
            raise RuntimeError("Storage changed after review; create a fresh bounded plan")
        old = {r["relative"]: r["context"] for r in review["entries"]}
        if any(r["context"] not in (old[r["relative"]], CONTEXT) for r in current):
            raise RuntimeError("A file label changed outside this operation")
        rules = local_rules()
        exists = validate_rule(rules, review["expression"])
        if [r for r in rules if r["expression"] != review["expression"]] != review["otherLocalRules"]:
            raise RuntimeError("SELinux local policy changed after review")
        if not exists:
            command(["semanage", "fcontext", "-N", "-a", "-t", "container_file_t", "-r", "s0", review["expression"]])
        for item in review["entries"]:
            root_check = open_root(review["root"])
            try:
                if os.fstat(root_check).st_ino != os.fstat(rootfd).st_ino:
                    raise RuntimeError("Storage root moved during apply")
            finally:
                os.close(root_check)
            fd = os.dup(rootfd)
            try:
                if item["relative"] != ".":
                    for component in item["relative"].split("/"):
                        if component in ("", ".", ".."):
                            raise RuntimeError("Invalid reviewed relative path")
                        child = os.open(component, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=fd)
                        os.close(fd)
                        fd = child
                if metadata(fd) != {k: v for k, v in item.items() if k not in ("relative", "context")}:
                    raise RuntimeError("A reviewed inode changed during apply")
                os.setxattr(fd, "security.selinux", CONTEXT.encode() + b"\0")
            finally:
                os.close(fd)
        after = snapshot(rootfd)
        if without_context(after) != without_context(review["entries"]) or any(r["context"] != CONTEXT for r in after):
            raise RuntimeError("Partial label outcome: retain the same plan and reconcile, never restart to bypass it")
        if command(["matchpathcon", "-n", review["root"] + "/future-archive"]).strip() != CONTEXT:
            raise RuntimeError("Persistent policy lookup disagrees with the reviewed label")
        return {"status": "applied", "entries": len(after), "context": CONTEXT,
                "unixPermissionsChanged": False, "processesRestarted": False,
                "newFilesRequireOwnerRestorecon": True}
    finally:
        os.close(rootfd)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    sub = p.add_subparsers(dest="action", required=True)
    create = sub.add_parser("plan")
    create.add_argument("--root", required=True)
    create.add_argument("--output", required=True)
    execute = sub.add_parser("apply")
    execute.add_argument("--plan", required=True)
    execute.add_argument("--sha256", required=True)
    args = p.parse_args()
    if args.action == "plan":
        data = canonical(plan(args.root))
        fd = os.open(args.output, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
        with os.fdopen(fd, "wb") as out:
            out.write(data)
            out.flush()
            os.fsync(out.fileno())
        print(json.dumps({"status": "review", "sha256": hashlib.sha256(data).hexdigest(), "policyChanged": False}))
    else:
        fd = os.open(args.plan, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
        with os.fdopen(fd, "rb") as source:
            info = os.fstat(source.fileno())
            if not stat.S_ISREG(info.st_mode) or stat.S_IMODE(info.st_mode) & 0o077:
                raise RuntimeError("Review must be a private regular file")
            data = source.read(4 * 1024 * 1024 + 1)
        if len(data) > 4 * 1024 * 1024 or hashlib.sha256(data).hexdigest() != args.sha256:
            raise RuntimeError("Review checksum differs")
        print(json.dumps(apply(json.loads(data))))


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        raise SystemExit(str(error))
