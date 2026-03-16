import SwiftUI
import WidgetKit

private let widgetKind = "SmartAnalogWidget"
private let widgetReadFileName = "widget_snapshot_read_v1.json"
private let widgetReadDirectory = "snapshots"
private let widgetAppGroup = "group.com.smartanalog.flutterApp"

struct ClockSegment: Hashable {
  let startAngleDeg: Double
  let sweepAngleDeg: Double
  let colorHex: String
}

struct WidgetEventPreview: Hashable, Identifiable {
  let id: String
  let title: String
  let startTime: Date?
  let endTime: Date?
  let allDay: Bool
  let colorHex: String
}

struct SmartAnalogWidgetEntry: TimelineEntry {
  let date: Date
  let displayDate: String
  let timezone: String
  let generatedAt: String
  let eventCount: Int
  let theme: String
  let segments: [ClockSegment]
  let events: [WidgetEventPreview]
}

struct SmartAnalogWidgetProvider: TimelineProvider {
  private let timelineStepMinutes = 1
  private let timelineHorizonMinutes = 60

  func placeholder(in context: Context) -> SmartAnalogWidgetEntry {
    SmartAnalogWidgetEntry(
      date: Date(),
      displayDate: "-",
      timezone: "-",
      generatedAt: "-",
      eventCount: 0,
      theme: "dark",
      segments: [],
      events: []
    )
  }

  func getSnapshot(in context: Context, completion: @escaping (SmartAnalogWidgetEntry) -> Void) {
    completion(loadBaseEntry(date: Date()))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<SmartAnalogWidgetEntry>) -> Void) {
    let baseDate = Date()
    let baseEntry = loadBaseEntry(date: baseDate)
    var entries: [SmartAnalogWidgetEntry] = []
    for minuteOffset in 0..<timelineHorizonMinutes {
      let date =
        Calendar.current.date(byAdding: .minute, value: minuteOffset * timelineStepMinutes, to: baseDate)
        ?? baseDate
      entries.append(
        SmartAnalogWidgetEntry(
          date: date,
          displayDate: baseEntry.displayDate,
          timezone: baseEntry.timezone,
          generatedAt: baseEntry.generatedAt,
          eventCount: baseEntry.eventCount,
          theme: baseEntry.theme,
          segments: baseEntry.segments,
          events: baseEntry.events
        )
      )
    }
    completion(Timeline(entries: entries, policy: .atEnd))
  }

  private func loadBaseEntry(date: Date) -> SmartAnalogWidgetEntry {
    guard
      let root = loadRootJson(),
      let snapshot = root["snapshot"] as? [String: Any]
    else {
      return SmartAnalogWidgetEntry(
        date: date,
        displayDate: "No snapshot",
        timezone: "Unknown",
        generatedAt: "Unknown",
        eventCount: 0,
        theme: "dark",
        segments: [],
        events: []
      )
    }

    let events = parseEvents(snapshot["events"] as? [[String: Any]])
    let style = snapshot["style"] as? [String: Any]
    let rawTheme = ((style?["theme"] as? String) ?? "dark").lowercased()
    let theme = (rawTheme == "light" || rawTheme == "white") ? "light" : "dark"
    let segmentItems = snapshot["segments"] as? [[String: Any]] ?? []
    let segments = segmentItems.map {
      ClockSegment(
        startAngleDeg: $0["start_angle_deg"] as? Double ?? 0,
        sweepAngleDeg: $0["sweep_angle_deg"] as? Double ?? 0,
        colorHex: $0["color_hex"] as? String ?? "#60A5FA"
      )
    }
    return SmartAnalogWidgetEntry(
      date: date,
      displayDate: snapshot["date"] as? String ?? "Unknown",
      timezone: snapshot["timezone"] as? String ?? "Unknown",
      generatedAt: root["generated_at"] as? String ?? "Unknown",
      eventCount: events.count,
      theme: theme,
      segments: segments,
      events: events
    )
  }

  private func parseEvents(_ rawEvents: [[String: Any]]?) -> [WidgetEventPreview] {
    let events = rawEvents ?? []
    return events
      .map { item in
        WidgetEventPreview(
          id: item["id"] as? String ?? UUID().uuidString,
          title: item["title"] as? String ?? "Untitled",
          startTime: parseIsoDate(item["start_time"] as? String),
          endTime: parseIsoDate(item["end_time"] as? String),
          allDay: item["all_day"] as? Bool ?? false,
          colorHex: item["color_hex"] as? String ?? "#64748B"
        )
      }
      .sorted {
        if $0.allDay != $1.allDay {
          return $0.allDay && !$1.allDay
        }
        let leftTime = $0.startTime ?? .distantFuture
        let rightTime = $1.startTime ?? .distantFuture
        if leftTime != rightTime {
          return leftTime < rightTime
        }
        return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
      }
  }

  private func parseIsoDate(_ value: String?) -> Date? {
    guard let value, !value.isEmpty else {
      return nil
    }

    let formatterWithFraction = ISO8601DateFormatter()
    formatterWithFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let parsed = formatterWithFraction.date(from: value) {
      return parsed
    }

    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: value)
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

