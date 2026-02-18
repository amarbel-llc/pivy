build:
  nix build

test-bats: build
  PATH="$(readlink -f ./result)/bin:$PATH" just zz-tests_bats/test

test: test-bats

build-rust:
  cd rust && cargo build

build-rust-release:
  cd rust && cargo build --release

build-nix:
  nix build .#pivy-rust

test:
  cd rust && cargo test

test-verbose:
  cd rust && cargo test -- --nocapture

fmt:
  cd rust && cargo fmt

clippy:
  cd rust && cargo clippy -- -D warnings

check:
  cd rust && cargo check

clean:
  cd rust && cargo clean
