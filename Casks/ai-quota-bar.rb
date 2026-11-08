cask "ai-quota-bar" do
  version "1.0.0"
  sha256 "8e6d60263650be389cd4df3869af94fdd9da31a8a9f3848c52cc7949eab52e67"

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