struct SmartAnalogClockFace: View {
  let entry: SmartAnalogWidgetEntry

  private var palette: WidgetFacePalette {
    if entry.theme == "light" {
      return WidgetFacePalette(
        face: Color(red: 1.0, green: 1.0, blue: 1.0),
        border: Color(red: 148 / 255, green: 163 / 255, blue: 184 / 255, opacity: 0.3),
        tick: Color(red: 51 / 255, green: 65 / 255, blue: 85 / 255),
        hand: Color(red: 15 / 255, green: 23 / 255, blue: 42 / 255),
        minuteHand: Color(red: 51 / 255, green: 65 / 255, blue: 85 / 255),
        center: Color(red: 15 / 255, green: 23 / 255, blue: 42 / 255)
      )
    }
    return WidgetFacePalette(
      face: Color(red: 17 / 255, green: 24 / 255, blue: 39 / 255),
      border: Color(red: 71 / 255, green: 85 / 255, blue: 105 / 255),
      tick: Color(red: 226 / 255, green: 232 / 255, blue: 240 / 255),
      hand: .white,
      minuteHand: Color(red: 226 / 255, green: 232 / 255, blue: 240 / 255),
      center: .white
    )
  }

  var body: some View {
    GeometryReader { geometry in
      let size = min(geometry.size.width, geometry.size.height)
      let radius = size / 2
      let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
      ZStack {
        Circle()
          .fill(palette.face)
        Circle()
          .stroke(palette.border, lineWidth: radius * 0.03)

        ForEach(Array(entry.segments.enumerated()), id: \.offset) { _, segment in
          if abs(segment.sweepAngleDeg) < 0.0001 {
            zeroDurationMarker(
              radius: radius,
              angleDeg: segment.startAngleDeg,
              color: hexColor(segment.colorHex)
            )
            .position(x: center.x, y: center.y)
          } else {
            Path { path in
              path.addArc(
                center: center,
                radius: radius * 0.72,
                startAngle: .degrees(segment.startAngleDeg),
                endAngle: .degrees(segment.startAngleDeg + segment.sweepAngleDeg),
                clockwise: false
              )
            }
            .stroke(hexColor(segment.colorHex), style: StrokeStyle(lineWidth: radius * 0.18, lineCap: .round))
          }
        }

        ForEach(0..<60, id: \.self) { index in
          let angle = Angle.degrees(Double(index) * 6)
          Rectangle()
            .fill(palette.tick)
            .frame(width: radius * 0.012, height: index % 5 == 0 ? radius * 0.12 : radius * 0.06)
            .offset(y: -radius * 0.8)
            .rotationEffect(angle)
        }

        clockHand(angle: hourAngle(for: entry.date), length: radius * 0.4, width: radius * 0.06, color: palette.hand)
        clockHand(
          angle: minuteAngle(for: entry.date),
          length: radius * 0.58,
          width: radius * 0.03,
          color: palette.minuteHand
        )

        Circle()
          .fill(palette.center)
          .frame(width: radius * 0.08, height: radius * 0.08)
      }
    }
  }

  private func clockHand(angle: Angle, length: CGFloat, width: CGFloat, color: Color) -> some View {
    Rectangle()
      .fill(color)
      .frame(width: width, height: length)
      .offset(y: -length / 2)
      .rotationEffect(angle)
  }

  private func hourAngle(for date: Date) -> Angle {
    let components = Calendar.current.dateComponents([.hour, .minute], from: date)
    let hour = Double((components.hour ?? 0) % 12)
    let minute = Double(components.minute ?? 0)
    return .degrees((hour + minute / 60) * 30)
  }

  private func minuteAngle(for date: Date) -> Angle {
    let components = Calendar.current.dateComponents([.minute], from: date)
    let minute = Double(components.minute ?? 0)
    return .degrees(minute * 6)
  }

