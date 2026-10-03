cask "deft" do
  version "1.3.3"
  sha256 "8aeb27c110a107c41528d9ca1be665631b939768fa586d207a5fb435e81a8f81"

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
