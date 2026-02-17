build:
  nix build

test-bats: build
  PATH="$(readlink -f ./result)/bin:$PATH" just zz-tests_bats/test

test: test-bats
