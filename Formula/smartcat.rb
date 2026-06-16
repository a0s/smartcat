class Smartcat < Formula
  desc "Context-aware cat that renders Markdown, images and code in your terminal"
  homepage "https://github.com/a0s/smartcat"
  url "https://github.com/a0s/smartcat/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"
  license "MIT"
  head "https://github.com/a0s/smartcat.git", branch: "main"

  def install
    bin.install "bin/smartcat"
    pkgshare.install "share/smartcat/config.default.yaml"
    (pkgshare/"init").install Dir["share/smartcat/init/*"]
  end

  def caveats
    <<~EOS
      smartcat ships with no required dependencies. For the best experience,
      install the optional viewers it knows about:

        brew install glow bat chafa

      Inline images use iTerm2's imgcat, available after:
        iTerm2 -> Install Shell Integration

      To make `cat` smart in interactive shells (safe: pipes and scripts are
      untouched), add this to your ~/.zshrc:

        eval "$(smartcat init zsh)"

      To customize file-type handlers, copy the default config and edit it:

        mkdir -p "${XDG_CONFIG_HOME:-$HOME/.config}/smartcat"
        cp "#{pkgshare}/config.default.yaml" \\
           "${XDG_CONFIG_HOME:-$HOME/.config}/smartcat/config.yaml"
    EOS
  end

  test do
    assert_match "smartcat #{version}", shell_output("#{bin}/smartcat --version")

    (testpath/"sample.md").write("# Title\nbody\n")
    piped = pipe_output("#{bin}/smartcat #{testpath}/sample.md")
    assert_equal File.read(testpath/"sample.md"), piped

    assert_match "command smartcat", shell_output("#{bin}/smartcat init zsh")
  end
end
