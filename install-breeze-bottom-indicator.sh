#!/usr/bin/env bash
# install-breeze-bottom-indicator.sh
# Install, apply, or uninstall the Breeze Bottom Indicator KDE Plasma desktop theme.
#
# Defaults to a per-user install:
#   ~/.local/share/plasma/desktoptheme/breeze-bottom-indicator
#
# The script can install from either:
#   1. The extracted theme directory containing metadata.json and plasmarc
#   2. breeze-bottom-indicator.tar.gz placed next to this script
#   3. A tarball passed with --archive /path/to/file.tar.gz

set -Eeuo pipefail
IFS=$'\n\t'

readonly THEME_ID="breeze-bottom-indicator"
readonly THEME_NAME="Breeze Bottom Indicator"
readonly ARCHIVE_BASENAME="breeze-bottom-indicator.tar.gz"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR

mode="user"
prefix=""
source_dir=""
archive_path=""
do_install=1
do_apply=0
do_reload=1
do_cache_clean=1
dry_run=0
work_dir=""

if [[ -t 2 ]]; then
  c_red=$'\e[31m'
  c_yel=$'\e[33m'
  c_grn=$'\e[32m'
  c_dim=$'\e[2m'
  c_off=$'\e[0m'
else
  c_red=""
  c_yel=""
  c_grn=""
  c_dim=""
  c_off=""
fi

info() { printf '%s==>%s %s\n' "$c_grn" "$c_off" "$*" >&2; }
warn() { printf '%swarn:%s %s\n' "$c_yel" "$c_off" "$*" >&2; }
err()  { printf '%serror:%s %s\n' "$c_red" "$c_off" "$*" >&2; }
die()  { err "$*"; exit 1; }

cleanup() {
  if [[ -n "$work_dir" && -d "$work_dir" ]]; then
    rm -rf -- "$work_dir"
  fi
}
trap cleanup EXIT

run() {
  if (( dry_run )); then
    printf '%s$' "$c_dim"
    printf ' %q' "$@"
    printf '%s\n' "$c_off"
  else
    "$@"
  fi
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

usage() {
  cat <<EOF_USAGE
Install the "$THEME_NAME" Plasma desktop theme.

Usage:
  $(basename "$0") [options]

Source options:
  --archive FILE       Install from a .tar.gz archive
  --source DIR         Install from an extracted theme directory

Install target:
  --user               Install for the current user, default
  --system             Install system-wide to /usr/share, uses sudo if needed
  --prefix DIR         Install under DIR/share/plasma/desktoptheme

Actions:
  --uninstall          Remove the installed theme instead of installing
  --apply              Set this as the active Plasma desktop theme after install
  --no-reload          Do not restart plasmashell
  --no-cache-clean     Do not remove this theme's Plasma cache files

Other:
  -n, --dry-run        Print actions without changing files
  -h, --help           Show this help

Examples:
  $(basename "$0") --archive ./breeze-bottom-indicator.tar.gz --apply
  $(basename "$0") --source ./breeze-bottom-indicator --apply
  $(basename "$0") --system --archive ./breeze-bottom-indicator.tar.gz
  $(basename "$0") --uninstall
EOF_USAGE
}

# Parse arguments.
while (($#)); do
  case "$1" in
    --archive)
      (($# >= 2)) || die "--archive needs a file path"
      archive_path="$2"
      shift 2
      ;;
    --archive=*)
      archive_path="${1#--archive=}"
      shift
      ;;
    --source)
      (($# >= 2)) || die "--source needs a directory path"
      source_dir="$2"
      shift 2
      ;;
    --source=*)
      source_dir="${1#--source=}"
      shift
      ;;
    --user)
      mode="user"
      shift
      ;;
    --system)
      mode="system"
      shift
      ;;
    --prefix)
      (($# >= 2)) || die "--prefix needs a directory path"
      mode="prefix"
      prefix="$2"
      shift 2
      ;;
    --prefix=*)
      mode="prefix"
      prefix="${1#--prefix=}"
      shift
      ;;
    --uninstall)
      do_install=0
      shift
      ;;
    --apply)
      do_apply=1
      shift
      ;;
    --no-reload)
      do_reload=0
      shift
      ;;
    --no-cache-clean)
      do_cache_clean=0
      shift
      ;;
    -n|--dry-run)
      dry_run=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      err "unknown option: $1"
      usage
      exit 2
      ;;
  esac
