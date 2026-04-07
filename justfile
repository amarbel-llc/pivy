default: build test

build: build-nix build-nix-rust

build-nix:
  nix build

build-nix-rust:
  nix build .#pivy-rust -o result-rust

build-rust:
  cd rust && cargo build

build-rust-release:
  cd rust && cargo build --release

test: test-bats test-bats-rust

test-bats: build-nix
  PATH="$(readlink -f ./result)/bin:$PATH" just zz-tests_bats/test

test-bats-rust: build-nix-rust
  PIVY_AGENT_RUST="$(readlink -f ./result-rust)/bin/pivy-agent-rust" just zz-tests_bats/test-rust

test-rust:
  cd rust && cargo test

test-rust-verbose:
  cd rust && cargo test -- --nocapture

fmt:
  cd rust && cargo fmt

clippy:
  cd rust && cargo clippy -- -D warnings

check:
  cd rust && cargo check

clean:
  cd rust && cargo clean
