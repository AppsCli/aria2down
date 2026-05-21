import Flutter
import UIKit
import BackgroundTasks

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var bgTask: UIBackgroundTaskIdentifier = .invalid
  private static let bgRefreshId = "cloud.iothub.aria2down.bgrefresh"
  private static let bgProcessingId = "cloud.iothub.aria2down.bgprocessing"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // 注册两类后台任务标识，与 Info.plist
    // `BGTaskSchedulerPermittedIdentifiers` 对应。任务仅负责让 libaria2
    // 在应用挂起期间获得短暂 CPU 时间；实际下载由 worker isolate 推进。
    if #available(iOS 13.0, *) {
      BGTaskScheduler.shared.register(forTaskWithIdentifier: AppDelegate.bgRefreshId, using: nil) { task in
        self.handleAppRefresh(task: task as! BGAppRefreshTask)
      }
      BGTaskScheduler.shared.register(forTaskWithIdentifier: AppDelegate.bgProcessingId, using: nil) { task in
        self.handleProcessing(task: task as! BGProcessingTask)
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // MARK: - Background tasks

  override func applicationDidEnterBackground(_ application: UIApplication) {
    super.applicationDidEnterBackground(application)
    beginExtendedBackground(application)
    scheduleAppRefresh()
    scheduleProcessing()
  }

  override func applicationWillEnterForeground(_ application: UIApplication) {
    super.applicationWillEnterForeground(application)
    endExtendedBackground(application)
  }

  private func beginExtendedBackground(_ application: UIApplication) {
    endExtendedBackground(application)
    bgTask = application.beginBackgroundTask(withName: "aria2down.keepalive") { [weak self] in
      guard let self = self else { return }
      self.endExtendedBackground(application)
    }
  }

  private func endExtendedBackground(_ application: UIApplication) {
    guard bgTask != .invalid else { return }
    application.endBackgroundTask(bgTask)
    bgTask = .invalid
  }

  @available(iOS 13.0, *)
  private func scheduleAppRefresh() {
    let request = BGAppRefreshTaskRequest(identifier: AppDelegate.bgRefreshId)
    request.earliestBeginDate = Date(timeIntervalSinceNow: 60)
    do {
      try BGTaskScheduler.shared.submit(request)
    } catch {
      NSLog("aria2down: BGAppRefresh submit failed: \(error)")
    }
  }

  @available(iOS 13.0, *)
  private func scheduleProcessing() {
    let request = BGProcessingTaskRequest(identifier: AppDelegate.bgProcessingId)
    request.requiresNetworkConnectivity = true
    request.requiresExternalPower = false
    request.earliestBeginDate = Date(timeIntervalSinceNow: 120)
    do {
      try BGTaskScheduler.shared.submit(request)
    } catch {
      NSLog("aria2down: BGProcessing submit failed: \(error)")
    }
  }

  @available(iOS 13.0, *)
  private func handleAppRefresh(task: BGAppRefreshTask) {
    scheduleAppRefresh()
    task.expirationHandler = { task.setTaskCompleted(success: false) }
    // libaria2 由 worker isolate 维护事件循环；后台被唤醒时给系统一个
    // 短暂的窗口让 isolate 跑几个 RUN_ONCE 即可。
    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
      task.setTaskCompleted(success: true)
    }
  }

  @available(iOS 13.0, *)
  private func handleProcessing(task: BGProcessingTask) {
    scheduleProcessing()
    task.expirationHandler = { task.setTaskCompleted(success: false) }
    DispatchQueue.main.asyncAfter(deadline: .now() + 25.0) {
      task.setTaskCompleted(success: true)
    }
  }
}
