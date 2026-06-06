import UIKit

/// iOS 应用伪装：切换备用图标（名称无法动态修改）
final class DisguiseManager {
  static let shared = DisguiseManager()

  private let map: [String: String?] = [
    "original": nil,
    "calculator": "DisguiseCalculator",
    "weather": "DisguiseWeather",
    "notes": "DisguiseNotes",
    "settings": "DisguiseSettings",
    "album": "DisguiseAlbum",
    "gallery": "DisguiseGallery",
    "phone": "DisguisePhone",
  ]

  func current() -> String {
    guard UIApplication.shared.supportsAlternateIcons else { return "original" }
    let name = UIApplication.shared.alternateIconName
    if name == nil { return "original" }
    for (id, icon) in map where icon == name {
      return id
    }
    return "original"
  }

  func apply(id: String, completion: @escaping (Bool) -> Void) {
    guard UIApplication.shared.supportsAlternateIcons else {
      completion(false)
      return
    }
    let iconName = map[id] ?? nil
    UIApplication.shared.setAlternateIconName(iconName) { error in
      completion(error == nil)
    }
  }
}
