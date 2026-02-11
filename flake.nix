{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/23d72dabcb3b12469f57b37170fcbc1789bd7457";
    nixpkgs-master.url = "github:NixOS/nixpkgs/b28c4999ed71543e71552ccfd0d7e68c581ba7e9";
    utils.url = "https://flakehub.com/f/numtide/flake-utils/0.1.102";
  };

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-master,
      utils,
    }:
    (utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
        };

        pkgs-master = import nixpkgs-master {
          inherit system;
        };

        libressl-src = pkgs.fetchurl {
          url = "https://ftp.openbsd.org/pub/OpenBSD/LibreSSL/libressl-4.0.0.tar.gz";
          sha256 = "sha256-TYQZVfCsw9/HHQ49018oOvRhIiNQ4mhD/qlzHAJGoeQ=";
        };

        openssh-src = pkgs.fetchurl {
          url = "https://ftp.openbsd.org/pub/OpenBSD/OpenSSH/portable/openssh-10.0p1.tar.gz";
          sha256 = "sha256-AhoucJoO30JQsSVr1anlAEEakN3avqgw7VnO+Q652Fw=";
        };

        buildInputs = with pkgs; [
          libbsd
          libedit
          zlib
        ] ++ pkgs.lib.optionals (!pkgs.stdenv.isDarwin) [
          pcsclite
        ];

        nativeBuildInputs = with pkgs; [
          gcc
          gnumake
          pkg-config
          ragel
          curl
          gnutar
          patch
          makeWrapper
        ];

        pivy = pkgs.stdenv.mkDerivation {
          pname = "pivy";
          version = "0.12.1";

          src = ./.;

          inherit buildInputs nativeBuildInputs;

          postPatch = ''
            # Extract vendored sources instead of downloading
            mkdir -p libressl openssh
            tar -xzf ${libressl-src} --strip-components=1 -C libressl
            touch .libressl.extract
            tar -xzf ${openssh-src} --strip-components=1 -C openssh
            touch .openssh.extract
          '';

          buildPhase = ''
            runHook preBuild
            make -j$NIX_BUILD_CORES \
              ZLIB_LIB=${pkgs.zlib}/lib \
              SYSTEM_CFLAGS="-arch ${pkgs.stdenv.hostPlatform.darwinArch}" \
              SYSTEM_LDFLAGS="-arch ${pkgs.stdenv.hostPlatform.darwinArch}"
            runHook postBuild
          '';

          installPhase = ''
            runHook preInstall
            mkdir -p $out/bin
            install -m 755 pivy-tool $out/bin/.pivy-tool-unwrapped
            install -m 755 pivy-agent $out/bin/.pivy-agent-unwrapped
            install -m 755 pivy-box $out/bin/.pivy-box-unwrapped

            # Create wrapper scripts that preload system pcsclite
            # This is needed on non-NixOS where pcscd version must match client library
            for cmd in pivy-tool pivy-agent pivy-box; do
              cat > $out/bin/$cmd <<WRAPPER
            #!/bin/sh
            for lib in \\
              /usr/lib/x86_64-linux-gnu/libpcsclite.so.1 \\
              /usr/lib/aarch64-linux-gnu/libpcsclite.so.1 \\
              /usr/lib/libpcsclite.so.1 \\
              /lib/x86_64-linux-gnu/libpcsclite.so.1 \\
              /lib/libpcsclite.so.1; do
              if [ -e "\$lib" ]; then
                export LD_PRELOAD="\$lib\''${LD_PRELOAD:+:\$LD_PRELOAD}"
                break
              fi
            done
            exec $out/bin/.$cmd-unwrapped "\$@"
            WRAPPER
              chmod +x $out/bin/$cmd
            done
            runHook postInstall
          '';

          meta = with pkgs.lib; {
            description = "PIV tools for YubiKey and similar hardware tokens";
            homepage = "https://github.com/arekinath/pivy";
            license = licenses.mpl20;
            platforms = platforms.linux ++ platforms.darwin;
          };
        };
      in
      {
        packages.default = pivy;
        packages.pivy = pivy;

        devShells.default = pkgs.mkShell {
          packages = buildInputs ++ nativeBuildInputs;
        };
      }
    ));
}
