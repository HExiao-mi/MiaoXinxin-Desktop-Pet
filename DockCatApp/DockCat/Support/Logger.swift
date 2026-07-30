import Foundation
import os

enum DockCatLog {
    static let app = Logger(subsystem: "com.miaoxinxin.DockPet", category: "App")
    static let assets = Logger(subsystem: "com.miaoxinxin.DockPet", category: "Assets")
    static let state = Logger(subsystem: "com.miaoxinxin.DockPet", category: "State")
}
