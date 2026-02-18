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
