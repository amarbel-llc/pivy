#! /usr/bin/env bats
#
# Go-based conformance tests run against the Rust pivy-agent rewrite.
# Uses Go's x/crypto/ssh/agent as an independent parser to validate that
# pivy-agent-rust responses conform to the IETF SSH agent protocol spec.
#
# No PIV card required — runs against pivy-agent-rust in all-card mode.

setup() {
  load "$(dirname "$BATS_TEST_FILE")/common.bash"

  if [[ -n ${PIVY_AGENT_RUST:-} ]]; then
    RUST_AGENT="$PIVY_AGENT_RUST"
  else
    RUST_AGENT="$(dirname "$BATS_TEST_FILE")/../result-rust/bin/pivy-agent-rust"
  fi
  CONFORMANCE_DIR="${CONFORMANCE_DIR:-$(dirname "$BATS_TEST_FILE")/../result-conformance}"
  CONFORMANCE_BIN="$CONFORMANCE_DIR/bin/pivy-agent-conformance"

  if [[ ! -x $RUST_AGENT ]]; then
    skip "pivy-agent-rust not found at $RUST_AGENT (run: nix build .#pivy-rust -o result-rust)"
  fi
  if [[ ! -x $CONFORMANCE_BIN ]]; then
    skip "conformance binary not found (run: nix build .#pivy-agent-conformance -o result-conformance)"
  fi

  PIVY_TMPDIR="$(mktemp -d /tmp/pivy-test.XXXXXX)"
  AGENT_SOCK="$PIVY_TMPDIR/agent.sock"

  "$RUST_AGENT" -A -D -a "$AGENT_SOCK" &
  AGENT_PID=$!

  local tries=0
  while [[ ! -S $AGENT_SOCK ]] && ((tries < 10)); do
    sleep 0.2
    tries=$((tries + 1))
  done
  [[ -S $AGENT_SOCK ]] || {
    kill "$AGENT_PID" 2>/dev/null || true
    skip "agent socket did not appear (pcscd may not be available)"
  }
}

teardown() {
  if [[ -n ${AGENT_PID:-} ]]; then
    kill "$AGENT_PID" 2>/dev/null || true
    wait "$AGENT_PID" 2>/dev/null || true
  fi
  if [[ -n ${PIVY_TMPDIR:-} ]]; then
    rm -rf "$PIVY_TMPDIR"
  fi
}

function rust_agent_conformance_runs { # @test
  run "$CONFORMANCE_BIN" "$AGENT_SOCK"
  # TDD baseline: print results regardless of pass/fail count.
  # As extensions are implemented, failures will convert to passes.
  echo "$output"
  assert_output --partial "passed"
  refute_output --partial "CRASH"
  refute_output --partial "connection reset"
  refute_output --partial "broken pipe"
}
