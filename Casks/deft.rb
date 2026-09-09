cask "deft" do
  version "1.2"
  sha256 "f1bab318671e4b1c4169f6ed9869e8f886afd0afe3374a05fb46d0f7f6f420ac"

  url "https://github.com/ninjait07/deft/releases/download/v#{version}/Deft-#{version}.dmg"
  name "Deft"
  desc "Windows-style window management and keyboard for macOS"
  homepage "https://github.com/ninjait07/deft"

  depends_on macos: ">= :ventura"

  app "Deft.app"

  zap trash: [
    "~/Library/Logs/Deft.log",
    "~/Library/Preferences/com.nonbannawat.deft.plist",
  ]
end
