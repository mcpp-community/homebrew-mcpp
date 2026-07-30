# homebrew-mcpp

Homebrew tap for [**mcpp**](https://github.com/mcpp-community/mcpp) — a modern,
module-first C++23 build & package management tool.

```sh
brew install mcpp-community/mcpp/mcpp-m
```

That single command taps this repository and installs mcpp; no separate
`brew tap` step is needed. After the tap exists, the short forms work too:

```sh
brew install mcpp-m        # the formula
brew install mcpp-bin      # alias
mcpp --version             # the command is always `mcpp`
```

Upgrades and removal are the usual `brew upgrade mcpp-m` / `brew uninstall mcpp-m`.

## Why `mcpp-m` and not `mcpp`

`mcpp` in homebrew-core is [Matsui's C preprocessor](https://formulae.brew.sh/formula/mcpp),
an unrelated project that has held the name for years. A tap cannot take a name
that core already owns without the two sharing a Cellar directory, so the
formula is `mcpp-m` — the same reason upstream ships `mcpp-bin` / `mcpp-m` on
the AUR rather than `mcpp`.

`Aliases/` maps both `mcpp` and `mcpp-bin` to this formula, so
`brew install mcpp-community/mcpp/mcpp` also resolves here once the tap is
installed. Plain `brew install mcpp` (unqualified) still means the
preprocessor — that name belongs to core and always will.

## What gets installed, and where

The formula ships the **prebuilt release artifacts** — byte-identical to what
upstream's `install.sh` one-liner downloads, verified against the `.sha256`
sidecars published beside them.

| Path | Contents | Owner |
| --- | --- | --- |
| `$(brew --prefix)/bin/mcpp` | launcher script | Homebrew |
| `<Cellar>/mcpp-m/<ver>/libexec/bin/mcpp` | the mcpp binary | Homebrew |
| `<Cellar>/mcpp-m/<ver>/libexec/registry/bin/xlings` | bundled xlings | Homebrew |
| `~/.mcpp/` | registry sandbox, caches, logs, **toolchains** | you |

### Why a launcher instead of a plain symlink

mcpp resolves `MCPP_HOME` from the *real* path of the running binary
(canonicalized, symlinks resolved). Linked straight into `bin`, that path is
the Cellar — so mcpp would write its registry, caches and every downloaded
toolchain into the versioned Cellar directory, and `brew upgrade` would drop
all of it on the next release.

The launcher pins the two environment knobs the binary honors, deferring to
anything you exported yourself:

```sh
export MCPP_HOME="${MCPP_HOME:-$HOME/.mcpp}"
export MCPP_VENDORED_XLINGS="${MCPP_VENDORED_XLINGS:-<libexec>/registry/bin/xlings}"
```

So per-user state lives in `~/.mcpp` and survives upgrades; `rm -rf ~/.mcpp`
resets mcpp without touching the Homebrew installation.

## Platform support

| Platform | Status |
| --- | --- |
| macOS arm64 (Apple silicon), macOS 14+ | supported |
| macOS x86_64 (Intel) | no release artifact — use [`install.sh`](https://github.com/mcpp-community/mcpp#install) or `xlings install mcpp` |
| Linux x86_64 / aarch64 (Homebrew on Linux) | supported |

The macOS binary is built with `minos 14.0`, which the formula declares as
`depends_on macos: :sonoma`.

First `mcpp build` downloads a toolchain (LLVM on macOS) into `~/.mcpp`. That
is a one-time cost per user, not per upgrade.

## Maintenance

`version`, the three `url`s and the three `sha256`s in `Formula/mcpp-m.rb` are
machine-owned — don't hand-edit them:

```sh
./scripts/update-formula.sh              # follow upstream's latest release
./scripts/update-formula.sh 2026.7.30.3  # pin an exact version
```

The script reads the `.sha256` sidecars upstream publishes (it never re-hashes
a tarball it downloaded itself, which would only attest to its own download)
and aborts rather than commit a partially-rewritten formula.

`.github/workflows/bump-formula.yml` runs it on three triggers:

| Trigger | When |
| --- | --- |
| `repository_dispatch` (`mcpp-release`) | upstream's release pipeline pings this repo the moment a release finishes |
| `schedule` (daily) | catch-up, so the tap stays current even if the upstream ping is not configured |
| `workflow_dispatch` | manual pin or re-run |

## Other ways to install mcpp

- `xlings install mcpp` — upstream's recommended path, all platforms
- `curl -fsSL https://github.com/mcpp-community/mcpp/releases/latest/download/install.sh | bash`
- Arch Linux: `yay -S mcpp-bin`

## License

The formula and scripts here are Apache-2.0, matching
[mcpp](https://github.com/mcpp-community/mcpp) itself.
