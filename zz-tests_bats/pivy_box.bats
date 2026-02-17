#! /usr/bin/env bats

setup() {
  load "$(dirname "$BATS_TEST_FILE")/common.bash"
  export output
}

teardown() {
  chflags_and_rm
}

function no_args_prints_usage_and_fails { # @test
  run pivy-box
  assert_failure
  assert_output --partial "type and operation required"
}

function type_without_op_prints_usage_and_fails { # @test
  run pivy-box key
  assert_failure
  assert_output --partial "operation required"
}

function bad_type_and_op_fails { # @test
  run pivy-box nonexistent badop
  assert_failure
}
