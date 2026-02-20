#! /usr/bin/env bats

setup() {
  load "$(dirname "$BATS_TEST_FILE")/common.bash"
  export output
}

teardown() {
  chflags_and_rm
}

function no_args_prints_usage_and_fails { # @test
  run pivy-agent
  assert_failure
  assert_output --partial "usage: pivy-agent"
}

function bad_option_prints_usage_and_fails { # @test
  run pivy-agent -Q
  assert_failure
  assert_output --partial "usage: pivy-agent"
}

# --- install-service ---

function install_service_bad_option_fails { # @test
  run pivy-agent install-service -Z
  assert_failure
  assert_output --partial "usage: pivy-agent install-service"
}

function install_service_mutually_exclusive_A_and_g_fails { # @test
  run pivy-agent install-service -A -g 0000
  assert_failure
  assert_output --partial "-A and -g are mutually exclusive"
}

function install_service_writes_plist_with_socket_path { # @test
  local home="$BATS_TEST_TMPDIR/home"
  mkdir -p "$home/Library"
  local plist="$home/Library/LaunchAgents/net.cooperi.pivy-agent.plist"

  # launchctl load fails in test sandbox, but plist should be written
  HOME="$home" run pivy-agent install-service -A -a /tmp/first.sock
  assert [ -f "$plist" ]
  run grep '/tmp/first.sock' "$plist"
  assert_success
}

function install_service_reinstall_updates_socket_path { # @test
  local home="$BATS_TEST_TMPDIR/home"
  mkdir -p "$home/Library"
  local plist="$home/Library/LaunchAgents/net.cooperi.pivy-agent.plist"

  HOME="$home" run pivy-agent install-service -A -a /tmp/first.sock
  assert [ -f "$plist" ]

  HOME="$home" run pivy-agent install-service -A -a /tmp/second.sock
  run grep '/tmp/second.sock' "$plist"
  assert_success
  run grep '/tmp/first.sock' "$plist"
  assert_failure
}

function install_service_plist_contains_askpass_env { # @test
  local home="$BATS_TEST_TMPDIR/home"
  mkdir -p "$home/Library"
  local plist="$home/Library/LaunchAgents/net.cooperi.pivy-agent.plist"

  HOME="$home" run pivy-agent install-service -A -a /tmp/test.sock
  assert [ -f "$plist" ]
  run grep 'SSH_ASKPASS' "$plist"
  assert_success
  run grep 'SSH_ASKPASS_REQUIRE' "$plist"
  assert_success
  run grep 'force' "$plist"
  assert_success
}

function install_service_plist_contains_notify_env { # @test
  local home="$BATS_TEST_TMPDIR/home"
  mkdir -p "$home/Library"
  local plist="$home/Library/LaunchAgents/net.cooperi.pivy-agent.plist"

  HOME="$home" run pivy-agent install-service -A -a /tmp/test.sock
  assert [ -f "$plist" ]
  run grep 'SSH_NOTIFY_SEND' "$plist"
  assert_success
}

function install_service_plist_contains_confirm_env { # @test
  local home="$BATS_TEST_TMPDIR/home"
  mkdir -p "$home/Library"
  local plist="$home/Library/LaunchAgents/net.cooperi.pivy-agent.plist"

  HOME="$home" run pivy-agent install-service -A -a /tmp/test.sock
  assert [ -f "$plist" ]
  run grep 'SSH_CONFIRM' "$plist"
  assert_success
}

function install_service_no_askpass_omits_askpass_env { # @test
  local home="$BATS_TEST_TMPDIR/home"
  mkdir -p "$home/Library"
  local plist="$home/Library/LaunchAgents/net.cooperi.pivy-agent.plist"

  HOME="$home" run pivy-agent install-service -A -a /tmp/test.sock --no-askpass
  assert [ -f "$plist" ]
  run grep 'SSH_ASKPASS' "$plist"
  assert_failure
}

function install_service_no_notify_omits_notify_env { # @test
  local home="$BATS_TEST_TMPDIR/home"
  mkdir -p "$home/Library"
  local plist="$home/Library/LaunchAgents/net.cooperi.pivy-agent.plist"

  HOME="$home" run pivy-agent install-service -A -a /tmp/test.sock --no-notify
  assert [ -f "$plist" ]
  run grep 'SSH_NOTIFY_SEND' "$plist"
  assert_failure
}

# --- restart-service ---

function restart_service_fails_without_service_installed { # @test
  run pivy-agent restart-service
  assert_failure
  assert_output --partial "restart failed"
}

# --- uninstall-service ---

function uninstall_service_recognized_as_subcommand { # @test
  HOME="$BATS_TEST_TMPDIR" run pivy-agent uninstall-service
  assert_success
  assert_output --partial "Uninstalled"
}
