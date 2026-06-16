# Releasing (maintainer notes)

smartcat is distributed through a Homebrew tap that lives in a separate repo:
[a0s/homebrew-smartcat](https://github.com/a0s/homebrew-smartcat). Users install
it with a single command (Homebrew auto-taps):

```
brew install a0s/smartcat/smartcat
```

The tap repo holds only `Formula/smartcat.rb`. It needs no tags - Homebrew reads
the formula from its `main` branch, and the released version is pinned inside the
formula via `url` + `sha256`. Tags live on this (source) repo only.

## Cutting a new release

1. In this repo: bump `VERSION` in `bin/smartcat`, commit, push.
2. Tag and push the tag:

   ```
   git tag v0.1.0 && git push --tags
   ```

3. Compute the tarball checksum:

   ```
   curl -sL https://github.com/a0s/smartcat/archive/refs/tags/v0.1.0.tar.gz | shasum -a 256
   ```

4. In the **homebrew-smartcat** repo, update `Formula/smartcat.rb`:
   - `url` -> the new tag's tarball;
   - `sha256` -> the checksum from step 3.

   Commit and push. Users get it via `brew update && brew upgrade smartcat`.

## Verifying the formula

```
brew audit --strict --online a0s/smartcat/smartcat
brew install a0s/smartcat/smartcat
brew test a0s/smartcat/smartcat
```
