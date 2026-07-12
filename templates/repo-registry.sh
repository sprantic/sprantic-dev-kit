# repo — cross-machine registry of git clones under ~/projects.
#
# Configs and apps already sync between machines through the env repo; the clones
# themselves don't. This closes that gap with a checked-in manifest (repos.manifest,
# one "relpath url" per line) and four verbs:
#
#   repo register [--update] [dir]   add the clone at dir (default: cwd); --update
#                                    pushes a changed local origin URL into the manifest
#   repo scan                        walk ~/projects and register every clone found
#   repo sync [--fetch] [--fix-remotes]  clone everything missing here; --fix-remotes
#                                    resets drifted local origin URLs to the manifest
#   repo status [--fetch] [--dirty] [name...]  manifest vs. local: missing, untracked,
#                                    DRIFTED remotes, plus each clone's branch state
#                                    (ahead/behind upstream, dirty); --fetch refreshes
#                                    remotes first so the counts are current; --dirty
#                                    hides clean in-sync clones, leaving only the ones
#                                    needing attention (dirty, ahead/behind, no
#                                    upstream, detached, drifted, missing, untracked);
#                                    trailing names limit output to repos whose base
#                                    name (last path component) or full relpath matches
#
# The manifest travels like every other config: commit + push env, pull on the other
# machine, `repo sync`. Clones run through `direnv exec <parent>` so the per-tree
# identity wiring (use_github in .envrc, SSH aliases) picks the right key — same as
# cloning by hand from inside that tree.
#
# Conventions are overridable: REPO_PROJECTS_ROOT (default ~/projects) and
# REPO_MANIFEST (default $REPO_PROJECTS_ROOT/env/repos.manifest).

PROJECTS="${REPO_PROJECTS_ROOT:-$HOME/projects}"
MANIFEST="${REPO_MANIFEST:-$PROJECTS/env/repos.manifest}"

usage() {
  sed -n 's/^#   //p' "$0" 2>/dev/null || true
  echo "manifest: $MANIFEST"
}

# Look up a manifest entry's URL by relpath (exact match on field 1). Empty if absent.
manifest_url() {
  [ -f "$MANIFEST" ] || return 0
  awk -v r="$1" '$1 == r { print $2; exit }' "$MANIFEST"
}

# `ignore <prefix>` lines in the manifest exclude whole trees (e.g. legacy dumps) from
# scan/status — the rule syncs with the manifest, so every machine ignores the same trees.
ignored() {
  [ -f "$MANIFEST" ] || return 1
  awk -v p="$1" '$1 == "ignore" && (p == $2 || index(p, $2 "/") == 1) { found = 1 } END { exit !found }' "$MANIFEST"
}

# The manifest is committed to the env repo — embedded http(s) credentials
# (https://user:token@host/...) must never land in it. Strip the userinfo part;
# ssh:// URLs keep their git@ (that's a username, not a secret).
clean_url() {
  case "$1" in
    http://*@* | https://*@*) printf '%s\n' "$1" | sed -E 's#^(https?://)[^/@]+@#\1#' ;;
    *) printf '%s\n' "$1" ;;
  esac
}

# Replace the URL recorded for a relpath (entry must exist).
manifest_set_url() {
  local tmp
  tmp=$(mktemp)
  awk -v r="$1" -v u="$2" '$1 == r { $2 = u } { print }' "$MANIFEST" > "$tmp"
  mv "$tmp" "$MANIFEST"
}

