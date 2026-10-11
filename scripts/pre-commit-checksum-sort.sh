#!/usr/bin/env bash
# pre-commit-checksum-sort.sh - pre-commit wrapper for checksum-sort.sh
# Runs scripts/checksum-sort.sh on each staged filter list file and
# re-stages the result so checksums/sorting are included in the commit.
#
# Layout note (AdmiraList): the maintained list is the single root file
# AdmiraList.txt, so this wrapper gates on that exact path instead of a
# filters/ directory.
#
# Usage (called by pre-commit with staged filenames):
#   scripts/pre-commit-checksum-sort.sh [file ...]
# Fallback (no args): process staged files under the CONFIG pathspec.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SORT_SCRIPT="${SCRIPT_DIR}/checksum-sort.sh"

# --- CONFIG (repo-specific; keep logic below untouched) ---
# Space-separated git pathspecs selecting the maintained filter lists.
# Quoted as one word so each space-separated token is passed as-is to git.
FILTER_PATHSPECS='AdmiraList.txt'
# ERE (case) matching the same set for the second-line-of-defense gate.
FILTER_GATE='^AdmiraList\.txt$'
# ----------------------------------------------------------

log_info() {
  echo "$*" >&2
}

log_error() {
  echo "❌ $*" >&2
}

collect_staged_filters() {
  # shellcheck disable=SC2086
  git -C "$REPO_ROOT" diff --cached --name-only --diff-filter=ACM -- $FILTER_PATHSPECS
}

process_one() {
  local rel="$1"
  local abs="${REPO_ROOT}/${rel}"

  if [[ ! -f "$abs" ]]; then
    return 0
  fi

  log_info "🔄 checksum-sort: ${rel}"
  "$SORT_SCRIPT" "$abs"
  git -C "$REPO_ROOT" add -- "$rel"
}

main() {
  if [[ ! -x "$SORT_SCRIPT" ]]; then
    log_error "Sort script not found or not executable: ${SORT_SCRIPT}"
    exit 1
  fi

  local files=()
  if [[ $# -gt 0 ]]; then
    files=("$@")
  else
    while IFS= read -r line || [[ -n "$line" ]]; do
      [[ -z "$line" ]] && continue
      files+=("$line")
    done < <(collect_staged_filters)
  fi

  if [[ ${#files[@]} -eq 0 ]]; then
    exit 0
  fi

  local file=""
  local rel=""
  for file in "${files[@]}"; do
    # Normalize to repo-relative path for the FILTER_GATE gate.
    rel="${file#"${REPO_ROOT}"/}"
    if [[ ! "$rel" =~ $FILTER_GATE ]]; then
      continue
    fi
    # Skip deleted / non-regular files.
    if [[ ! -f "${REPO_ROOT}/${rel}" ]]; then
      continue
    fi
    process_one "$rel"
  done
}

main "$@"
