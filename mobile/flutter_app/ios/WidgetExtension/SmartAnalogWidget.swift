import SwiftUI
import WidgetKit

private let widgetKind = "SmartAnalogWidget"
private let widgetReadFileName = "widget_snapshot_read_v1.json"
private let widgetReadDirectory = "snapshots"
private let widgetAppGroup = "group.com.smartanalog.flutterApp"

struct SmartAnalogWidgetEntry: TimelineEntry {
  let date: Date
  let displayDate: String
  let timezone: String
  let generatedAt: String
  let eventCount: Int
}

struct SmartAnalogWidgetProvider: TimelineProvider {
  func placeholder(in context: Context) -> SmartAnalogWidgetEntry {
    SmartAnalogWidgetEntry(
      date: Date(),
      displayDate: "-",
      timezone: "-",
      generatedAt: "-",
      eventCount: 0
    )
  }

  func getSnapshot(in context: Context, completion: @escaping (SmartAnalogWidgetEntry) -> Void) {
    completion(loadEntry())
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<SmartAnalogWidgetEntry>) -> Void) {
    let entry = loadEntry()
    let nextRefresh = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
    completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
  }

  private func loadEntry() -> SmartAnalogWidgetEntry {
    guard
      let root = loadRootJson(),
      let snapshot = root["snapshot"] as? [String: Any]
    else {
      return SmartAnalogWidgetEntry(
        date: Date(),
        displayDate: "No snapshot",
        timezone: "Unknown",
        generatedAt: "Unknown",
        eventCount: 0
      )
    }

    let events = snapshot["events"] as? [[String: Any]] ?? []
    return SmartAnalogWidgetEntry(
      date: Date(),
      displayDate: snapshot["date"] as? String ?? "Unknown",
      timezone: snapshot["timezone"] as? String ?? "Unknown",
      generatedAt: root["generated_at"] as? String ?? "Unknown",
      eventCount: events.count
    )
  }

  private func loadRootJson() -> [String: Any]? {
    guard
      let appGroupUrl = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: widgetAppGroup
      )
    else {
      return nil
    }

    let snapshotFileUrl = appGroupUrl
      .appendingPathComponent(widgetReadDirectory, isDirectory: true)
      .appendingPathComponent(widgetReadFileName)

    guard
      let data = try? Data(contentsOf: snapshotFileUrl),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      return nil
    }

    return json
  }
}

struct SmartAnalogWidgetEntryView: View {
  let entry: SmartAnalogWidgetProvider.Entry

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Smart Analog")
        .font(.headline)
      Text(entry.displayDate)
        .font(.subheadline)
      Text("\(entry.timezone) | events \(entry.eventCount)")
        .font(.caption)
        .foregroundColor(.secondary)
      Text("updated: \(entry.generatedAt)")
        .font(.caption2)
        .foregroundColor(.secondary)
        .lineLimit(1)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .padding(12)
  }
}

struct SmartAnalogWidget: Widget {
  let kind: String = widgetKind

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: SmartAnalogWidgetProvider()) { entry in
      SmartAnalogWidgetEntryView(entry: entry)
    }
    .configurationDisplayName("Smart Analog")
    .description("Displays the latest Smart Analog snapshot.")
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
  }
}

@main
struct SmartAnalogWidgetBundle: WidgetBundle {
  var body: some Widget {
    SmartAnalogWidget()
  }
}
