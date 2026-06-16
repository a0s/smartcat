# Releasing (maintainer notes)

## Cutting a release

1. Tag a stable release and push the tag:

   ```
   git tag v0.1.0 && git push --tags
   ```

2. Update the formula's `url` and `sha256` in `Formula/smartcat.rb`
   (`brew fetch` prints the checksum for the release tarball).

## Submitting to homebrew-core

Once the project is notable enough to qualify:

1. Ensure `brew audit --strict --new smartcat` and `brew test smartcat` pass.
2. Open a pull request against `Homebrew/homebrew-core`.

After it merges, `brew install smartcat` works for everyone with no tap.
