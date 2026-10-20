# Built from source, so one formula serves macOS and Linux with no bottles; the release commit bumps the tag with VERSION.
class Hop < Formula
  desc "Jump to the directory or file you mean in a repo, with fzf"
  homepage "https://github.com/etknorr/hop"
  url "https://github.com/etknorr/hop.git", tag: "v1.0.0"
  license "MIT"
  head "https://github.com/etknorr/hop.git", branch: "main"

  depends_on "go" => :build
  depends_on "fzf"

  def install
    ldflags = "-s -w -X github.com/etknorr/hop/internal/version.Version=#{version}"
    system "go", "build", *std_go_args(ldflags:)
    pkgshare.install "config.example.toml", "workspaces.example"
  end

  def caveats
    <<~EOS
      Add hop to your shell, after compinit for zsh:
        zsh:  eval "$(hop init zsh)"
        bash: eval "$(hop init bash)"
        fish: hop init fish | source

      Example config and workspaces files to copy into ~/.config/hop:
        #{opt_pkgshare}/config.example.toml
        #{opt_pkgshare}/workspaces.example
    EOS
  end

  test do
    assert_match "hop #{version}", shell_output("#{bin}/hop -V")
    assert_match "hopr", shell_output("#{bin}/hop init zsh")
    assert_path_exists pkgshare/"config.example.toml"
    system "git", "init", "-q", testpath/"repo"
    (testpath/"repo/api/README.md").write "api\n"
    system "git", "-C", testpath/"repo", "add", "-A"
    cd testpath/"repo" do
      assert_equal (testpath/"repo/api").realpath.to_s, shell_output("#{bin}/hop api").strip
    end
  end
end