  private func hexColor(_ hex: String) -> Color {
    let sanitized = hex.replacingOccurrences(of: "#", with: "")
    guard let value = Int(sanitized, radix: 16) else {
      return Color(red: 96 / 255, green: 165 / 255, blue: 250 / 255)
    }

    let r = Double((value >> 16) & 0xFF) / 255.0
    let g = Double((value >> 8) & 0xFF) / 255.0
    let b = Double(value & 0xFF) / 255.0
    return Color(red: r, green: g, blue: b)
  }

  private func zeroDurationMarker(radius: CGFloat, angleDeg: Double, color: Color) -> some View {
    Capsule(style: .circular)
      .fill(color)
      .frame(width: radius * 0.03, height: radius * 0.34)
      .offset(y: -radius * 0.52)
      .rotationEffect(.degrees(angleDeg + 90))
  }
}

struct SmartAnalogWidgetEntryView: View {
  @Environment(\.widgetFamily) private var widgetFamily
  let entry: SmartAnalogWidgetProvider.Entry

  private var widgetBackground: Color {
    entry.theme == "light"
      ? Color(red: 248 / 255, green: 250 / 255, blue: 252 / 255)
      : Color(red: 2 / 255, green: 6 / 255, blue: 23 / 255)
  }

  private var widgetTextColor: Color {
    entry.theme == "light"
      ? Color(red: 15 / 255, green: 23 / 255, blue: 42 / 255)
      : Color(red: 248 / 255, green: 250 / 255, blue: 252 / 255)
  }

  private var widgetSubTextColor: Color {
    entry.theme == "light"
      ? Color(red: 51 / 255, green: 65 / 255, blue: 85 / 255)
      : Color(red: 148 / 255, green: 163 / 255, blue: 184 / 255)
  }

  private static let eventTimeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm"
    return formatter
  }()

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Smart Analog")
        .font(.headline)
        .foregroundColor(widgetTextColor)

      SmartAnalogClockFace(entry: entry)
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)

      Text("\(entry.displayDate) | events \(entry.eventCount)")
        .font(.caption)
        .foregroundColor(widgetSubTextColor)
        .lineLimit(1)

      VStack(alignment: .leading, spacing: 3) {
        Text("Today")
          .font(.caption2)
          .fontWeight(.semibold)
          .foregroundColor(widgetSubTextColor)

        if visibleEvents.isEmpty {
          Text("No events today")
            .font(.caption2)
            .foregroundColor(widgetSubTextColor)
            .lineLimit(1)
        } else {
          ForEach(visibleEvents) { event in
            HStack(spacing: 6) {
              Circle()
                .fill(hexColor(event.colorHex))
                .frame(width: 5, height: 5)

              Text("- \(eventLine(event))")
                .font(.caption2)
                .foregroundColor(widgetTextColor)
                .lineLimit(1)
            }
          }
        }
      }
    }
    .padding(12)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(widgetBackground)
  }

  private var visibleEvents: [WidgetEventPreview] {
    let maxCount: Int
    switch widgetFamily {
    case .systemSmall:
      maxCount = 1
    case .systemMedium:
      maxCount = 2
    default:
      maxCount = 3
    }
    return Array(entry.events.prefix(maxCount))
  }

  private func eventLine(_ event: WidgetEventPreview) -> String {
    if event.allDay {
      return "All day - \(event.title)"
    }

    let start = event.startTime.map { Self.eventTimeFormatter.string(from: $0) } ?? "--:--"
    let end = event.endTime.map { Self.eventTimeFormatter.string(from: $0) } ?? "--:--"
    let timePart = start == end ? start : "\(start)-\(end)"
    return "\(timePart) - \(event.title)"
  }

  private func hexColor(_ hex: String) -> Color {
    let sanitized = hex.replacingOccurrences(of: "#", with: "")
    guard let value = Int(sanitized, radix: 16) else {
      return Color(red: 100 / 255, green: 116 / 255, blue: 139 / 255)
    }

    let r = Double((value >> 16) & 0xFF) / 255.0
    let g = Double((value >> 8) & 0xFF) / 255.0
    let b = Double(value & 0xFF) / 255.0
    return Color(red: r, green: g, blue: b)
  }
}

private struct WidgetFacePalette {
  let face: Color
  let border: Color
  let tick: Color
  let hand: Color
  let minuteHand: Color
  let center: Color
}

struct SmartAnalogWidget: Widget {
  let kind: String = widgetKind

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: SmartAnalogWidgetProvider()) { entry in
      SmartAnalogWidgetEntryView(entry: entry)
    }
    .configurationDisplayName("Smart Analog")
    .description("Displays the latest Smart Analog clock snapshot.")
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
  }
}

@main
struct SmartAnalogWidgetBundle: WidgetBundle {
  var body: some Widget {
    SmartAnalogWidget()
  }
}
