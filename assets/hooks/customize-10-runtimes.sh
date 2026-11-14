#!/bin/bash

set -eo pipefail

chroot_dir="$1"
source "$ROOT_DIR/common.sh"

# mmdebstrap runs hooks serially, so this one fans the independent runtime
# groups out itself. Each group gets its own log and .bashrc fragment.
work_dir=$(mktemp -d)
pids=()
names=()

function start_group() {
  local name="$1"
  shift
  : > "$work_dir/$name.log"
  (
    export OUTPUT_FILE="$work_dir/$name.log" RUNTIME_BASHRC="$work_dir/$name.bashrc" SETUP_PARALLEL=true
    for runtime in "$@"; do
      bash "$ROOT_DIR/runtimes/$runtime.sh" "$chroot_dir"
    done
  ) > "$work_dir/$name.out" 2>&1 &
  pids+=($!)
  names+=("$name")
}

start_group sdkman sdkman java
start_group node nvm node
start_group pyenv pyenv
start_group golang golang

failed=0
for i in "${!pids[@]}"; do
  name="${names[$i]}"
  status=0
  wait "${pids[$i]}" || status=$?
  cat "$work_dir/$name.log" >> "$OUTPUT_FILE"
  if [[ $status -ne 0 ]]; then
    error "runtime group '$name' failed (exit $status), its output:"
    cat "$work_dir/$name.out" >&2
    failed=1
  elif [[ "$VERBOSE" = "true" ]]; then
    cat "$work_dir/$name.out"
  fi
done

[[ $failed -eq 0 ]] || exit 1

# Fixed order, as the hooks used to append them, so PATH precedence is unchanged.
for name in sdkman node pyenv golang; do
  if [[ -f "$work_dir/$name.bashrc" ]]; then
    cat "$work_dir/$name.bashrc" >> "$chroot_dir$RUNTIME_HOME/.bashrc"
  fi
done
rm -rf "$work_dir"
