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
  version "2026.7.30.2"
  license "Apache-2.0"

  # mcpp keeps its package index in sync over git.
  depends_on "git"

  on_macos do
    # Upstream publishes an arm64-only macOS artifact, built with minos 14.0
    # (release.yml asserts it). Intel Macs have no asset — build from source
    # via `xlings install mcpp` or the install.sh one-liner instead.
    depends_on arch: :arm64
    depends_on macos: :sonoma

    url "https://github.com/mcpp-community/mcpp/releases/download/v2026.7.30.2/mcpp-2026.7.30.2-macosx-arm64.tar.gz"
    sha256 "23ffd00bba91094d86d5a3a19ffb005f84b62f0309020035feaf1e129e1df838"
  end

  on_linux do
    on_intel do
      url "https://github.com/mcpp-community/mcpp/releases/download/v2026.7.30.2/mcpp-2026.7.30.2-linux-x86_64.tar.gz"
      sha256 "4b048875027731ed7d66f219b7fb4dd73a1bfe9427809e187a81e6121e96b8dc"
    end
    on_arm do
      url "https://github.com/mcpp-community/mcpp/releases/download/v2026.7.30.2/mcpp-2026.7.30.2-linux-aarch64.tar.gz"
      sha256 "8a9f48720af833ab272aee35f51e9dc26642898e458d054093df50a33c333095"
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
