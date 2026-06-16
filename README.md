# smartcat

<p align="center">
  <img src="images/banner.webp" alt="smartcat - a context-aware cat that renders Markdown, images, PDFs and code right in your terminal" width="100%">
</p>

**Make `cat` smart - transparently.** Keep typing `cat` exactly as you always
have. When you're a human looking at a single file in a terminal, it renders the
file the way you'd want - Markdown, images, code, data. The instant the output
goes to a pipe, a file, multiple files, a flag, or a script, it's the ordinary
`cat` again - **byte for byte**. Nothing breaks.

```
cat README.md          # rendered Markdown
cat diagram.png        # inline image (iTerm2)
cat main.py            # syntax-highlighted code
cat data.json          # pretty data

cat file.md | grep x   # raw bytes - exactly like before
cat a.txt b.txt        # plain cat, untouched
cat -n file            # plain cat, untouched
```

That's the whole pitch: a `cat` that's nicer for you and invisible to everything
else. No retraining your fingers, no broken scripts.

> Under the hood the tool is a command named `smartcat`. The transparent `cat`
> behavior is an opt-in shell shim you enable with one line (see
> [Make `cat` smart](#make-cat-smart-opt-in)). Once enabled, `cat` and
> `smartcat` are interchangeable - the examples below use whichever reads best.

## Why it is safe

The smart path activates only when **all** of these are true:

- stdout is a terminal (`[ -t 1 ]`), not a pipe or a file;
- exactly one argument was given;
- that argument is a readable regular file, not a flag.

Otherwise it `exec`s the real `cat` with your arguments untouched - so
`cat a b c`, `cat -n file`, `cat < file`, and `cat file | tool` all keep working
byte-for-byte. The shim lives only in your interactive shell, so `cron` jobs and
`sh script.sh` never even see it.

smartcat doesn't render anything itself - it hands each file to a real viewer
(`glow`, `bat`, `imgcat`, and friends) and steps aside. It installs with no
dependencies, but it's only as useful as the viewers you have: a file type with
no viewer installed just falls back to plain `cat` and prints a one-line hint
about what to install. So grab the renderers for the types you care about - see
[Renderers](#renderers) below.

## Forcing the plain cat

Pass `-native` (or `--native`) as the **first** argument to bypass rendering and
run the vanilla `cat` with the remaining arguments - even on a single file in an
interactive terminal:

```
cat -native README.md       # raw, no Markdown rendering
cat -native -n file.md      # remaining args go straight to cat
```

It must come first, because it is a smartcat directive, not a `cat` flag.

## Inspecting handlers

`cat -status` (or `cat --status`) prints a table of every known file type, the
renderer chain for it, which renderers are installed (`+`/`-`), and the active
one that will actually run. Missing renderers are listed with their install hint:

```
cat -status
```

```
TYPE      ACTIVE  RENDERERS (+ installed)  EXTENSIONS
markdown  glow    glow(+) mdcat(-) bat(+)  md, markdown, mdown, mkd, mkdn
image     imgcat  imgcat(+) chafa(-)       png, jpg, jpeg, gif, webp, ...
pdf       mutool  pdftotext(-) mutool(+)   pdf
...
```

## Install

```
brew install a0s/smartcat/smartcat
```

### Renderers

These are what actually render your files. Install the ones for the types you
use and skip the rest - anything without a renderer falls back to plain `cat`.

```
brew install glow       # Markdown
brew install bat        # code, JSON/YAML/CSV, syntax highlighting
brew install poppler    # PDF (text)
brew install chafa      # images, when you're not in iTerm2
```

In iTerm2 images render with its built-in `imgcat` - turn it on via
**iTerm2 → Install Shell Integration** (no brew package needed).

Run `cat -status` to see what's covered and what's missing.

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

1. **By extension first** - the file's lowercase extension is matched against
   the `extensions` list of each handler. This is predictable, fast, and fully
   controlled by your config.
2. **By MIME as a fallback** - for files with no extension or an unknown one,
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

- **`extensions`** - file extensions (without the dot) this handler claims.
- **`mime`** - optional MIME patterns for the `file`-based fallback. `*` is a
  wildcard, e.g. `image/*`.
- **`commands`** - an ordered fallback chain. `smartcat` runs the first command
  whose program is installed. `{file}` is replaced with the file path.
- **`hint`** - shown to stderr when none of the commands are installed.

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
fallbacks - the first installed one wins.

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
