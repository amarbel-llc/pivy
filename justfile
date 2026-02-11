build:
  make -j$(nproc)

install:
  sudo make -C build/pivy install
