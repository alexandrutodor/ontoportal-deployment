#!/usr/bin/env python3
"""Fetch a Git image source into the path expected by image-build-matrix.py."""
from __future__ import annotations

import argparse
import base64
import os
import pathlib
import re
import shutil
import subprocess
from urllib.parse import urlparse

ROOT = pathlib.Path(__file__).resolve().parents[1]


def inside_repo(path: pathlib.Path) -> pathlib.Path:
    resolved = path.resolve()
    try:
        resolved.relative_to(ROOT)
    except ValueError as exc:
        raise SystemExit(f"destination must stay inside the repository: {path}") from exc
    return resolved


def git_host(url: str) -> str:
    parsed = urlparse(url)
    if parsed.scheme in {"https", "http", "ssh", "git+ssh"} and parsed.hostname:
        return parsed.hostname
    match = re.match(r"^(?:[^@/]+@)?([^:/]+):.+$", url)
    if match:
        return match.group(1)
    raise SystemExit("Git URL must be http(s), ssh, or scp-like git syntax")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", required=True)
    parser.add_argument("--ref", required=True)
    parser.add_argument("--dest", required=True, type=pathlib.Path)
    args = parser.parse_args()

    host = git_host(args.url)
    parsed = urlparse(args.url)

    dest = inside_repo(ROOT / args.dest)
    if dest.exists():
        shutil.rmtree(dest)
    dest.parent.mkdir(parents=True, exist_ok=True)
    command = ["git"]
    token = os.environ.get("SOURCE_GIT_TOKEN", "")
    if token and host == "github.com" and parsed.scheme in {"https", "http"}:
        header = base64.b64encode(f"x-access-token:{token}".encode("utf-8")).decode("ascii")
        command.extend(["-c", f"http.https://github.com/.extraheader=AUTHORIZATION: basic {header}"])
    clone_with_ref = command + ["clone", "--depth", "1", "--branch", args.ref, args.url, str(dest)]
    try:
        subprocess.run(clone_with_ref, check=True)
    except subprocess.CalledProcessError:
        if dest.exists():
            shutil.rmtree(dest)
        clone_default = command + ["clone", "--depth", "1", args.url, str(dest)]
        subprocess.run(clone_default, check=True)
        subprocess.run(["git", "-C", str(dest), "fetch", "--depth", "1", "origin", args.ref], check=True)
        subprocess.run(["git", "-C", str(dest), "checkout", "--detach", "FETCH_HEAD"], check=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
