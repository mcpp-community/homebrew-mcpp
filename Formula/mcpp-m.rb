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
  version "2026.11.12.1"
  license "Apache-2.0"

  # mcpp keeps its package index in sync over git.
  depends_on "git"

  on_macos do
    # Upstream publishes an arm64-only macOS artifact, built with minos 14.0
    # (release.yml asserts it). Intel Macs have no asset — build from source
    # via `xlings install mcpp` or the install.sh one-liner instead.
    depends_on arch: :arm64
    depends_on macos: :sonoma

    url "https://github.com/mcpp-community/mcpp/releases/download/v2026.11.12.1/mcpp-2026.11.12.1-macosx-arm64.tar.gz"
    sha256 "b6eb70d0a51033b9ddb66d148cf16956f353aac42994ba4577cad959ade7c006"
  end

  on_linux do
    on_intel do
      url "https://github.com/mcpp-community/mcpp/releases/download/v2026.11.12.1/mcpp-2026.11.12.1-linux-x86_64.tar.gz"
      sha256 "c94fed472ad608943b19a347758da31a345bdfe156ecfd4e539dcd958d83c7a7"
    end
    on_arm do
      url "https://github.com/mcpp-community/mcpp/releases/download/v2026.11.12.1/mcpp-2026.11.12.1-linux-aarch64.tar.gz"
      sha256 "e138429b58763681b90d3a4d9554d894f78b0ea36c3356c2c75c2df413b1c84a"
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

      Homebrew 6 gates third-party taps. You reached this formula through a
      fully-qualified name, which Homebrew reads as explicit intent — but
      `brew install mcpp-m`, `brew install mcpp-community/mcpp/mcpp` and
      `brew upgrade mcpp-m` are refused as "untrusted tap" until you run:

        brew trust mcpp-community/mcpp
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
