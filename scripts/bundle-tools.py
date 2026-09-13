#!/usr/bin/env python3
"""Bundle local Homebrew media tools and their non-system Mach-O dependencies."""
import hashlib
import json
import pathlib
import shutil
import subprocess
import sys


def run(*args: str) -> str:
    return subprocess.check_output(args, text=True).strip()


def main() -> None:
    app = pathlib.Path(sys.argv[1]).resolve()
    tools = app / "Contents" / "Helpers"
    libraries = app / "Contents" / "Frameworks"
    resources = app / "Contents" / "Resources"
    for directory in (tools, libraries, resources):
        directory.mkdir(parents=True, exist_ok=True)
    copied = {}
    provenance = []

    def copy_binary(original: pathlib.Path, executable: bool = False) -> pathlib.Path:
        original = original.resolve(strict=True)
        if original in copied:
            return copied[original]
        destination = (tools if executable else libraries) / original.name
        if destination.exists():
            raise RuntimeError(f"Conflicting library basename: {destination}")
        shutil.copy2(original, destination)
        destination.chmod(0o755)
        copied[original] = destination
        provenance.append({"source": str(original), "bundled": str(destination.relative_to(app)),
                           "source_sha256": hashlib.sha256(original.read_bytes()).hexdigest()})
        dependencies = run("otool", "-L", str(original)).splitlines()[1:]
        for line in dependencies:
            dependency = line.strip().split(" (compatibility")[0]
            if dependency.startswith(("/usr/lib/", "/System/Library/")):
                continue
            if dependency.startswith("@loader_path/"):
                resolved = original.parent / dependency.removeprefix("@loader_path/")
            elif dependency.startswith("@rpath/"):
                suffix = dependency.removeprefix("@rpath/")
                candidates = [original.parent / suffix, pathlib.Path("/opt/homebrew/lib") / suffix]
                resolved = next((p for p in candidates if p.exists()), None)
                if resolved is None:
                    raise RuntimeError(f"Cannot resolve {dependency} in {original}")
            else:
                resolved = pathlib.Path(dependency)
            if resolved.resolve() == original:
                continue
            bundled = copy_binary(resolved)
            replacement = ("@executable_path/../Frameworks/" if executable else "@loader_path/") + bundled.name
            subprocess.run(["install_name_tool", "-change", dependency, replacement, str(destination)], check=True)
        if not executable:
            subprocess.run(["install_name_tool", "-id", "@rpath/" + destination.name, str(destination)], check=True)
        subprocess.run(["codesign", "--force", "--sign", "-", str(destination)], check=True)
        return destination

    versions = {}
    for name in ("ffmpeg", "ffprobe"):
        source = pathlib.Path("/opt/homebrew/bin") / name
        copy_binary(source, executable=True)
        versions[name] = run(str(source), "-version")
    for destination in copied.values():
        for line in run("otool", "-L", str(destination)).splitlines()[1:]:
            dependency = line.strip().split(" (compatibility")[0]
            if dependency.startswith("/") and not dependency.startswith(("/usr/lib/", "/System/Library/")):
                raise RuntimeError(f"Unbundled dependency {dependency} in {destination}")
    (resources / "MediaTools-Provenance.json").write_text(json.dumps({"tools": versions, "files": provenance}, indent=2) + "\n")
    notices = resources / "ThirdPartyLicenses"
    notices.mkdir()
    for original in copied:
        parts = original.parts
        if "Cellar" in parts:
            index = parts.index("Cellar")
            root = pathlib.Path(*parts[:index + 3])
            for pattern in ("COPYING*", "LICENSE*", "COPYRIGHT*", "AUTHORS*"):
                for notice in root.glob(pattern):
                    if notice.is_file():
                        destination = notices / (parts[index + 1] + "-" + notice.name)
                        if not destination.exists():
                            shutil.copy2(notice, destination)
    (resources / "THIRD-PARTY-NOTICE.txt").write_text(
        "This local development build bundles the installed Homebrew FFmpeg tools and their dependencies.\n"
        "See MediaTools-Provenance.json for exact source paths, checksums, versions, and build configuration,\n"
        "and ThirdPartyLicenses for license files available in the installed formulae.\n"
        "This installed FFmpeg build is GPL-enabled and includes libx264; see its recorded build configuration.\n"
        "This bundle is ad-hoc signed for local testing, not notarized or prepared for redistribution.\n"
        "Before redistribution, audit every bundled dependency and fulfill its license and corresponding-source obligations.\n")


if __name__ == "__main__":
    main()
