# mcpp — modern C++23 build & package management tool.
#
# This formula ships the SAME prebuilt release artifacts that upstream's
# `install.sh` one-liner downloads (mcpp-community/mcpp → release.yml).
#
# Why `mcpp-m` and not `mcpp`: homebrew-core already owns the name `mcpp`
# (Matsui's C preprocessor). Same collision as Arch, where upstream ships
# `mcpp-bin` / `mcpp-m`. `Aliases/` maps both of those spellings here, so
# `brew install mcpp-community/mcpp/mcpp` works too once the tap is present.
#
# version / url / sha256 are rewritten by scripts/update-formula.sh — the
# bump workflow owns those three lines, so don't hand-edit them.
class McppM < Formula
  desc "Modern C++23 build and package management tool (module-first)"
  homepage "https://github.com/mcpp-community/mcpp"
  version "2026.7.30.3"
  license "Apache-2.0"

  # mcpp keeps its package index in sync over git.
  depends_on "git"

  on_macos do
    # Upstream publishes an arm64-only macOS artifact, built with minos 14.0
    # (release.yml asserts it). Intel Macs have no asset — build from source
    # via `xlings install mcpp` or the install.sh one-liner instead.
    depends_on arch: :arm64
    depends_on macos: :sonoma

    url "https://github.com/mcpp-community/mcpp/releases/download/v2026.7.30.3/mcpp-2026.7.30.3-macosx-arm64.tar.gz"
    sha256 "1659be17b3f54c495c224179a570dd220fcfead25bbcda0c6279b20afa6a4e18"
  end

  on_linux do
    on_intel do
      url "https://github.com/mcpp-community/mcpp/releases/download/v2026.7.30.3/mcpp-2026.7.30.3-linux-x86_64.tar.gz"
      sha256 "115cc537b17bfcaf5b5d13e0c7fcf9a591864cb6f18d10244e3828cfc1f8e1c4"
    end
    on_arm do
      url "https://github.com/mcpp-community/mcpp/releases/download/v2026.7.30.3/mcpp-2026.7.30.3-linux-aarch64.tar.gz"
      sha256 "aff78e9e04d0dfc09ef828b9a5aad3e1e4afff19de47b493a88bbbf803a00d14"
    end
  end

  livecheck do
    url :homepage
    strategy :github_latest
  end

  def install
    # The release tarball is a self-contained tree. Keep it whole under
    # libexec and put a launcher on PATH — see the wrapper comment below for
    # why a plain `bin.install` would break every write mcpp makes.
    libexec.install "bin"
    libexec.install "registry" if File.directory?("registry")

    # mcpp WRITES at runtime: registry sandbox, BMI/metadata caches, logs and
    # every toolchain it downloads (hundreds of MB). It resolves MCPP_HOME
    # from the running binary's *real* path (canonical, symlinks resolved), so
    # a bare symlink into the Cellar would make MCPP_HOME the Cellar version
    # dir — `brew upgrade` would then silently drop every installed toolchain.
    # Pin the two env knobs the binary honors, deferring to values the user
    # already exported. Mirrors the Arch launcher (upstream scripts/aur).
    (bin/"mcpp").write <<~SH
      #!/bin/sh
      export MCPP_HOME="${MCPP_HOME:-$HOME/.mcpp}"
      export MCPP_VENDORED_XLINGS="${MCPP_VENDORED_XLINGS:-#{libexec}/registry/bin/xlings}"
      exec "#{libexec}/bin/mcpp" "$@"
    SH
    chmod 0755, bin/"mcpp"

    prefix.install "LICENSE" if File.exist?("LICENSE")
    doc.install "README.md" if File.exist?("README.md")
  end

  def caveats
    <<~EOS
      mcpp keeps per-user state in ~/.mcpp (registry, caches, toolchains).
      Override with MCPP_HOME=<dir>; remove ~/.mcpp to reset.

      The first `mcpp build` downloads a toolchain (LLVM on macOS) and may
      take a while. It is cached in ~/.mcpp and survives `brew upgrade`.
    EOS
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/mcpp --version")
    assert_match "Usage:", shell_output("#{bin}/mcpp --help")

    # The launcher must pin MCPP_HOME outside the Cellar, or `brew upgrade`
    # would take the user's toolchains with it. Asserted statically: the
    # commands that would print the resolved home (`mcpp self env`) bootstrap
    # the sandbox over the network, which has no place in a formula test.
    launcher = (bin/"mcpp").read
    assert_match(/MCPP_HOME="\$\{MCPP_HOME:-\$HOME\/\.mcpp\}"/, launcher)
    assert_predicate libexec/"bin/mcpp", :executable?
  end
end
