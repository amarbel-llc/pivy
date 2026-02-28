#! /usr/bin/env bats

setup() {
  load "$(dirname "$BATS_TEST_FILE")/common.bash"
  export output
}

teardown() {
  chflags_and_rm
}

stub_service_commands() {
  # Stub out service management commands so tests don't escape the sandbox.
  # pivy-agent calls systemctl (Linux) or launchctl (macOS) which would
  # otherwise talk to the real service manager.
  local stub_dir="$BATS_TEST_TMPDIR/stub-bin"
  local exit_code="${1:-0}"
  mkdir -p "$stub_dir"
  printf '#!/bin/sh\nexit %s\n' "$exit_code" >"$stub_dir/systemctl"
  printf '#!/bin/sh\nexit %s\n' "$exit_code" >"$stub_dir/launchctl"
  chmod +x "$stub_dir/systemctl" "$stub_dir/launchctl"
  PATH="$stub_dir:$PATH"
}

install_service_setup() {
  local home="$BATS_TEST_TMPDIR/home"
  if [[ "$(uname)" == "Darwin" ]]; then
    mkdir -p "$home/Library"
    SERVICE_FILE="$home/Library/LaunchAgents/net.cooperi.pivy-agent.plist"
  else
    mkdir -p "$home/.config"
    SERVICE_FILE="$home/.config/systemd/user/pivy-agent@.service"
  fi
  INSTALL_HOME="$home"
  stub_service_commands
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

function install_service_writes_service_file_with_socket_path { # @test
  install_service_setup

  # service management commands fail in test sandbox, but files should be written
  HOME="$INSTALL_HOME" run pivy-agent install-service -A -a /tmp/first.sock
  assert [ -f "$SERVICE_FILE" ]
  run grep '/tmp/first.sock' "$SERVICE_FILE"
  assert_success
}

function install_service_reinstall_updates_socket_path { # @test
  install_service_setup

  HOME="$INSTALL_HOME" run pivy-agent install-service -A -a /tmp/first.sock
  assert [ -f "$SERVICE_FILE" ]

  HOME="$INSTALL_HOME" run pivy-agent install-service -A -a /tmp/second.sock
  run grep '/tmp/second.sock' "$SERVICE_FILE"
  assert_success
  run grep '/tmp/first.sock' "$SERVICE_FILE"
  assert_failure
}

function install_service_contains_askpass_env { # @test
  install_service_setup

  HOME="$INSTALL_HOME" run pivy-agent install-service -A -a /tmp/test.sock
  assert [ -f "$SERVICE_FILE" ]
  run grep 'SSH_ASKPASS' "$SERVICE_FILE"
  assert_success
  run grep 'SSH_ASKPASS_REQUIRE' "$SERVICE_FILE"
  assert_success
  run grep 'force' "$SERVICE_FILE"
  assert_success
}

function install_service_contains_notify_env { # @test
  install_service_setup

  HOME="$INSTALL_HOME" run pivy-agent install-service -A -a /tmp/test.sock
  assert [ -f "$SERVICE_FILE" ]
  run grep 'SSH_NOTIFY_SEND' "$SERVICE_FILE"
  assert_success
}

function install_service_contains_confirm_env { # @test
  install_service_setup

  HOME="$INSTALL_HOME" run pivy-agent install-service -A -a /tmp/test.sock
  assert [ -f "$SERVICE_FILE" ]
  run grep 'SSH_CONFIRM' "$SERVICE_FILE"
  assert_success
}

function install_service_no_askpass_omits_askpass_env { # @test
  install_service_setup

  HOME="$INSTALL_HOME" run pivy-agent install-service -A -a /tmp/test.sock --no-askpass
  assert [ -f "$SERVICE_FILE" ]
  run grep 'SSH_ASKPASS' "$SERVICE_FILE"
  assert_failure
}

function install_service_no_notify_omits_notify_env { # @test
  install_service_setup

  HOME="$INSTALL_HOME" run pivy-agent install-service -A -a /tmp/test.sock --no-notify
  assert [ -f "$SERVICE_FILE" ]
  run grep 'SSH_NOTIFY_SEND' "$SERVICE_FILE"
  assert_failure
}

# --- restart-service ---

function restart_service_fails_without_service_installed { # @test
  stub_service_commands 1
  run pivy-agent restart-service
  assert_failure
  assert_output --partial "restart failed"
}

# --- uninstall-service ---

function uninstall_service_recognized_as_subcommand { # @test
  stub_service_commands
  HOME="$BATS_TEST_TMPDIR" run pivy-agent uninstall-service
  assert_success
  assert_output --partial "Uninstalled"
}
