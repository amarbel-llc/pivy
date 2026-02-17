bats_load_library bats-support
bats_load_library bats-assert
bats_load_library bats-assert-additions

chflags_and_rm() {
  chflags -R nouchg "$BATS_TEST_TMPDIR" 2>/dev/null || true
  rm -rf "$BATS_TEST_TMPDIR"
}
