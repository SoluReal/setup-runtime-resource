#!/bin/bash

set -eo pipefail

chroot_dir="$1"
source "$ROOT_DIR/common.sh"

# mmdebstrap runs hooks serially, so this one fans the independent runtime groups out itself.
# Groups log progress events live to $OUTPUT_FILE; raw tool output goes to a per-group file.
work_dir=$(mktemp -d)
declare -A group_of started_at
durations=0

function start_group() {
  local name="$1"
  shift
  (
    export GROUP_NAME="$name" RUNTIME_BASHRC="$work_dir/$name.bashrc" SETUP_PARALLEL=true
    for runtime in "$@"; do
      bash "$ROOT_DIR/runtimes/$runtime.sh" "$chroot_dir"
    done
  ) > "$work_dir/$name.out" 2>&1 &
  group_of[$!]="$name"
  started_at[$name]=$SECONDS
}

# One contiguous block per group, so concurrent groups' output never mixes.
function print_group_output() {
  local name="$1"
  { printf "%b[setup-runtime] ── %s output ──%b\n" "$Green" "$name" "$Color_Off"; cat "$work_dir/$name.out"; } \
    > "$work_dir/$name.block"
  cat "$work_dir/$name.block" >> "$OUTPUT_FILE"
}

all_started=$SECONDS
start_group sdkman sdkman java
start_group node nvm node
start_group pyenv pyenv
start_group golang golang

failed=0
while (( ${#group_of[@]} > 0 )); do
  status=0
  wait -n -p finished "${!group_of[@]}" || status=$?
  name="${group_of[$finished]}"
  unset "group_of[$finished]"
  elapsed=$((SECONDS - started_at[$name]))
  durations=$((durations + elapsed))
  GROUP_NAME="$name"
  if [[ $status -eq 0 ]]; then
    group_event "✔" "$Green" "done" "$(format_elapsed $elapsed)"
    if [[ "$VERBOSE" = "true" ]]; then
      print_group_output "$name"
    fi
  else
    group_event "✘" "$Red" "failed" "$(format_elapsed $elapsed)"
    print_group_output "$name"
    error "runtime group '$name' failed (exit $status), see its output above"
    failed=1
  fi
done

[[ $failed -eq 0 ]] || exit 1

info_to_output_file "runtimes ready in $(format_elapsed $((SECONDS - all_started))) (sequential would be $(format_elapsed $durations))"

# Fixed order, as the hooks used to append them, so PATH precedence is unchanged.
for name in sdkman node pyenv golang; do
  if [[ -f "$work_dir/$name.bashrc" ]]; then
    cat "$work_dir/$name.bashrc" >> "$chroot_dir$RUNTIME_HOME/.bashrc"
  fi
done
rm -rf "$work_dir"
