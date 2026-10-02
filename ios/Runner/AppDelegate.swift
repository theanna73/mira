import Flutter
import UIKit
import UserNotifications
import EventKit
import EventKitUI

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var calendarBridge: CalendarBridge?
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    GeneratedPluginRegistrant.register(with: self)
    if let controller = window?.rootViewController as? FlutterViewController {
      calendarBridge = CalendarBridge(controller: controller)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}

private final class CalendarBridge: NSObject, EKEventEditViewDelegate {
  private let channel: FlutterMethodChannel
  private weak var controller: UIViewController?
  private var pending: FlutterResult?
  init(controller: FlutterViewController) {
    self.controller = controller
    channel = FlutterMethodChannel(name: "app.mira/calendar", binaryMessenger: controller.binaryMessenger)
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(FlutterError(code: "UNAVAILABLE", message: "Календарь недоступен", details: nil)); return }
      guard call.method == "add" else { result(FlutterMethodNotImplemented); return }
      guard self.pending == nil else { result(FlutterError(code: "BUSY", message: "Редактор календаря уже открыт", details: nil)); return }
      guard let args = call.arguments as? [String: Any],
        let title = args["title"] as? String, !title.isEmpty,
        let start = args["start"] as? NSNumber, let end = args["end"] as? NSNumber,
        end.doubleValue > start.doubleValue else {
          result(FlutterError(code: "INVALID_EVENT", message: "Некорректное событие", details: nil)); return
      }
      self.pending = result
      let store = EKEventStore()
      let event = EKEvent(eventStore: store)
      event.title = title
      event.notes = args["notes"] as? String
      event.location = args["location"] as? String
      event.startDate = Date(timeIntervalSince1970: start.doubleValue / 1000)
      event.endDate = Date(timeIntervalSince1970: end.doubleValue / 1000)
      if #available(iOS 17.0, *) {
        // EventKitUI manages authorization; the app does not read the user's calendar.
        self.present(event: event, store: store)
      } else {
        store.requestAccess(to: .event) { granted, _ in
          DispatchQueue.main.async {
            if granted { self.present(event: event, store: store) }
            else {
              self.pending?(FlutterError(code: "DENIED", message: "Доступ к календарю не выдан", details: nil))
              self.pending = nil
            }
          }
        }
      }
    }
  }
  private func present(event: EKEvent, store: EKEventStore) {
    guard let controller = controller, controller.presentedViewController == nil else {
      pending?(FlutterError(code: "BUSY", message: "Закройте другое окно и повторите", details: nil)); pending = nil; return
    }
    let editor = EKEventEditViewController()
    editor.eventStore = store
    editor.event = event
    editor.editViewDelegate = self
    controller.present(editor, animated: true)
  }
  func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
    controller.dismiss(animated: true)
    pending?(action == .saved)
    pending = nil
  }
}
