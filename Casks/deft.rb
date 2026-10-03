cask "deft" do
  version "1.3.4"
  sha256 "77b89ebc8e0fc24fa23842fa83329d53b6e152ceb40f3788dd448a319ce1aa77"

  url "https://github.com/ninjait07/deft/releases/download/v#{version}/Deft-#{version}.dmg"
  name "Deft"
  desc "Windows-style window management and keyboard for macOS"
  homepage "https://github.com/ninjait07/deft"

  depends_on macos: :ventura

  app "Deft.app"

  zap trash: [
    "~/Library/Logs/Deft.log",
    "~/Library/Preferences/com.nonbannawat.deft.plist",
  ]
end
