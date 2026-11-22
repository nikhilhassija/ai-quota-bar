cask "ai-quota-bar" do
  version "1.0.2"
  sha256 "d98519f2ac34480f5b7052e2e743db44c21106156fc1531fbbe9b252541cb569"

  url "https://github.com/nikhilhassija/ai-quota-bar/releases/download/v#{version}/AIQuotaBar.zip"
  name "AIQuotaBar"
  desc "Lightweight native macOS menu bar quota tracker for Claude, Antigravity, and Codex"
  homepage "https://github.com/nikhilhassija/ai-quota-bar"

  depends_on macos: ">= :ventura"

  app "AIQuotaBar.app"

  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-dr", "com.apple.quarantine", "#{appdir}/AIQuotaBar.app"],
                   sudo: false
  end

  uninstall quit: "local.nikhil.AIQuotaBar"

  zap trash: [
    "~/Library/Preferences/local.nikhil.AIQuotaBar.plist",
    "~/Library/LaunchAgents/com.local.AIQuotaBar.plist",
  ]
end
