"""YASB true-portable patch, rev 1.4. Run only in the builder's throwaway checkout.

Source-aware, transactional edits: before touching the checkout, every supported
function is inspected and every output is generated in memory. If upstream
changes unexpectedly, the build stops with the exact file/function name.
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

PATCH_VERSION = "1.4"


class PatchError(RuntimeError):
    pass


def ensure(condition: bool, where: str, why: str):
    if not condition:
        raise PatchError(f"{where}: {why}")


def replace_one(text: str, old: str, new: str, where: str) -> str:
    if new in text:
        print(f"ALREADY PATCHED: {where}")
        return text
    count = text.count(old)
    ensure(count == 1, where, f"expected exactly one source anchor; found {count}")
    print(f"PATCH: {where}")
    return text.replace(old, new, 1)


def replace_function(text: str, name: str, indent: int, transform, where: str) -> str:
    """Replace a uniquely named single-line Python def by its indentation block."""
    lines = text.splitlines(keepends=True)
    head = re.compile(r"^" + " " * indent + r"def\s+" + re.escape(name) + r"\s*\(")
    starts = [i for i, line in enumerate(lines) if head.match(line)]
    ensure(len(starts) == 1, where, f"expected one def {name}(...), found {len(starts)}")
    start = starts[0]
    end = len(lines)
    for i in range(start + 1, len(lines)):
        line = lines[i]
        if not line.strip():
            continue
        leading = len(line) - len(line.lstrip(" "))
        if leading <= indent:
            end = i
            break
    block = "".join(lines[start:end])
    result = transform(block)
    ensure(result != "", where, "replacement was empty")
    print(f"PATCH: {where}")
    lines[start:end] = [result]
    return "".join(lines)


def patch_settings(text: str) -> str:
    where = "src/settings.py: portable config and temporary directories"
    old = 'SCRIPT_PATH = os.path.dirname(sys.executable) if IS_FROZEN else os.path.dirname(os.path.abspath(__file__))'
    new = '''SCRIPT_PATH = os.path.dirname(sys.executable) if IS_FROZEN else os.path.dirname(os.path.abspath(__file__))

# YASB_PORTABLE_PATHS_V1
PORTABLE_DATA_DIRECTORY = os.path.join(SCRIPT_PATH, "Data")
PORTABLE_CONFIG_DIRECTORY = os.path.join(PORTABLE_DATA_DIRECTORY, "Config")
PORTABLE_TEMP_DIRECTORY = os.path.join(PORTABLE_DATA_DIRECTORY, "Temp")

if IS_FROZEN:
    os.makedirs(PORTABLE_CONFIG_DIRECTORY, exist_ok=True)
    os.makedirs(PORTABLE_TEMP_DIRECTORY, exist_ok=True)
    os.environ["YASB_CONFIG_HOME"] = PORTABLE_CONFIG_DIRECTORY
    os.environ["TEMP"] = PORTABLE_TEMP_DIRECTORY
    os.environ["TMP"] = PORTABLE_TEMP_DIRECTORY
    import tempfile
    tempfile.tempdir = PORTABLE_TEMP_DIRECTORY'''
    text = replace_one(text, old, new, where)
    text = replace_one(
        text,
        'DEFAULT_CONFIG_DIRECTORY = os.getenv("YASB_CONFIG_HOME") or os.path.join(os.path.expanduser("~"), ".config", "yasb")',
        'DEFAULT_CONFIG_DIRECTORY = PORTABLE_CONFIG_DIRECTORY if IS_FROZEN else (os.getenv("YASB_CONFIG_HOME") or os.path.join(os.path.expanduser("~"), ".config", "yasb"))',
        'src/settings.py: frozen default config root',
    )
    return text


def patch_system(text: str) -> str:
    where = "src/core/utils/system.py: app_data_path"
    ensure(re.search(r"^import sys\s*$", text, flags=re.M), where, "sys import not found")

    def transform(block: str) -> str:
        old = '    folder = Path(os.environ["LOCALAPPDATA"]) / "YASB"'
        new = '''    folder = (
        Path(sys.executable).resolve().parent / "Data" / "LocalState"
        if getattr(sys, "frozen", False)
        else Path(os.environ["LOCALAPPDATA"]) / "YASB"
    )'''
        for invariant in ['folder.mkdir(parents=True, exist_ok=True)', 'if filename is not None:', 'return folder / filename', 'return folder']:
            ensure(invariant in block, where, f"expected storage behavior missing: {invariant}")
        return replace_one(block, old, new, where + " storage assignment")

    return replace_function(text, "app_data_path", 0, transform, where)


def patch_cloud(text: str) -> str:
    where = "src/core/cloud/session.py: cloud_dir"
    text = replace_one(
        text,
        'from core.cloud.errors import CloudError',
        'from core.cloud.errors import CloudError\nfrom core.utils.system import app_data_path',
        where + " import",
    )

    def transform(block: str) -> str:
        old = '    base = Path(os.environ.get("LOCALAPPDATA", Path.home() / "AppData" / "Local")) / "YASB" / CLOUD_DIR_NAME'
        new = '    base = app_data_path(CLOUD_DIR_NAME)'
        ensure('base.mkdir(parents=True, exist_ok=True)' in block and 'return base' in block,
               where, "expected mkdir/return behavior changed")
        return replace_one(block, old, new, where + " storage assignment")

    return replace_function(text, "cloud_dir", 0, transform, where)


def patch_update(text: str) -> str:
    where = "src/core/utils/update_service.py: UpdateService.is_update_supported"

    def transform(block: str) -> str:
        # Match function by name and validate only meaningful semantics.
        if '"""The portable build is updated only by its GitHub Actions builder."""' in block:
            return block
        for invariant in ('is_installed', 'get_app_identifier()', 'ARCHITECTURE is not None', 'RELEASE_CHANNEL.startswith("pr-")'):
            ensure(invariant in block, where, f"upstream update policy changed: missing {invariant}")
        return '''    def is_update_supported(self) -> bool:
        """The portable build is updated only by its GitHub Actions builder."""
        return False

'''

    # Replaces only the named method, independent of its docstring/formatting.
    return replace_function(text, "is_update_supported", 4, transform, where)


def patch_tray(text: str) -> str:
    return replace_one(
        text,
        'AUTOSTART_FILE = EXE_PATH if os.path.exists(EXE_PATH) else None',
        'AUTOSTART_FILE = None  # Portable build uses INSTALL-PORTABLE-STARTUP.cmd',
        'src/core/tray.py: autostart menu',
    )


def patch_win32(text: str) -> str:
    specs = [
        ("enable_autostart", 'winreg.SetValueEx', '''def enable_autostart(app_name: str, executable_path: str) -> bool:
    """Disable registry autostart in the portable build."""
    logging.warning("Portable YASB uses INSTALL-PORTABLE-STARTUP.cmd, not registry autostart.")
    return False

'''),
        ("disable_autostart", 'winreg.DeleteValue', '''def disable_autostart(app_name: str) -> bool:
    """Registry autostart is not used in the portable build."""
    return True

'''),
        ("is_autostart_enabled", 'winreg.QueryValueEx', '''def is_autostart_enabled(app_name: str) -> bool:
    """Registry autostart is intentionally disabled in the portable build."""
    return False

'''),
    ]
    for name, original_call, replacement in specs:
        where = f"src/core/utils/win32/utils.py: {name}"

        def transform(block: str, *, call=original_call, target=replacement, label=where) -> str:
            if block.startswith(target):
                return block
            ensure(call in block, label, f"registry implementation changed: {call} missing")
            return target

        text = replace_function(text, name, 0, transform, where)
    return text


def patch_cli(text: str) -> str:
    where = "src/cli.py: disable updater, startup and WER CLI actions"
    if 'The official MSI updater is disabled in the portable build.' in text:
        print(f"ALREADY PATCHED: {where}")
        return text
    start_anchor = '        elif args.command == "set-channel":\n'
    end_anchor = '        elif args.command == "log":\n'
    ensure(text.count(start_anchor) == 1 and text.count(end_anchor) == 1, where,
           "CLI command-dispatch anchors changed")
    start = text.index(start_anchor)
    end = text.index(end_anchor, start)
    old = text[start:end]
    for command in ("set-channel", "update", "enable-autostart", "disable-autostart", "enable-crash-dumps", "disable-crash-dumps"):
        ensure(old.count(f'elif args.command == "{command}"') == 1, where,
               f"command handler {command} changed")
    new = '''        elif args.command == "set-channel":
            print("Release-channel switching is disabled in the portable build.")
            print("Use your YASB-Portable-Builder GitHub workflow to update the application.")
            sys.exit(0)

        elif args.command == "update":
            print("The official MSI updater is disabled in the portable build.")
            print("Use your YASB-Portable-Builder GitHub workflow to update the application.")
            sys.exit(0)

        elif args.command == "enable-autostart":
            print("Built-in registry/Task Scheduler autostart is disabled in the portable build.")
            print("Run INSTALL-PORTABLE-STARTUP.cmd from the portable folder instead.")
            sys.exit(0)

        elif args.command == "disable-autostart":
            print("Run REMOVE-PORTABLE-STARTUP.cmd from the portable folder.")
            sys.exit(0)

        elif args.command == "enable-crash-dumps":
            print("WER registry crash-dump registration is disabled in the portable build.")
            sys.exit(0)

        elif args.command == "disable-crash-dumps":
            print("WER registry crash-dump registration is not used by the portable build.")
            sys.exit(0)

'''
    print(f"PATCH: {where}")
    return text[:start] + new + text[end:]


def patch_schedule(text: str) -> str:
    where = "src/core/cloud/schedule.py: create Scheduled Task"

    def transform(block: str) -> str:
        if 'Automatic YASB Cloud scheduled backup is disabled in the portable build.' in block:
            return block
        for invariant in ('_executable()', 'scheduler.NewTask', 'RegisterTaskDefinition'):
            ensure(invariant in block, where, f"cloud scheduler behavior changed: {invariant} missing")
        return '''def create() -> tuple[bool, str]:
    """The portable build must not register a persistent Scheduled Task."""
    return False, "Automatic YASB Cloud scheduled backup is disabled in the portable build."

'''

    return replace_function(text, "create", 0, transform, where)


PATCHERS = {
    "src/settings.py": patch_settings,
    "src/core/utils/system.py": patch_system,
    "src/core/cloud/session.py": patch_cloud,
    "src/core/utils/update_service.py": patch_update,
    "src/core/tray.py": patch_tray,
    "src/core/utils/win32/utils.py": patch_win32,
    "src/cli.py": patch_cli,
    "src/core/cloud/schedule.py": patch_schedule,
}


def run(root: Path, check_only: bool, skip_compile: bool) -> None:
    ensure((root / "src").is_dir(), str(root), "missing src/ directory")
    pending = {}
    for name, patcher in PATCHERS.items():
        path = root / name
        ensure(path.is_file(), name, "upstream file missing")
        source = path.read_text(encoding="utf-8-sig").replace("\r\n", "\n")
        transformed = patcher(source)
        if not skip_compile:
            try:
                # YASB currently requires Python 3.14. Earlier versions cannot
                # parse the upstream `except E1, E2:` syntax used by YASB.
                compile(transformed, name, "exec")
            except SyntaxError as exc:
                raise PatchError(f"{name}: patched file does not compile: {exc}") from exc
        pending[path] = transformed

    # Cross-file invariants: no originals were touched yet.
    ensure('base = app_data_path(CLOUD_DIR_NAME)' in pending[root / "src/core/cloud/session.py"],
           "cloud", "portable Cloud path missing")
    ensure('return False' in pending[root / "src/core/utils/update_service.py"],
           "update service", "portable update disable missing")
    print(f"ALL SOURCE TRANSFORMATIONS PASSED: {len(pending)} files")

    if check_only:
        print("PREFLIGHT ONLY: did not change any files")
        return

    for path, new in pending.items():
        path.write_text(new, encoding="utf-8", newline="\n")

    try:
        revision = subprocess.run(["git", "-C", str(root), "rev-parse", "HEAD"],
                                  stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, check=True).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        revision = "unavailable-in-local-preflight"

    marker = {
        "patch": "YASB true-portable", "patch_version": PATCH_VERSION,
        "upstream_revision": revision,
        "config_root": "./Data/Config", "local_state_root": "./Data/LocalState",
        "temp_root": "./Data/Temp", "built_in_msi_updater": False,
        "built_in_registry_autostart": False, "built_in_task_autostart": False,
        "wer_registry_crash_dump_setup": False,
        "cloud_scheduled_backup_task": False, "cloud_files_portable": True,
        "cloud_cached_login_machine_portable": False,
        "cloud_cached_login_note": "YASB Cloud Windows DPAPI sign-in requires reauthentication after clean Windows install.",
        "applied_at": datetime.now(timezone.utc).isoformat(),
    }
    (root / ".yasb-true-portable-patch.json").write_text(json.dumps(marker, indent=2), encoding="utf-8")
    print("YASB PORTABLE PATCH v1.4 APPLIED SUCCESSFULLY")


def main() -> int:
    parser = argparse.ArgumentParser(description="Patch YASB for portable Windows builds")
    parser.add_argument("--source-root", required=True)
    parser.add_argument("--check-only", action="store_true")
    parser.add_argument("--skip-compile", action="store_true", help="Local review on Python older than YASB 3.14 requirement")
    args = parser.parse_args()
    try:
        run(Path(args.source_root).resolve(), args.check_only, args.skip_compile)
        return 0
    except (PatchError, OSError) as exc:
        print(f"PORTABLE PATCH FAILURE: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