cmd_register() {
  local top rel url existing update=0
  if [ "${1:-}" = "--update" ]; then
    update=1
    shift
  fi
  top=$(git -C "${1:-.}" rev-parse --show-toplevel 2>/dev/null) || {
    echo "repo register: ${1:-.} is not inside a git work tree" >&2
    return 1
  }
  case "$top" in
    "$PROJECTS"/*) ;;
    *)
      echo "repo register: $top is outside $PROJECTS — only project clones are tracked" >&2
      return 1
      ;;
  esac
  rel=${top#"$PROJECTS"/}
  if [ "$rel" = "env" ]; then
    # The env repo carries the manifest; a machine that can read it already has the clone.
    return 0
  fi
  if ignored "$rel"; then
    echo "ignored: $rel (manifest ignore rule)"
    return 0
  fi
  url=$(git -C "$top" remote get-url origin 2>/dev/null) || {
    echo "repo register: $rel has no 'origin' remote — add one first" >&2
    return 1
  }
  if [ "$url" != "$(clean_url "$url")" ]; then
    echo "warning: $rel origin URL embeds credentials — recording it WITHOUT them" >&2
    url=$(clean_url "$url")
  fi
  existing=$(manifest_url "$rel")
  if [ -n "$existing" ]; then
    if [ "$existing" = "$url" ]; then
      echo "already registered: $rel"
    elif [ "$update" -eq 1 ]; then
      manifest_set_url "$rel" "$url"
      echo "updated: $rel -> $url  (was $existing)"
    else
      echo "repo register: $rel is registered with a DIFFERENT url:" >&2
      echo "  manifest: $existing" >&2
      echo "  local:    $url" >&2
      echo "if the LOCAL side is right: repo register --update; if the MANIFEST is right:" >&2
      echo "repo sync --fix-remotes (or edit $MANIFEST by hand)" >&2
      return 1
    fi
    return 0
  fi
  printf '%s %s\n' "$rel" "$url" >> "$MANIFEST"
  sort -o "$MANIFEST" "$MANIFEST"
  echo "registered: $rel -> $url"
}

cmd_scan() {
  local gitdir failures=0
  # -mindepth 2 keeps ~/projects itself out if it ever becomes a repo; .git as a
  # DIRECTORY means primary clones only (worktrees/submodules have a .git file).
  while IFS= read -r gitdir; do
    cmd_register "$(dirname "$gitdir")" || failures=$((failures + 1))
  done < <(find "$PROJECTS" -mindepth 2 -maxdepth 6 -type d -name .git -prune | sort)
  [ "$failures" -eq 0 ] || {
    echo "repo scan: $failures clone(s) could not be registered (see above)" >&2
    return 1
  }
  echo "scan done — review, then commit repos.manifest in the env repo to publish"
}

# Clone one manifest entry. Through direnv when available so the target tree's
# .envrc (identity pinning) applies exactly as it would for a manual clone there.
clone_one() {
  local rel=$1 url=$2 parent
  parent="$PROJECTS/$(dirname "$rel")"
  mkdir -p "$parent"
  if command -v direnv > /dev/null; then
    direnv exec "$parent" git clone "$url" "$PROJECTS/$rel" || {
      echo "repo sync: clone of $rel failed — if direnv reported a blocked .envrc," >&2
      echo "run 'direnv allow $parent' once on this machine and re-run repo sync" >&2
      return 1
    }
  else
    git clone "$url" "$PROJECTS/$rel"
  fi
}

cmd_sync() {
  local do_fetch=0 fix_remotes=0 arg rel url local_url failures=0 cloned=0 drifted=0
  for arg in "$@"; do
    case "$arg" in
      --fetch) do_fetch=1 ;;
      --fix-remotes) fix_remotes=1 ;;
      *) echo "repo sync: unknown flag $arg" >&2; return 1 ;;
    esac
  done
  [ -f "$MANIFEST" ] || {
    echo "repo sync: no manifest at $MANIFEST — pull the env repo first" >&2
    return 1
  }
  while read -r rel url; do
    case "$rel" in '' | '#'* | ignore) continue ;; esac
    if [ -e "$PROJECTS/$rel/.git" ]; then
      # Remote drift: the manifest is the published truth; a differing local origin is
      # either an unpublished change (repo register --update) or stale (fix it here).
      local_url=$(clean_url "$(git -C "$PROJECTS/$rel" remote get-url origin 2>/dev/null || true)")
      if [ -n "$local_url" ] && [ "$local_url" != "$url" ]; then
        if [ "$fix_remotes" -eq 1 ]; then
          git -C "$PROJECTS/$rel" remote set-url origin "$url"
          echo "remote fixed: $rel -> $url  (was $local_url)"
        else
          echo "remote DRIFTED: $rel (local $local_url, manifest $url) — --fix-remotes or repo register --update" >&2
          drifted=$((drifted + 1))
        fi
      fi
      if [ "$do_fetch" -eq 1 ]; then
        git -C "$PROJECTS/$rel" fetch --quiet || echo "fetch failed: $rel" >&2
      fi
      continue
    fi
    if clone_one "$rel" "$url"; then
      cloned=$((cloned + 1))
    else
      failures=$((failures + 1))
    fi
  done < "$MANIFEST"
  echo "sync done: $cloned cloned, $failures failed, $drifted drifted remote(s)"
  [ "$failures" -eq 0 ] && [ "$drifted" -eq 0 ]
}

# Branch state of the clone at $1 relative to its upstream: "in sync", "2 ahead",
# "1 behind", "1 ahead, 3 behind", "no upstream", or "detached"; ", dirty" appended
# when the work tree has uncommitted changes. Ahead/behind counts compare against
# the last fetch — pass --fetch to `repo status` for current numbers.
branch_state() {
  local top=$1 branch counts ahead behind state dirty=""
  [ -n "$(git -C "$top" status --porcelain 2>/dev/null)" ] && dirty=", dirty"
  branch=$(git -C "$top" symbolic-ref --quiet --short HEAD 2>/dev/null) || {
    printf 'detached%s' "$dirty"
    return 0
  }
  if counts=$(git -C "$top" rev-list --left-right --count "${branch}@{upstream}...${branch}" 2>/dev/null); then
    behind=${counts%%[[:space:]]*}
    ahead=${counts##*[[:space:]]}
    if [ "$ahead" -eq 0 ] && [ "$behind" -eq 0 ]; then
      state="in sync"
    elif [ "$behind" -eq 0 ]; then
      state="$ahead ahead"
    elif [ "$ahead" -eq 0 ]; then
      state="$behind behind"
    else
      state="$ahead ahead, $behind behind"
    fi
  else
    state="no upstream"
  fi
  printf '%s: %s%s' "$branch" "$state" "$dirty"
}

# Does relpath $1 pass the name filters? Exact match on the base name (last path
# component) or the full relpath; no filters means everything passes. `filters`
# is the calling function's array (bash locals are dynamically scoped).
name_selected() {
  local f base=${1##*/}
  [ "${#filters[@]}" -eq 0 ] && return 0
  for f in "${filters[@]}"; do
    if [ "$f" = "$base" ] || [ "$f" = "$1" ]; then
      return 0
    fi
  done
  return 1
}