done

[[ -z "$prefix" || -n "${prefix//[[:space:]]/}" ]] || die "--prefix needs a non-empty value"
[[ -z "$source_dir" || -n "${source_dir//[[:space:]]/}" ]] || die "--source needs a non-empty value"
[[ -z "$archive_path" || -n "${archive_path//[[:space:]]/}" ]] || die "--archive needs a non-empty value"

case "$mode" in
  user)
    dest_root="${XDG_DATA_HOME:-$HOME/.local/share}/plasma/desktoptheme"
    SUDO=()
    ;;
  system)
    dest_root="/usr/share/plasma/desktoptheme"
    if (( EUID == 0 )); then
      SUDO=()
    else
      need_cmd sudo
      SUDO=(sudo)
    fi
    ;;
  prefix)
    dest_root="${prefix%/}/share/plasma/desktoptheme"
    SUDO=()
    ;;
  *)
    die "internal error: bad install mode: $mode"
    ;;
esac
readonly dest_root
readonly DEST="$dest_root/$THEME_ID"

extract_archive() {
  local archive="$1"

  [[ -f "$archive" ]] || die "archive not found: $archive"
  need_cmd tar
  work_dir="$(mktemp -d "${TMPDIR:-/tmp}/${THEME_ID}.XXXXXX")"

  info "Extracting $archive"
  tar -xzf "$archive" -C "$work_dir"

  local candidate="$work_dir/$THEME_ID"
  if [[ -d "$candidate" ]]; then
    printf '%s\n' "$candidate"
    return 0
  fi

  candidate="$(find "$work_dir" -mindepth 1 -maxdepth 2 -type f -name metadata.json -printf '%h\n' | head -n 1 || true)"
  [[ -n "$candidate" && -d "$candidate" ]] || die "could not find theme metadata.json inside archive"
  printf '%s\n' "$candidate"
}

resolve_source_dir() {
  if [[ -n "$source_dir" && -n "$archive_path" ]]; then
    die "use either --source or --archive, not both"
  fi

  if [[ -n "$source_dir" ]]; then
    [[ -d "$source_dir" ]] || die "source directory not found: $source_dir"
    printf '%s\n' "$(cd -- "$source_dir" && pwd)"
    return 0
  fi

  if [[ -n "$archive_path" ]]; then
    extract_archive "$archive_path"
    return 0
  fi

  if [[ -f "$SCRIPT_DIR/metadata.json" && -f "$SCRIPT_DIR/plasmarc" ]]; then
    printf '%s\n' "$SCRIPT_DIR"
    return 0
  fi

  if [[ -d "$SCRIPT_DIR/$THEME_ID" && -f "$SCRIPT_DIR/$THEME_ID/metadata.json" ]]; then
    printf '%s\n' "$SCRIPT_DIR/$THEME_ID"
    return 0
  fi

  if [[ -f "$SCRIPT_DIR/$ARCHIVE_BASENAME" ]]; then
    extract_archive "$SCRIPT_DIR/$ARCHIVE_BASENAME"
    return 0
  fi

  die "no source found. Run from the theme directory, place $ARCHIVE_BASENAME next to this script, or pass --archive/--source"
}

validate_source() {
  local src="$1"

  [[ -f "$src/metadata.json" ]] || die "metadata.json not found in source: $src"
  [[ -f "$src/plasmarc" ]] || die "plasmarc not found in source: $src"

  if ! grep -q '"Id"[[:space:]]*:[[:space:]]*"breeze-bottom-indicator"' "$src/metadata.json"; then
    die "metadata.json does not look like $THEME_ID"
  fi
}

copy_file_with_dirs() {
  local src_root="$1"
  local rel_path="$2"
  local target_dir

  target_dir="$DEST/$(dirname -- "$rel_path")"
  run "${SUDO[@]}" install -d -m 0755 "$target_dir"
  run "${SUDO[@]}" install -m 0644 "$src_root/$rel_path" "$DEST/$rel_path"
}

