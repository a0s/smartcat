# smartcat

A context-aware `cat` for macOS terminals (iTerm2 and friends).

When you run it interactively on a single file, `smartcat` renders it with the
right viewer — Markdown through `glow`, images through `imgcat`, source code
through `bat`, and so on. In every other case it behaves **exactly** like the
plain `cat`, so pipes, redirects, multiple files, flags, and scripts are never
affected.

```
smartcat README.md          # rendered Markdown
smartcat diagram.png        # inline image (iTerm2)
smartcat main.py            # syntax-highlighted code
smartcat data.json          # pretty data
smartcat file.md | grep x   # raw bytes, just like cat
smartcat -native README.md  # force the plain cat, no rendering
```

## Why it is safe

`smartcat` only switches to a viewer when **all** of these are true:

- stdout is a terminal (`[ -t 1 ]`), not a pipe or a file;
- it received exactly one argument;
- that argument is a readable regular file, not a flag.

Otherwise it `exec`s the real `cat` with your arguments untouched. That means
scripts, `cat a b c`, `cat -n file`, `cat < file`, and `cat file | tool` all
keep working byte-for-byte.

There are **no required dependencies**. If a file type has no installed viewer,
`smartcat` prints a short hint to stderr (e.g. `brew install glow`) and falls
back to plain `cat`, so you still see the content.

## Forcing the plain cat

Pass `-native` (or `--native`) as the **first** argument to bypass all rendering
and run the vanilla `cat` with the remaining arguments — even on a single file in
an interactive terminal:

```
smartcat -native README.md       # raw, no Markdown rendering
cat -native README.md            # same, when the cat shim is enabled
smartcat -native -n file.md      # remaining args go straight to cat
```

It must come first, because it is a smartcat directive rather than a `cat` flag.

## Inspecting handlers

`smartcat status` (or `--status`) prints a table of every known file type, the
renderer chain for it, which renderers are installed (`+`/`-`), and the active
one that will actually run. Missing renderers are listed with their install hint:

```
smartcat status
```

```
TYPE      ACTIVE  RENDERERS (+ installed)  EXTENSIONS
markdown  glow    glow(+) mdcat(-) bat(+)  md, markdown, mdown, mkd, mkdn
image     imgcat  imgcat(+) chafa(-)       png, jpg, jpeg, gif, webp, ...
pdf       mutool  pdftotext(-) mutool(+)   pdf
...
```

## Install

### Homebrew (recommended)

Before the formula is in homebrew-core, install it from the tap:

```
brew tap a0s/smartcat https://github.com/a0s/homebrew-smartcat
brew install a0s/smartcat/smartcat
```

Install the latest `main` without a tagged release:

```
brew install --HEAD a0s/smartcat/smartcat
```

Build straight from a local checkout of this repo:

```
brew install --build-from-source ./Formula/smartcat.rb
```

After the formula is accepted into homebrew-core, this is all you need:

```
brew install smartcat
```

### Optional viewers

`smartcat` works without them, but they make it shine:

```
brew install glow bat chafa
```

For inline images, enable iTerm2 shell integration: **iTerm2 → Install Shell
Integration** (this provides `imgcat`).

## Make `cat` smart (opt-in)

`smartcat` never touches `cat` on its own. To route interactive `cat` through
it, add one line to your `~/.zshrc`:

```zsh
eval "$(smartcat init zsh)"
```

(`smartcat init bash` is also available.) Reload with `source ~/.zshrc`. Now
`cat README.md` renders, while `cat README.md | grep x` and any script using
`cat` stay exactly as before. Remove the line to undo it completely.

## How file-type detection works

1. **By extension first** — the file's lowercase extension is matched against
   the `extensions` list of each handler. This is predictable, fast, and fully
   controlled by your config.
2. **By MIME as a fallback** — for files with no extension or an unknown one,
   `smartcat` consults `file --mime-type` (built into macOS, not a dependency)
   and matches it against each handler's optional `mime` patterns.

## Configuration

The config is a YAML file. Resolution order:

1. `$SMARTCAT_CONFIG`
2. `${XDG_CONFIG_HOME:-$HOME/.config}/smartcat/config.yaml`
3. the bundled default at `<brew-prefix>/share/smartcat/config.default.yaml`

Copy the default to start customizing:

```
mkdir -p "${XDG_CONFIG_HOME:-$HOME/.config}/smartcat"
cp "$(brew --prefix)/share/smartcat/config.default.yaml" \
   "${XDG_CONFIG_HOME:-$HOME/.config}/smartcat/config.yaml"
```

### Schema

```yaml
handlers:
  markdown:
    extensions: [md, markdown]
    mime: [text/markdown]
    commands:
      - glow {file}
      - bat --style=plain --paging=never {file}
    hint: "For rendered Markdown: brew install glow (or bat)"
```

- **`extensions`** — file extensions (without the dot) this handler claims.
- **`mime`** — optional MIME patterns for the `file`-based fallback. `*` is a
  wildcard, e.g. `image/*`.
- **`commands`** — an ordered fallback chain. `smartcat` runs the first command
  whose program is installed. `{file}` is replaced with the file path.
- **`hint`** — shown to stderr when none of the commands are installed.

### Adding a new file type

```yaml
handlers:
  notebook:
    extensions: [ipynb]
    commands:
      - jupytext --to markdown -o - {file}
      - bat --style=plain --paging=never {file}
    hint: "For notebooks: brew install jupytext (or bat)"
```

One viewer can serve many extensions, and one type can list several viewers as
fallbacks — the first installed one wins.

### Supported YAML subset

The bundled parser needs no external tools and understands a small, documented
subset of YAML:

- a top-level `handlers:` map;
- each handler name indented by **2 spaces**, ending with `:`;
- handler keys indented by **4 spaces**;
- `extensions` and `mime` as inline lists: `[a, b, c]`;
- `commands` as a block list, each item indented by **6 spaces**: `- cmd`;
- `hint` as a scalar (quotes optional);
- `#` comment lines and blank lines are ignored.

## Uninstall

```
brew uninstall smartcat
```

Then remove the `eval "$(smartcat init zsh)"` line from your `~/.zshrc` and,
optionally, `~/.config/smartcat`.

## Development

`smartcat` is a single bash script (`bin/smartcat`) with a YAML config parsed by
an embedded awk reader. To hack on it without installing, put `bin` on your PATH
and enable the shim:

```zsh
export PATH="$PWD/bin:$PATH"
eval "$(smartcat init zsh)"
```

### Tests

A self-contained, dependency-free test suite lives in `test/run.sh`. It exercises
the no-TTY passthrough paths directly and the interactive rendering paths through
a pseudo-terminal (`script`) with fake renderers on PATH, so assertions are
deterministic regardless of what is actually installed.

```
./test/run.sh
```

It covers passthrough byte-equality with `cat`, renderer selection and fallback
chains, extension and MIME detection, the `-native` override, the install-hint
fallback, config resolution, and a regression test ensuring the chosen renderer
never receives the command list on stdin. To run the suite against an alternate
binary, set `SMARTCAT_BIN`.

## Publishing to homebrew-core

Once the project is notable enough, submit the formula to homebrew-core:

1. Tag a stable release (`git tag v1.0.0 && git push --tags`) and update the
   formula's `url` and `sha256` (`brew fetch` prints the checksum).
2. Ensure `brew audit --strict --new smartcat` and `brew test smartcat` pass.
3. Open a pull request against `Homebrew/homebrew-core`. After it merges,
   `brew install smartcat` works for everyone with no tap.

## License

MIT — see [LICENSE](LICENSE).