cmd_status() {
  local do_fetch=0 dirty_only=0 arg rel url local_url state gitdir top
  local filters=()
  for arg in "$@"; do
    case "$arg" in
      --fetch) do_fetch=1 ;;
      --dirty) dirty_only=1 ;;
      --*) echo "repo status: unknown flag $arg" >&2; return 1 ;;
      *) filters+=("$arg") ;;
    esac
  done
  if [ -f "$MANIFEST" ]; then
    while read -r rel url; do
      case "$rel" in '' | '#'* | ignore) continue ;; esac
      name_selected "$rel" || continue
      if [ -e "$PROJECTS/$rel/.git" ]; then
        if [ "$do_fetch" -eq 1 ]; then
          git -C "$PROJECTS/$rel" fetch --quiet 2>/dev/null || echo "fetch failed: $rel" >&2
        fi
        local_url=$(clean_url "$(git -C "$PROJECTS/$rel" remote get-url origin 2>/dev/null || true)")
        state=$(branch_state "$PROJECTS/$rel")
        if [ -n "$local_url" ] && [ "$local_url" != "$url" ]; then
          echo "DRIFTED   $rel  (local $local_url, manifest $url; $state)"
        else
          # A clean, in-sync clone is the only state --dirty hides.
          case "$state" in
            *": in sync") [ "$dirty_only" -eq 1 ] && continue ;;
          esac
          echo "present   $rel  ($state)"
        fi
      else
        echo "MISSING   $rel  ($url)"
      fi
    done < "$MANIFEST"
  else
    echo "no manifest at $MANIFEST"
  fi
  # Local clones the manifest doesn't know about — candidates for `repo register`.
  while IFS= read -r gitdir; do
    top=$(dirname "$gitdir")
    rel=${top#"$PROJECTS"/}
    [ "$rel" = "env" ] && continue
    ignored "$rel" && continue
    name_selected "$rel" || continue
    [ -n "$(manifest_url "$rel")" ] || echo "UNTRACKED $rel  (repo register to add)"
  done < <(find "$PROJECTS" -mindepth 2 -maxdepth 6 -type d -name .git -prune | sort)
}

case "${1:-}" in
  register) shift; cmd_register "$@" ;;
  scan)     cmd_scan ;;
  sync)     shift || true; cmd_sync "$@" ;;
  status)   shift || true; cmd_status "$@" ;;
  list)     cat "$MANIFEST" 2>/dev/null || echo "no manifest at $MANIFEST" ;;
  *)        usage; exit 1 ;;
esac
