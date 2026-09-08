cask "deft" do
  version "1.0"
  sha256 "4aa9b7d99f261e1560d7219764c7213f51ce7d55811175a908b7be185117b8a4"

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
