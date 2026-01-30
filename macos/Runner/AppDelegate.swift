import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationDidFinishLaunching(_ notification: Notification) {
    guard let window = mainFlutterWindow else {
      super.applicationDidFinishLaunching(notification)
      return
    }
    
    let controller: FlutterViewController = window.contentViewController as! FlutterViewController
    
    // Register plugins
    RegisterGeneratedPlugins(registry: controller)
    
    super.applicationDidFinishLaunching(notification)
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
