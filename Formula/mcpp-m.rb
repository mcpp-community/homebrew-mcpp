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
  version "2026.8.3.3"
  license "Apache-2.0"

  # mcpp keeps its package index in sync over git.
  depends_on "git"

  on_macos do
    # Upstream publishes an arm64-only macOS artifact, built with minos 14.0
    # (release.yml asserts it). Intel Macs have no asset — build from source
    # via `xlings install mcpp` or the install.sh one-liner instead.
    depends_on arch: :arm64
    depends_on macos: :sonoma

    url "https://github.com/mcpp-community/mcpp/releases/download/v2026.8.3.3/mcpp-2026.8.3.3-macosx-arm64.tar.gz"
    sha256 "4c477842f179375333825fdd5335d5892502b71faaa88cbdf5ba2aee05eabb62"
  end

  on_linux do
    on_intel do
      url "https://github.com/mcpp-community/mcpp/releases/download/v2026.8.3.3/mcpp-2026.8.3.3-linux-x86_64.tar.gz"
      sha256 "e430f7fea648ec38c949f41a57b53c6f387aecf9f5123aa259b04e4ae36aa316"
    end
    on_arm do
      url "https://github.com/mcpp-community/mcpp/releases/download/v2026.8.3.3/mcpp-2026.8.3.3-linux-aarch64.tar.gz"
      sha256 "3fa085fb04341d1f984540f70d39d60bb44f12dea7d695454bd44e2c725bee6c"
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
    #
    # bin.mkpath first: nothing has created <prefix>/bin at this point (the
    # payload went to libexec), and Homebrew's Pathname#write does not make
    # parent directories — write_env_script mkpaths by hand for this reason.
    bin.mkpath
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
