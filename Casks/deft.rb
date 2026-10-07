cask "deft" do
  version "1.3.6"
  sha256 "13008db97e695894de939df5ac16b9df2d21492be672e129f65ce3f1d213edb1"

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
