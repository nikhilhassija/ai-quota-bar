cask "ai-quota-bar" do
  version "1.0.1"
  sha256 "7529f0c38e4d264d739235cad18f50596f5ba0bd8c313cd7918ca778aaf4cdc0"

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
