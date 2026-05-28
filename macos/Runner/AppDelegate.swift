import Cocoa
import FlutterMacOS
import app_links

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  // Finder 双击 .torrent / .metalink 或在 Finder「打开方式」里选择 aria2down 时，
  // macOS 通过 kAEOpenDocuments Apple Event 投递文件 URL，最终调用此方法。
  //
  // app_links 的 macOS 插件只订阅了 kAEGetURL（自定义 URL Scheme，如
  // aria2down:// / magnet:），不会处理 file://，因此双击 .torrent 不会触发任何
  // 反应（既不打开新建任务页，也不弹种子选择对话框）。这里把所有传入的
  // URL（含 file://）注入到 app_links 的统一管道（AppLinks.shared.handleLink），
  // 让 Dart 侧 IncomingLinkListener 走与「外部唤起」一致的流程。
  override func application(_ application: NSApplication, open urls: [URL]) {
    super.application(application, open: urls)
    for url in urls {
      AppLinks.shared.handleLink(link: url.absoluteString)
    }
  }
}