install_theme() {
  local src="$1"

  info "Installing $THEME_NAME to $DEST"
  run "${SUDO[@]}" install -d -m 0755 "$DEST"

  # Replace previous runtime files cleanly, but never remove outside the theme dir.
  if [[ "$DEST" == */$THEME_ID ]]; then
    run "${SUDO[@]}" rm -rf -- "$DEST"
    run "${SUDO[@]}" install -d -m 0755 "$DEST"
  else
    die "refusing to clean unexpected destination: $DEST"
  fi

  # Runtime files needed by Plasma. This intentionally excludes development backups.
  copy_file_with_dirs "$src" "metadata.json"
  copy_file_with_dirs "$src" "plasmarc"

  while IFS= read -r -d '' file_path; do
    rel_path="${file_path#"$src/"}"
    copy_file_with_dirs "$src" "$rel_path"
  done < <(find "$src" -type f -name '*.svgz' -print0 | sort -z)
}

uninstall_theme() {
  if [[ ! -d "$DEST" ]]; then
    warn "$DEST does not exist. Nothing to uninstall."
    return 0
  fi

  [[ "$DEST" == */$THEME_ID ]] || die "refusing to remove unexpected destination: $DEST"
  [[ -f "$DEST/metadata.json" ]] || die "$DEST has no metadata.json. Refusing to remove it."

  info "Removing $DEST"
  run "${SUDO[@]}" rm -rf -- "$DEST"
}

clean_caches() {
  (( do_cache_clean )) || return 0

  local cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}"
  info "Clearing Plasma cache files for $THEME_ID"

  shopt -s nullglob
  local stale=(
    "$cache_dir/plasma_theme_${THEME_ID}"*
    "$cache_dir/plasma-svgelements-${THEME_ID}"*
  )
  shopt -u nullglob

  if (( ${#stale[@]} )); then
    run rm -rf -- "${stale[@]}"
  fi
}

apply_theme() {
  (( do_apply )) || return 0

  if ! command -v plasma-apply-desktoptheme >/dev/null 2>&1; then
    warn "plasma-apply-desktoptheme not found. Apply manually in System Settings."
    return 0
  fi

  info "Setting active Plasma desktop theme to $THEME_ID"
  run plasma-apply-desktoptheme "$THEME_ID"
}

reload_plasma() {
  (( do_reload )) || return 0

  if [[ -z "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ]]; then
    warn "no graphical session detected. Skipping plasmashell reload."
    return 0
  fi

  if command -v systemctl >/dev/null 2>&1 \
      && systemctl --user list-unit-files plasma-plasmashell.service >/dev/null 2>&1 \
      && systemctl --user is-active --quiet plasma-plasmashell.service; then
    info "Restarting plasma-plasmashell.service"
    run systemctl --user restart plasma-plasmashell.service
    return 0
  fi

  if pgrep -x plasmashell >/dev/null 2>&1; then
    info "Restarting plasmashell"
    if command -v kquitapp6 >/dev/null 2>&1; then
      run kquitapp6 plasmashell || true
    else
      run pkill -x plasmashell || true
    fi

    sleep 1

    if command -v kstart >/dev/null 2>&1; then
      run setsid -f kstart plasmashell >/dev/null 2>&1 || true
    else
      run setsid -f plasmashell >/dev/null 2>&1 || true
    fi
  else
    warn "plasmashell is not running. Nothing to reload."
  fi
}

main() {
  need_cmd find
  need_cmd grep
  need_cmd install
  need_cmd sort

  if (( do_install )); then
    src="$(resolve_source_dir)"
    validate_source "$src"
    install_theme "$src"
  else
    uninstall_theme
  fi

  clean_caches
  apply_theme
  reload_plasma

  if (( dry_run )); then
    info "dry run complete. No files were changed."
  elif (( do_install )); then
    cat <<EOF_DONE

${c_grn}Done.${c_off} Installed to: $DEST
Activate: System Settings -> Colors & Themes -> Plasma Style -> "$THEME_NAME"
Command:  plasma-apply-desktoptheme $THEME_ID
EOF_DONE
  else
    info "Uninstalled $THEME_NAME"
  fi
}

main "$@"
