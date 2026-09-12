import Foundation

let root = FileManager.default.currentDirectoryPath
let macIconPath = "\(root)/mac/build/icon.png"
let assetsDir = "\(root)/ios/Journal/Assets.xcassets"
let appIconDir = "\(assetsDir)/AppIcon.appiconset"
let appLogoDir = "\(assetsDir)/AppLogo.imageset"

try FileManager.default.createDirectory(atPath: appIconDir, withIntermediateDirectories: true)
try FileManager.default.createDirectory(atPath: appLogoDir, withIntermediateDirectories: true)

// 1. Assets.xcassets Contents.json
let rootContents = """
{
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
"""
try rootContents.write(toFile: "\(assetsDir)/Contents.json", atomically: true, encoding: .utf8)

// 2. Direct byte-for-byte copy of mac/build/icon.png to AppIcon-1024.png
let appIconPath = "\(appIconDir)/AppIcon-1024.png"
let rawIconData = try Data(contentsOf: URL(fileURLWithPath: macIconPath))
try rawIconData.write(to: URL(fileURLWithPath: appIconPath))
print("Copied \(macIconPath) -> \(appIconPath) (\(rawIconData.count) bytes)")

// 3. AppIcon Contents.json
let appIconContents = """
{
  "images" : [
    {
      "filename" : "AppIcon-1024.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
"""
try appIconContents.write(toFile: "\(appIconDir)/Contents.json", atomically: true, encoding: .utf8)

// 4. Direct byte-for-byte copy of mac/build/icon.png to AppLogo.imageset
let logoPath = "\(appLogoDir)/AppLogo.png"
try rawIconData.write(to: URL(fileURLWithPath: logoPath))
print("Copied \(macIconPath) -> \(logoPath) (\(rawIconData.count) bytes)")

let appLogoContents = """
{
  "images" : [
    {
      "filename" : "AppLogo.png",
      "idiom" : "universal",
      "scale" : "1x"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
"""
try appLogoContents.write(toFile: "\(appLogoDir)/Contents.json", atomically: true, encoding: .utf8)

print("Icon successfully propagated everywhere from \(macIconPath)!")
