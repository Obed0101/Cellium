import Foundation
import SwiftUI
import Charts
import AppKit
import CelliumCore
import CelliumStore

struct BatteryHistoryPage: View {
     @ObservedObject var model: BatteryViewModel
     @Environment(\.accessibilityReduceMotion) private var reduceMotion
     @State private var hoveredHistoryIndex: Int?
     @State private var hoveredHistoryX: CGFloat = 0
     @State private var hoveredLearningDate: Date?
     @State private var hoveredLearningX: CGFloat = 0
      @State private var hoveredCycleIndex: Int?
      @State private var hoveredCycleX: CGFloat = 0
      @State private var cachedProcessSummaries: [ProcessHistorySummary] = []

     private struct CycleHistoryPoint: Identifiable, Equatable {
         let date: Date
         let usagePercent: Double
         let equivalentCycles: Double
         let hardwareCycleDelta: Int
         let quality: SensorQuality
         let observedSeconds: TimeInterval
         let sampleCount: Int

         var id: Date { date }
     }


      private func makeProcessSummaries(from samples: [StoredProcessSample]) -> [ProcessHistorySummary] {
         let grouped = Dictionary(grouping: samples) { sample in
            "\(sample.kind.rawValue):\(sample.name)"
        }
        return grouped.values.compactMap { samples in
            guard let first = samples.first else { return nil }
            let cpu = samples.map(\.cpuPercent).reduce(0, +) / Double(samples.count)
             let memorySamples = samples.compactMap(\.memoryPercent)
             let memory = memorySamples.isEmpty ? nil : memorySamples.reduce(0, +) / Double(memorySamples.count)
             let energySamples = samples.compactMap(\.estimatedBatteryPercentPerMinute)
             let energy = energySamples.isEmpty ? nil : energySamples.reduce(0, +) / Double(energySamples.count)
             let observedMinutes = observedMinutes(for: samples)
             return ProcessHistorySummary(
                id: "\(first.kind.rawValue):\(first.name)",
                name: first.name,
                kind: first.kind,
                 averageCPUPercent: cpu,
                 memoryPercent: memory,
                 estimatedBatteryPercentPerMinute: energy,
                 estimatedDrainPercent: energy.map { $0 * observedMinutes },
                 observedMinutes: observedMinutes,
                 sampleCount: samples.count
            )
        }
         .sorted { left, right in
             let leftDrain = left.estimatedDrainPercent ?? 0
             let rightDrain = right.estimatedDrainPercent ?? 0
             if leftDrain != rightDrain { return leftDrain > rightDrain }
             return left.averageCPUPercent > right.averageCPUPercent
          }
      }

      private func refreshProcessSummaries() {
          cachedProcessSummaries = makeProcessSummaries(from: model.processHistorySamples)
      }

      private func observedMinutes(for samples: [StoredProcessSample]) -> Double {
          // fetchProcessSamples returns newest-first rows. Dictionary(grouping:)
          // preserves that order, so sorting every process again only adds work
          // while the history page is being recomputed.
          let dates = samples.map(\.timestamp)
          guard dates.count > 1 else { return 1 }
          let observedSeconds = zip(dates, dates.dropFirst()).reduce(0.0) { total, pair in
              total + min(300, max(0, pair.0.timeIntervalSince(pair.1)))
          }
         return max(1, observedSeconds / 60)
     }

     var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                hourlySection
                cycleUsageSection
                dayNightSection
                weeklyLearningSection
                processSection
            }
            .padding(18)
         }
         .frame(maxWidth: .infinity, maxHeight: .infinity)
         .foregroundStyle(CelliumBrand.foreground)
         .onAppear { refreshProcessSummaries() }
         .onChange(of: model.processHistorySamples) { _, _ in
             refreshProcessSummaries()
         }
     }

    private var hourlySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                sectionTitle(
                    model.historyRangeTitle,
                    subtitle: model.historyWindowLabel
                )
                Spacer(minLength: 4)
                Picker(model.copy(.history), selection: Binding(
                    get: { model.historyRange },
                    set: { model.setHistoryRange($0) }
                )) {
                    ForEach(HistoryRange.allCases) { range in
                        Text(range.label(for: model.language)).tag(range)
                    }
                }
                .labelsHidden()
                .controlSize(.small)
                .pickerStyle(.menu)
            }
            if model.historyAggregates.isEmpty {
                emptyState(text: model.copy(.noData))
            } else {
                Chart {
                    ForEach(model.historyAggregates, id: \.bucketStart) { aggregate in
                        if let charge = aggregate.averageChargePercent {
                            LineMark(
                                x: .value(model.copy(.chartTime), aggregate.bucketStart),
                                y: .value(model.copy(.batteryCharge), charge)
                            )
                            .foregroundStyle(CelliumBrand.signal)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                             .interpolationMethod(.catmullRom)
                         }
                     }
                     if let hoveredHistoryPoint {
                         RuleMark(x: .value(model.copy(.chartTime), hoveredHistoryPoint.date))
                             .foregroundStyle(CelliumBrand.foreground.opacity(0.5))
                             .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                         PointMark(
                             x: .value(model.copy(.chartTime), hoveredHistoryPoint.date),
                             y: .value(model.copy(.batteryCharge), hoveredHistoryPoint.charge)
                         )
                         .foregroundStyle(CelliumBrand.signal)
                         .symbolSize(42)
                     }
                 }

                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle()
                            .fill(.clear)
                            .contentShape(Rectangle())
                            .onContinuousHover(coordinateSpace: .local) { phase in
                                switch phase {
                                case .active(let location):
                                     guard let date: Date = proxy.value(atX: location.x) else { return }
                                     hoveredHistoryIndex = closestHistoryIndex(to: date)
                                     hoveredHistoryX = location.x
                                 case .ended:
                                     hoveredHistoryIndex = nil

                                }
                            }

                         if let point = hoveredHistoryPoint {
                             HistoryHoverTooltip(text: historyTooltip(for: point))
                                 .position(
                                     x: min(max(92, hoveredHistoryX), max(92, geometry.size.width - 92)),
                                     y: 18
                                 )
                         }

                    }
                }
                .chartYScale(domain: 0...100)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5))
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .frame(height: 150)
                .padding(8)
                .background(CelliumBrand.surface, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                hourlySummary
            }
        }
    }

     private var historyPoints: [(date: Date, charge: Double)] {
         model.historyAggregates.compactMap { aggregate in
             aggregate.averageChargePercent.map { (date: aggregate.bucketStart, charge: $0) }
         }
     }

     private var hoveredHistoryPoint: (date: Date, charge: Double)? {
         guard let hoveredHistoryIndex,
               historyPoints.indices.contains(hoveredHistoryIndex) else {
             return nil
         }
         return historyPoints[hoveredHistoryIndex]
     }

     private func closestHistoryIndex(to date: Date) -> Int? {

        guard !historyPoints.isEmpty else { return nil }
        return historyPoints.indices.min {
            abs(historyPoints[$0].date.timeIntervalSince(date)) < abs(historyPoints[$1].date.timeIntervalSince(date))
        }
    }

    private func historyTooltip(for point: (date: Date, charge: Double)) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: model.language == .spanish ? "es_ES" : "en_US")
        formatter.dateFormat = model.historyRange.resolution == .day ? "d MMM yyyy" : "d MMM HH:mm"
        return "\(formatter.string(from: point.date)) · \(model.copy(.batteryCharge)): \(String(format: "%.0f%%", point.charge))"
    }

    private var hourlySummary: some View {
        let charges = model.historyAggregates.compactMap(\.averageChargePercent)
        let temperatures = model.historyAggregates.compactMap(\.averageTemperatureCelsius)
        return HStack(spacing: 8) {
            statPill(
                title: model.language == .spanish ? "Promedio" : "Average",
                value: charges.isEmpty ? "—" : String(format: "%.0f%%", charges.reduce(0, +) / Double(charges.count))
            )
            statPill(
                title: model.language == .spanish ? "Rango" : "Range",
                value: rangeLabel(charges, suffix: "%", decimals: 0)
            )
            statPill(
                title: model.language == .spanish ? "Temperatura" : "Temperature",
                value: temperatures.isEmpty ? "—" : String(format: "%.1f °C", temperatures.reduce(0, +) / Double(temperatures.count))
            )
        }
    }

    private var cycleUsageSection: some View {
        VStack(alignment: .leading, spacing: 9) {
             sectionTitle(
                 model.language == .spanish ? "Uso equivalente y ciclos" : "Equivalent use and cycles",
                subtitle: model.language == .spanish
                    ? "EFC estimados; el contador de hardware permanece medido por macOS"
                     : "Estimated EFC; the hardware counter remains measured by macOS"
             )

             if let summary = model.cycleUsageSummary {
                 cycleOverview(summary)
             }

             if cycleHistoryPoints.isEmpty {
                emptyState(text: model.language == .spanish
                    ? "Aún no hay historial de ciclos equivalente."
                    : "Equivalent cycle history is not available yet.")
            } else {
                 Chart {
                    RuleMark(y: .value("100%", 100))
                        .foregroundStyle(CelliumBrand.foreground.opacity(0.45))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .annotation(position: .top, alignment: .trailing) {
                            Text(model.language == .spanish ? "100% = 1 EFC" : "100% = 1 EFC")
                                .font(.system(size: 8, weight: .medium, design: .monospaced))
                                .foregroundStyle(CelliumBrand.muted)
                        }

                     ForEach(cycleHistoryPoints) { point in
                        if usesIntradayCycleHistory {
                            BarMark(
                                x: .value(model.copy(.chartTime), point.date),
                                y: .value("EFC", point.usagePercent)
                            )
                            .foregroundStyle(cyclePointColor(point))
                            .cornerRadius(2)
                        } else {
                            BarMark(
                                x: .value(model.copy(.chartTime), point.date, unit: .day),
                                y: .value("EFC", point.usagePercent)
                            )
                            .foregroundStyle(cyclePointColor(point))
                             .cornerRadius(3)
                         }
                     }

                     if let hoveredCyclePoint {
                         RuleMark(x: .value(model.copy(.chartTime), hoveredCyclePoint.date))
                             .foregroundStyle(CelliumBrand.foreground.opacity(0.55))
                             .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                         PointMark(
                             x: .value(model.copy(.chartTime), hoveredCyclePoint.date),
                             y: .value("EFC", hoveredCyclePoint.usagePercent)
                         )
                         .foregroundStyle(cyclePointColor(hoveredCyclePoint))
                         .symbolSize(65)
                     }
                 }
                 .chartYScale(domain: 0...cycleHistoryMaximum)
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 5)) }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine().foregroundStyle(CelliumBrand.border.opacity(0.6))
                        AxisValueLabel {
                            if let percent = value.as(Double.self) {
                                Text("\(Int(percent))%")
                            }
                         }
                     }
                 }
                 .chartOverlay { proxy in
                     GeometryReader { geometry in
                         Rectangle()
                             .fill(.clear)
                             .contentShape(Rectangle())
                             .onContinuousHover(coordinateSpace: .local) { phase in
                                 switch phase {
                                 case .active(let location):
                                     guard let date: Date = proxy.value(atX: location.x) else { return }
                                     hoveredCycleIndex = closestCycleIndex(to: date)
                                     hoveredCycleX = location.x
                                 case .ended:
                                     hoveredCycleIndex = nil
                                 }
                             }

                         if let hoveredCyclePoint {
                             HistoryHoverTooltip(text: cycleTooltip(for: hoveredCyclePoint))
                                 .position(
                                     x: min(max(110, hoveredCycleX), max(110, geometry.size.width - 110)),
                                     y: 18
                                 )
                         }
                     }
                 }
                  .frame(height: 155)
                .padding(8)
                .background(CelliumBrand.surface, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .accessibilityLabel(model.language == .spanish
                    ? "Historial de uso equivalente de batería"
                    : "Equivalent battery use history")

                if let summary = model.cycleUsageSummary {
                    HStack(spacing: 8) {
                        statPill(
                            title: model.language == .spanish ? "Hoy" : "Today",
                            value: String(format: "%.0f%%", summary.todayUsagePercent)
                        )
                        statPill(
                            title: "24 h",
                            value: String(format: "%.2f EFC", summary.rolling24HourEquivalentCycles)
                        )
                        statPill(
                            title: model.language == .spanish ? "Ciclos" : "Cycles",
                            value: "+\(summary.rolling24HourHardwareCycleDelta)"
                        )
                    }

                    HStack(spacing: 12) {
                        Label(
                            cycleQualityLabel(cycleHistoryPoints.last?.quality ?? .unavailable),
                            systemImage: "waveform.path.ecg"
                        )
                        Label(
                            model.language == .spanish
                                ? "Observado \(durationLabel(summary.observedSecondsToday))"
                                : "Observed \(durationLabel(summary.observedSecondsToday))",
                            systemImage: "clock"
                        )
                        if summary.gapSecondsToday > 0 {
                            Label(
                                model.language == .spanish
                                    ? "Huecos \(durationLabel(summary.gapSecondsToday))"
                                    : "Gaps \(durationLabel(summary.gapSecondsToday))",
                                systemImage: "exclamationmark.triangle"
                            )
                            .foregroundStyle(CelliumBrand.warning)
                        }
                        Spacer(minLength: 0)
                    }
                    .font(.system(size: 8, weight: .medium, design: .rounded))
                    .foregroundStyle(CelliumBrand.muted)
                }

                ForEach(Array(cycleDetailDays.reversed()), id: \.bucketStart) { bucket in
                    HStack(spacing: 8) {
                        Text(bucket.bucketStart, format: .dateTime.day().month(.abbreviated))
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                        Text(cycleCountRange(bucket))
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(
                                bucket.hardwareCycleDelta >= 2
                                    ? CelliumBrand.critical
                                    : (bucket.cycleResetCount > 0 ? CelliumBrand.warning : CelliumBrand.muted)
                            )
                        Spacer()
                        Text(String(format: "%.0f%% · %.2f EFC", bucket.usagePercent, bucket.equivalentCycles))
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(cyclePointColor(
                                CycleHistoryPoint(
                                    date: bucket.bucketStart,
                                    usagePercent: bucket.usagePercent,
                                    equivalentCycles: bucket.equivalentCycles,
                                    hardwareCycleDelta: bucket.hardwareCycleDelta,
                                    quality: bucket.quality,
                                    observedSeconds: bucket.observedSeconds,
                                    sampleCount: bucket.sampleCount
                                )
                            ))
                    }
                    .padding(.horizontal, 4)
                }
            }
        }
    }

    private var usesIntradayCycleHistory: Bool {
        guard let duration = model.historyRange.duration else { return false }
        return duration <= 3 * 86_400
    }

    private var filteredCycleDays: [StoredCycleUsageBucket] {
        let since = model.historyRange.since
        return model.cycleUsageDailyBuckets.filter { bucket in
            since.map { bucket.bucketStart >= Calendar.autoupdatingCurrent.startOfDay(for: $0) } ?? true
        }
    }

    private var cycleDetailDays: [StoredCycleUsageBucket] {
        guard filteredCycleDays.count > 31, let first = filteredCycleDays.first else {
            return filteredCycleDays
        }
        return [first] + filteredCycleDays.dropFirst().filter {
            $0.hardwareCycleDelta > 0 || $0.cycleResetCount > 0
        }
    }

    private var cycleHistoryPoints: [CycleHistoryPoint] {
        if !usesIntradayCycleHistory {
            return filteredCycleDays.map {
                CycleHistoryPoint(
                    date: $0.bucketStart,
                    usagePercent: $0.usagePercent,
                    equivalentCycles: $0.equivalentCycles,
                    hardwareCycleDelta: $0.hardwareCycleDelta,
                    quality: $0.quality,
                    observedSeconds: $0.observedSeconds,
                    sampleCount: $0.sampleCount
                )
            }
        }

        let since = model.historyRange.since ?? .distantPast
        let buckets = model.cycleUsageQuarterHourBuckets
            .filter { $0.bucketStart >= since }
            .sorted { $0.bucketStart < $1.bucketStart }
        let grouped = Dictionary(grouping: buckets) { bucket in
            Calendar.autoupdatingCurrent.dateInterval(of: .hour, for: bucket.bucketStart)?.start
                ?? bucket.bucketStart
        }
        return grouped.values.compactMap { intervalBuckets in
            guard let first = intervalBuckets.min(by: { $0.bucketStart < $1.bucketStart }) else { return nil }
            let equivalentCycles = intervalBuckets.reduce(0) { $0 + $1.equivalentCycles }
            return CycleHistoryPoint(
                date: first.bucketStart,
                usagePercent: equivalentCycles * 100,
                equivalentCycles: equivalentCycles,
                hardwareCycleDelta: intervalBuckets.reduce(0) { $0 + $1.hardwareCycleDelta },
                quality: intervalBuckets.map(\.quality).max(by: { $0.rawValue < $1.rawValue }) ?? .unavailable,
                observedSeconds: intervalBuckets.reduce(0) { $0 + $1.observedSeconds },
                sampleCount: intervalBuckets.reduce(0) { $0 + $1.sampleCount }
            )
        }
        .sorted { $0.date < $1.date }
    }

    private var cycleHistoryMaximum: Double {
        let maximum = cycleHistoryPoints.map(\.usagePercent).max() ?? 100
        return max(20, ceil(maximum / 20) * 20)
    }

    private var hoveredCyclePoint: CycleHistoryPoint? {
        guard let hoveredCycleIndex,
              cycleHistoryPoints.indices.contains(hoveredCycleIndex) else {
            return nil
        }
        return cycleHistoryPoints[hoveredCycleIndex]
    }

    private func closestCycleIndex(to date: Date) -> Int? {
        guard !cycleHistoryPoints.isEmpty else { return nil }
        return cycleHistoryPoints.indices.min {
            abs(cycleHistoryPoints[$0].date.timeIntervalSince(date))
                < abs(cycleHistoryPoints[$1].date.timeIntervalSince(date))
        }
    }

    private func cycleTooltip(for point: CycleHistoryPoint) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: model.language == .spanish ? "es_ES" : "en_US")
        formatter.dateFormat = usesIntradayCycleHistory ? "d MMM HH:mm" : "d MMM yyyy"
        let interval = usesIntradayCycleHistory
            ? (model.language == .spanish ? "intervalo" : "interval")
            : (model.language == .spanish ? "día" : "day")
        let usage = String(format: "%.2f EFC (%.0f%%)", point.equivalentCycles, point.usagePercent)
        let cycles = model.language == .spanish
            ? "+\(point.hardwareCycleDelta) ciclos medidos"
            : "+\(point.hardwareCycleDelta) measured cycles"
        let quality = cycleQualityLabel(point.quality)
        let observed = model.language == .spanish
            ? "observado \(durationLabel(point.observedSeconds))"
            : "observed \(durationLabel(point.observedSeconds))"
        return "\(formatter.string(from: point.date)) · \(interval) · \(usage) · \(cycles) · \(observed) · \(quality)"
    }

    private func cyclePointColor(_ point: CycleHistoryPoint) -> Color {
        if point.hardwareCycleDelta >= 2 || point.usagePercent >= 200 {
            return CelliumBrand.critical
        }
        if point.usagePercent >= 100 {
            return CelliumBrand.warning
        }
        return CelliumBrand.signal
    }

    private func cycleCountRange(_ bucket: StoredCycleUsageBucket) -> String {
        if bucket.cycleResetCount > 0 {
            let count = bucket.lastCycleCount.map(String.init) ?? "—"
            return model.language == .spanish ? "\(count) · cambio" : "\(count) · changed"
        }
        if let first = bucket.firstCycleCount, let last = bucket.lastCycleCount {
            return first == last ? "\(last) · +\(bucket.hardwareCycleDelta)" : "\(first)→\(last)"
        }
        return "+\(bucket.hardwareCycleDelta)"
    }

    private func cycleQualityLabel(_ quality: SensorQuality) -> String {
        switch quality {
        case .measured: return model.language == .spanish ? "Amperaje medido" : "Measured current"
        case .calculated: return model.language == .spanish ? "Amperaje calculado" : "Calculated current"
        case .estimated: return model.language == .spanish ? "Uso estimado" : "Estimated use"
        case .stale: return model.language == .spanish ? "Dato desactualizado" : "Stale data"
        case .rejected: return model.language == .spanish ? "Dato rechazado" : "Rejected data"
        case .unavailable: return model.language == .spanish ? "Calidad no disponible" : "Quality unavailable"
        }
    }

    private func durationLabel(_ seconds: TimeInterval) -> String {
        let minutes = Int(max(0, seconds) / 60)
        if minutes >= 60 {
            return String(format: "%dh %02dm", minutes / 60, minutes % 60)
        }
        return "\(minutes)m"
    }

     private var computerUseSubtitle: String {
         let usesSelectedRange = model.historyRange != .day
             && model.historyRange.resolution != .day
         guard usesSelectedRange else {
             return model.language == .spanish
                 ? "Actividad estimada por hora, basada en CPU y memoria"
                 : "Estimated hourly activity from CPU and memory"
         }

         let rangeLabel = model.historyRange.label(for: model.language)
          return model.language == .spanish
              ? "Actividad por hora en los últimos \(rangeLabel)"
              : "Hourly activity across the last \(rangeLabel)"

     }

     private func cycleOverview(_ summary: CycleUsageSummary) -> some View {
         HStack(spacing: 14) {
             CycleUsageRing(
                 equivalentCycles: summary.todayEquivalentCycles,
                 language: model.language,
                 reduceMotion: reduceMotion
             )
             VStack(alignment: .leading, spacing: 5) {
                 Text(model.language == .spanish ? "Hoy" : "Today")
                     .font(.system(size: 11, weight: .bold, design: .rounded))
                 Text(model.language == .spanish
                     ? "Uso acumulado, no nivel de carga"
                     : "Accumulated use, not charge level")
                     .font(.system(size: 9, weight: .regular, design: .rounded))
                     .foregroundStyle(CelliumBrand.muted)
                 HStack(spacing: 6) {
                     Text(String(format: "%.2f EFC", summary.todayEquivalentCycles))
                         .font(.system(size: 12, weight: .semibold, design: .monospaced))
                         .foregroundStyle(CelliumBrand.signal)
                     Text("·")
                         .foregroundStyle(CelliumBrand.muted)
                     Text(String(format: "+%d %@", summary.todayHardwareCycleDelta, model.language == .spanish ? "ciclos medidos" : "measured cycles"))
                         .font(.system(size: 9, weight: .medium, design: .rounded))
                         .foregroundStyle(CelliumBrand.muted)
                 }
                 Text(model.language == .spanish
                     ? "La línea inferior muestra cuánto uso ocurrió en cada intervalo. Pasa el cursor para ver el detalle."
                     : "The chart below shows use in each interval. Hover for details.")
                     .font(.system(size: 9, weight: .regular, design: .rounded))
                     .foregroundStyle(CelliumBrand.muted)
                     .fixedSize(horizontal: false, vertical: true)
             }
             Spacer(minLength: 0)
         }
         .padding(10)
         .background(CelliumBrand.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
     }

     private var dayNightSection: some View {

        let segments = workTimeSegments
        let hasMeasuredActivity = segments.contains { $0.activity != nil }

         return VStack(alignment: .leading, spacing: 8) {
             HStack(alignment: .top, spacing: 8) {
                 sectionTitle(
                      model.language == .spanish ? "Uso del Mac" : "Computer use",
                      subtitle: computerUseSubtitle

                 )
                 Spacer(minLength: 4)
                 computerUseDateControls
             }
             if !hasMeasuredActivity {

                emptyState(text: model.copy(.noData))
            } else {
                 WorkTimeTimeline(
                     segments: segments,
                     language: model.language
                 )
                 .frame(height: 156)
                 workTimeLegend

            }
         }
      }

      private var computerUseDateControls: some View {
          HStack(spacing: 3) {
              Button {
                  model.moveComputerUseDate(by: -1)
              } label: {
                  Image(systemName: "chevron.left")
                      .font(.system(size: 9, weight: .semibold))
              }
              .buttonStyle(.plain)
              .frame(width: 18, height: 18)
              .contentShape(Rectangle())
              .help(model.language == .spanish ? "Día anterior" : "Previous day")

              DatePicker(
                  model.language == .spanish ? "Día de uso del Mac" : "Computer use day",
                  selection: Binding(
                      get: { model.computerUseDate },
                      set: { model.setComputerUseDate($0) }
                  ),
                  in: ...Date(),
                  displayedComponents: .date
              )
              .labelsHidden()
              .datePickerStyle(.field)
              .controlSize(.small)

              Button {
                  model.moveComputerUseDate(by: 1)
              } label: {
                  Image(systemName: "chevron.right")
                      .font(.system(size: 9, weight: .semibold))
              }
              .buttonStyle(.plain)
              .frame(width: 18, height: 18)
              .contentShape(Rectangle())
              .help(model.language == .spanish ? "Día siguiente" : "Next day")
              .disabled(model.isComputerUseToday)
          }
          .disabled(model.isRefreshingHistory)
      }

      private var workTimeLegend: some View {

         HStack(spacing: 8) {
             workLegendItem(
                 color: CelliumBrand.signal,
                 title: model.language == .spanish ? "Uso estimado" : "Estimated use"
             )
             workLegendItem(
                 color: CelliumBrand.muted,
                 title: model.language == .spanish ? "Actividad baja" : "Low activity"
             )
             workLegendItem(
                 color: CelliumBrand.border,
                 title: model.language == .spanish ? "Sin datos" : "No data"
             )
             Spacer(minLength: 0)
         }
         .font(.system(size: 8, weight: .medium, design: .rounded))
         .foregroundStyle(CelliumBrand.muted)
     }

     private func workLegendItem(color: Color, title: String) -> some View {
         HStack(spacing: 4) {
             RoundedRectangle(cornerRadius: 2, style: .continuous)
                 .fill(color)
                 .frame(width: 7, height: 7)
             Text(title)
         }
     }

      private var workTimeSegments: [WorkTimeSegment] {
          let calendar = Calendar.autoupdatingCurrent
          let window = model.computerUseDisplayWindow
          var slotStarts: [Date] = []
          var cursor = window.start

          while cursor < window.end, slotStarts.count < 10_000 {
              slotStarts.append(cursor)
              guard let next = calendar.date(byAdding: .hour, value: 1, to: cursor), next > cursor else {
                  break
              }
              cursor = next
          }

          if model.historyRange == .day,
             let latestAggregate = model.hourlyAggregates.max(by: { $0.bucketStart < $1.bucketStart }) {
              let latestSlot = calendar.dateInterval(of: .hour, for: latestAggregate.bucketStart)?.start
                  ?? latestAggregate.bucketStart
              slotStarts = slotStarts.filter { $0 <= latestSlot }
          }

          return slotStarts.enumerated().map { index, slotStart in
              let slotEnd = calendar.date(byAdding: .hour, value: 1, to: slotStart) ?? slotStart
              let samples = model.hourlyAggregates.filter {
                  $0.bucketStart >= slotStart && $0.bucketStart < slotEnd
              }
              let cpu = samples.compactMap(\.averageCPUUsagePercent)
              let memory = samples.compactMap(\.averageMemoryUsedPercent)
              let power = samples.compactMap(\.averageBatteryPowerWatts)
                  .filter { $0.isFinite && abs($0) >= 0.05 }
              return WorkTimeSegment(
                  id: index,
                  date: slotStart,
                  hour: calendar.component(.hour, from: slotStart),
                  activity: workActivity(cpu: cpu, memory: memory),
                  cpuPercent: cpu.isEmpty ? nil : cpu.reduce(0, +) / Double(cpu.count),
                  memoryPercent: memory.isEmpty ? nil : memory.reduce(0, +) / Double(memory.count),
                  powerWatts: power.isEmpty ? nil : power.reduce(0, +) / Double(power.count)
              )
          }
      }


    private func workActivity(cpu: [Double], memory: [Double]) -> Double? {
        guard !cpu.isEmpty || !memory.isEmpty else { return nil }
        let cpuAverage = cpu.isEmpty ? nil : cpu.reduce(0, +) / Double(cpu.count) / 100
        let memoryAverage = memory.isEmpty ? nil : memory.reduce(0, +) / Double(memory.count) / 100
        let score: Double
        switch (cpuAverage, memoryAverage) {
        case let (.some(cpu), .some(memory)):
            score = cpu * 0.6 + memory * 0.4
        case let (.some(cpu), nil):
            score = cpu
        case let (nil, .some(memory)):
            score = memory
        case (nil, nil):
            return nil
        }
        return min(1, max(0, score))
    }

    private var weeklyLearningSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(
                model.language == .spanish ? "Aprendizaje semanal" : "Weekly learning",
                 subtitle: model.language == .spanish
                     ? "Carga diaria, potencia y franja de actividad observadas"
                     : "Daily charge, power and observed activity windows"

            )
            if model.learningAggregates.isEmpty {
                emptyState(text: model.copy(.learningNoEvidence))
            } else {
                Chart {
                    ForEach(model.learningAggregates, id: \.bucketStart) { aggregate in
                        if let charge = aggregate.averageChargePercent {
                            BarMark(
                                x: .value(model.copy(.chartDay), aggregate.bucketStart),
                                y: .value(model.copy(.batteryCharge), charge)
                            )
                            .foregroundStyle(CelliumBrand.signal.gradient)
                         }
                     }
                     if let hoveredLearningAggregate,
                        let charge = hoveredLearningAggregate.averageChargePercent {
                         RuleMark(x: .value(model.copy(.chartDay), hoveredLearningAggregate.bucketStart))
                             .foregroundStyle(CelliumBrand.foreground.opacity(0.5))
                             .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                         PointMark(
                             x: .value(model.copy(.chartDay), hoveredLearningAggregate.bucketStart),
                             y: .value(model.copy(.batteryCharge), charge)
                         )
                         .foregroundStyle(CelliumBrand.signal)
                         .symbolSize(42)
                     }
                 }
                 .chartXScale(domain: learningChartDomain)

                .chartYScale(domain: 0...100)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) { value in
                        AxisGridLine()
                            .foregroundStyle(CelliumBrand.border.opacity(0.55))
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(learningDayLabel(for: date))
                            }
                        }
                    }
                }
                 .chartYAxis { AxisMarks(position: .leading) }
                 .chartOverlay { proxy in
                     GeometryReader { geometry in
                         Rectangle()
                             .fill(.clear)
                             .contentShape(Rectangle())
                             .onContinuousHover(coordinateSpace: .local) { phase in
                                 switch phase {
                                 case .active(let location):
                                     guard let date: Date = proxy.value(atX: location.x) else { return }
                                     hoveredLearningDate = closestLearningDate(to: date)
                                     hoveredLearningX = location.x
                                 case .ended:
                                     hoveredLearningDate = nil
                                 }
                             }

                         if let hoveredLearningAggregate {
                             HistoryHoverTooltip(text: learningTooltip(for: hoveredLearningAggregate))
                                 .position(
                                     x: min(max(100, hoveredLearningX), max(100, geometry.size.width - 100)),
                                     y: 18
                                 )
                         }
                     }
                 }
                 .frame(height: 125)

                .padding(8)
                .background(CelliumBrand.surface, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                 Text(model.learningDaysLabel)
                     .font(.system(size: 9, weight: .medium, design: .monospaced))
                     .foregroundStyle(CelliumBrand.muted)
                 if let learningPatternSummary {
                     Text(learningPatternSummary)
                         .font(.system(size: 9, weight: .regular, design: .rounded))
                         .foregroundStyle(CelliumBrand.muted)
                         .fixedSize(horizontal: false, vertical: true)
                 }

            }
        }
    }

      private var processSection: some View {
          let summaries = Array(cachedProcessSummaries.prefix(8))
          let totalDrain = summaries.compactMap(\.estimatedDrainPercent).reduce(0, +)
          return ProcessHistorySection(
              summaries: summaries,
              totalDrain: totalDrain,
              processImpacts: model.processImpacts,
              language: model.language,
              noImpactText: model.copy(.noAppImpact),
              reduceMotion: reduceMotion
          )
      }

     private struct LearningHourSummary {
         let hour: Int
         let activity: Double?
         let averagePowerWatts: Double?
     }

     private var learningHourSummaries: [LearningHourSummary] {
         let calendar = Calendar.autoupdatingCurrent
         let grouped = Dictionary(grouping: model.learningHourlyAggregates) {
             calendar.component(.hour, from: $0.bucketStart)
         }
         return grouped.compactMap { hour, aggregates in
             let cpu = aggregates.compactMap(\.averageCPUUsagePercent)
             let memory = aggregates.compactMap(\.averageMemoryUsedPercent)
             let power = aggregates.compactMap(\.averageBatteryPowerWatts)
                 .filter { $0.isFinite && abs($0) >= 0.05 }
             let activity = workActivity(cpu: cpu, memory: memory)
             guard activity != nil || !power.isEmpty else { return nil }
             return LearningHourSummary(
                 hour: hour,
                 activity: activity,
                 averagePowerWatts: power.isEmpty ? nil : power.reduce(0, +) / Double(power.count)
             )
         }
         .sorted { $0.hour < $1.hour }
     }

     private var learningPatternSummary: String? {
         guard !learningHourSummaries.isEmpty else { return nil }
         let peak = learningHourSummaries.max {
             learningActivityScore(for: $0) < learningActivityScore(for: $1)
         }
         guard let peak else { return nil }
         let nextHour = (peak.hour + 1) % 24
         let window = String(format: "%02d:00–%02d:00", peak.hour, nextHour)
         let averagePower = model.learningHourlyAggregates
             .compactMap(\.averageBatteryPowerWatts)
             .filter { $0.isFinite && abs($0) >= 0.05 }
         let watts = averagePower.isEmpty
             ? nil
             : averagePower.reduce(0, +) / Double(averagePower.count)

         var parts: [String] = []
         if model.language == .spanish {
             parts.append("Mayor actividad estimada: \(window)")
             if let watts {
                 parts.append(String(format: "media %.1f W", abs(watts)))
             }
             parts.append("basado en CPU, memoria y potencia observadas")
         } else {
             parts.append("Highest estimated activity: \(window)")
             if let watts {
                 parts.append(String(format: "%.1f W average", abs(watts)))
             }
             parts.append("based on observed CPU, memory and power")
         }
         return parts.joined(separator: " · ")
     }

     private func learningActivityScore(for summary: LearningHourSummary) -> Double {
         if let activity = summary.activity { return activity }
         return min(1, abs(summary.averagePowerWatts ?? 0) / 20)
     }

     private var learningChartDomain: ClosedRange<Date> {
         let calendar = Calendar.autoupdatingCurrent
         let end = calendar.startOfDay(for: Date())
         let start = calendar.date(byAdding: .day, value: -6, to: end) ?? end
         let upperBound = calendar.date(byAdding: .day, value: 1, to: end) ?? end
         return start...upperBound
     }

     private var hoveredLearningAggregate: BatteryAggregate? {
         guard let hoveredLearningDate else { return nil }
         return model.learningAggregates
             .filter { $0.averageChargePercent != nil }
             .min {
                 abs($0.bucketStart.timeIntervalSince(hoveredLearningDate)) <
                     abs($1.bucketStart.timeIntervalSince(hoveredLearningDate))
             }
     }

     private func closestLearningDate(to date: Date) -> Date? {
         model.learningAggregates
             .filter { $0.averageChargePercent != nil }
             .min {
                 abs($0.bucketStart.timeIntervalSince(date)) <
                     abs($1.bucketStart.timeIntervalSince(date))
             }?.bucketStart
     }

     private func learningTooltip(for aggregate: BatteryAggregate) -> String {
         let formatter = DateFormatter()
         formatter.locale = Locale(identifier: model.language == .spanish ? "es_ES" : "en_US")
         formatter.dateFormat = model.language == .spanish ? "EEEE d MMM" : "EEE, MMM d"
         var parts = [formatter.string(from: aggregate.bucketStart)]
         if let charge = aggregate.averageChargePercent {
             parts.append(String(format: model.language == .spanish ? "batería %.0f%%" : "battery %.0f%%", charge))
         }
         if let watts = aggregate.averageBatteryPowerWatts, abs(watts) >= 0.05 {
             parts.append(String(format: model.language == .spanish ? "%.1f W" : "%.1f W", abs(watts)))
         }
         return parts.joined(separator: " · ")
     }

     private func learningDayLabel(for date: Date) -> String {

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: model.language == .spanish ? "es_ES" : "en_US")
        formatter.dateFormat = model.language == .spanish ? "d MMM" : "MMM d"
        return formatter.string(from: date)
    }

    private func sectionTitle(_ title: String, subtitle: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 10, weight: .regular, design: .rounded))
                    .foregroundStyle(CelliumBrand.muted)
            }
        }
    }

    private func statPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 8, weight: .medium, design: .rounded))
                .foregroundStyle(CelliumBrand.muted)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(CelliumBrand.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func rangeLabel(_ values: [Double], suffix: String, decimals: Int) -> String {
        guard let minimum = values.min(), let maximum = values.max() else { return "—" }
        let format = decimals == 0 ? "%.0f%@–%.0f%@" : "%.1f%@–%.1f%@"
        return String(format: format, minimum, suffix, maximum, suffix)
    }

    private func emptyState(text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .regular, design: .rounded))
            .foregroundStyle(CelliumBrand.muted)
            .frame(maxWidth: .infinity, minHeight: 100, alignment: .leading)
            .padding(10)
            .background(CelliumBrand.surface, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}

private struct HistoryHoverTooltip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundStyle(CelliumBrand.foreground)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(CelliumBrand.elevated, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(CelliumBrand.border, lineWidth: 1)
            }
            .allowsHitTesting(false)
    }
}

private struct CycleUsageRing: View {
    let equivalentCycles: Double
    let language: CelliumLanguage
    let reduceMotion: Bool

    private var primaryProgress: Double {
        min(1, max(0, equivalentCycles))
    }

    private var overflowProgress: Double {
        min(1, max(0, equivalentCycles - 1))
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(CelliumBrand.border.opacity(0.7), lineWidth: 7)
            Circle()
                .trim(from: 0, to: primaryProgress)
                .stroke(CelliumBrand.signal, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Circle()
                .trim(from: 0, to: overflowProgress)
                .stroke(CelliumBrand.warning, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .scaleEffect(1.16)
            VStack(spacing: 0) {
                Text(String(format: "%.2f", equivalentCycles))
                    .font(.system(size: 17, weight: .bold, design: .monospaced))
                    .monospacedDigit()
                Text("EFC")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundStyle(CelliumBrand.muted)
            }
        }
        .frame(width: 72, height: 72)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.45), value: equivalentCycles)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(language == .spanish ? "Uso equivalente de batería hoy" : "Equivalent battery use today")
        .accessibilityValue(String(format: "%.2f EFC, %.0f%%", equivalentCycles, equivalentCycles * 100))
    }
}

  private struct WorkTimeSegment: Identifiable {
      let id: Int
      let date: Date
      let hour: Int

     let activity: Double?
     let cpuPercent: Double?
     let memoryPercent: Double?
     let powerWatts: Double?
 }

private struct WorkTimeTimeline: View {
    let segments: [WorkTimeSegment]
    let language: CelliumLanguage
    @State private var hoveredSegmentID: Int?
    @State private var hoveredX: CGFloat = 0

    var body: some View {
        TimelineView(.animation(minimumInterval: 30)) { timeline in
            ZStack {
                timelineCanvas(date: timeline.date)
                timelineLabels
                GeometryReader { geometry in
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .onContinuousHover(coordinateSpace: .local) { phase in
                            switch phase {
                            case .active(let location):
                                 let chartWidth = max(1, geometry.size.width - 28)
                                 let position = (location.x - 14) / chartWidth
                                 let segmentCount = max(1, segments.count)
                                 let index = min(
                                     segmentCount - 1,
                                     max(0, Int(position * CGFloat(segmentCount)))
                                 )
                                 hoveredSegmentID = index

                                hoveredX = location.x
                            case .ended:
                                hoveredSegmentID = nil
                            }
                        }

                    if let hoveredSegment {
                        HistoryHoverTooltip(text: tooltipText(for: hoveredSegment))
                            .position(
                                x: min(max(100, hoveredX), max(100, geometry.size.width - 100)),
                                y: 26
                            )
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(CelliumBrand.border, lineWidth: 1)
            }
        }
     }

     private var isMultiDay: Bool {
         guard let first = segments.first, let last = segments.last else { return false }
         return !Calendar.autoupdatingCurrent.isDate(first.date, inSameDayAs: last.date)
     }

     private var timelineLabelIndices: [Int] {
         guard !segments.isEmpty else { return [] }
         let candidates = [
             0,
             segments.count / 4,
             segments.count / 2,
             (segments.count * 3) / 4,
             segments.count - 1
         ]
         return candidates.reduce(into: []) { result, index in
             guard !result.contains(index) else { return }
             result.append(index)
         }
     }

     private func timelineLabel(for index: Int) -> String {
         guard segments.indices.contains(index) else { return "" }
         let formatter = DateFormatter()
         formatter.locale = Locale(identifier: language == .spanish ? "es_ES" : "en_US")
         formatter.dateFormat = isMultiDay ? "d MMM" : "HH:mm"
         return formatter.string(from: segments[index].date)
     }

     private var timelineLabels: some View {

        VStack(spacing: 0) {
            HStack {
                Text(language == .spanish ? "Actividad estimada" : "Estimated activity")
                    .foregroundStyle(CelliumBrand.foreground)
                Spacer()
                Text(language == .spanish ? "CPU + memoria" : "CPU + memory")
                    .foregroundStyle(CelliumBrand.muted)
            }
            .font(.system(size: 9, weight: .semibold, design: .monospaced))

            Spacer()

             HStack(spacing: 0) {
                 ForEach(Array(timelineLabelIndices.enumerated()), id: \.element) { position, index in
                     Text(timelineLabel(for: index))
                     if position < timelineLabelIndices.count - 1 {
                         Spacer()
                     }
                 }
             }
             .font(.system(size: 8, weight: .medium, design: .monospaced))
             .foregroundStyle(CelliumBrand.muted)

        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private func timelineCanvas(date: Date) -> some View {
        Canvas { context, size in
            drawTimeline(in: &context, size: size, date: date)
        }
    }

    private func drawTimeline(in context: inout GraphicsContext, size: CGSize, date: Date) {
        context.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .color(CelliumBrand.background)
        )

         let chart = CGRect(x: 14, y: 50, width: max(1, size.width - 28), height: 60)
         let segmentCount = max(1, segments.count)
         let slotWidth = chart.width / CGFloat(segmentCount)


        for segment in segments {
            let x = chart.minX + CGFloat(segment.id) * slotWidth
            let slot = CGRect(
                x: x + 1,
                y: chart.minY,
                width: max(1, slotWidth - 2),
                height: chart.height
            )
            let slotColor: Color
            switch activityLevel(for: segment) {
            case .active:
                slotColor = CelliumBrand.signal.opacity(0.16)
            case .low:
                slotColor = CelliumBrand.muted.opacity(0.14)
            case .noData:
                slotColor = CelliumBrand.border.opacity(0.10)
            }
            context.fill(
                Path(roundedRect: slot, cornerRadius: 3),
                with: .color(slotColor)
            )

            if let activity = segment.activity {
                let height = max(4, chart.height * (0.12 + activity * 0.88))
                let active = CGRect(
                    x: x + 3,
                    y: chart.maxY - height,
                    width: max(1, slotWidth - 6),
                    height: height
                )
                let barColor: Color = activityLevel(for: segment) == .active
                    ? CelliumBrand.signal
                    : CelliumBrand.muted
                context.fill(
                    Path(roundedRect: active, cornerRadius: 2),
                    with: .color(barColor.opacity(0.55 + activity * 0.45))
                )
            }
        }

        var baseline = Path()
        baseline.move(to: CGPoint(x: chart.minX, y: chart.maxY + 1))
        baseline.addLine(to: CGPoint(x: chart.maxX, y: chart.maxY + 1))
        context.stroke(
            baseline,
            with: .color(CelliumBrand.border),
            style: StrokeStyle(lineWidth: 1)
        )

        if let hoveredSegmentID {
            let hoveredX = chart.minX + (CGFloat(hoveredSegmentID) + 0.5) * slotWidth
            var cursor = Path()
            cursor.move(to: CGPoint(x: hoveredX, y: chart.minY - 5))
            cursor.addLine(to: CGPoint(x: hoveredX, y: chart.maxY + 5))
            context.stroke(
                cursor,
                with: .color(CelliumBrand.foreground.opacity(0.65)),
                style: StrokeStyle(lineWidth: 1, dash: [3, 3])
            )
        }

         if let markerIndex = currentMarkerIndex(for: date) {
             let markerX = chart.minX + (CGFloat(markerIndex) + 0.5) * slotWidth
             var marker = Path()
             marker.move(to: CGPoint(x: markerX, y: chart.minY - 5))
             marker.addLine(to: CGPoint(x: markerX, y: chart.maxY + 5))
             context.stroke(
                 marker,
                 with: .color(CelliumBrand.signal.opacity(0.85)),
                 style: StrokeStyle(lineWidth: 1)
             )
         }

    }

     private func currentMarkerIndex(for date: Date) -> Int? {
         guard let first = segments.first,
               let last = segments.last,
               date >= first.date,
               date < last.date.addingTimeInterval(3_600) else {
             return nil
         }
         return segments.lastIndex { $0.date <= date }
     }

     private var hoveredSegment: WorkTimeSegment? {

        guard let hoveredSegmentID else { return nil }
        return segments.first { $0.id == hoveredSegmentID }
    }

    private enum ActivityLevel {
        case active
        case low
        case noData
    }

    private func activityLevel(for segment: WorkTimeSegment) -> ActivityLevel {
        guard let activity = segment.activity else { return .noData }
        return activity >= 0.15 ? .active : .low
    }

     private func tooltipText(for segment: WorkTimeSegment) -> String {
         let nextDate = segment.date.addingTimeInterval(3_600)
         let formatter = DateFormatter()
         formatter.locale = Locale(identifier: language == .spanish ? "es_ES" : "en_US")
         formatter.dateFormat = isMultiDay ? "d MMM HH:mm" : "HH:mm"
         let window = "\(formatter.string(from: segment.date))–\(formatter.string(from: nextDate))"
         let state: String

        switch activityLevel(for: segment) {
        case .active:
            state = language == .spanish ? "Uso estimado" : "Estimated use"
        case .low:
            state = language == .spanish ? "Actividad baja" : "Low activity"
        case .noData:
            state = language == .spanish ? "Sin datos" : "No data"
        }

        var details = [window, state]
        if let cpu = segment.cpuPercent {
            details.append(String(format: "CPU %.1f%%", cpu))
        }
        if let memory = segment.memoryPercent {
            details.append(String(format: "RAM %.1f%%", memory))
        }
        if let watts = segment.powerWatts, abs(watts) >= 0.05 {
            details.append(String(format: "%.1f W", abs(watts)))
        }
        return details.joined(separator: " · ")
    }
}

private struct ProcessHistorySummary: Identifiable {
    let id: String
    let name: String
    let kind: StoredProcessKind
    let averageCPUPercent: Double
    let memoryPercent: Double?
    let estimatedBatteryPercentPerMinute: Double?
    let estimatedDrainPercent: Double?
    let observedMinutes: Double
    let sampleCount: Int
}

private struct ProcessHistorySection: View {
    let summaries: [ProcessHistorySummary]
    let totalDrain: Double
    let processImpacts: [ProcessEnergyImpact]
    let language: CelliumLanguage
    let noImpactText: String
    let reduceMotion: Bool
    @State private var hoveredProcessID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(
                language == .spanish ? "Apps y procesos con más impacto" : "Apps and processes with most impact",
                subtitle: language == .spanish
                    ? "Cuánto representan en el rango seleccionado, no solo su CPU"
                    : "What they represent in the selected range, not just their CPU"
            )
            if summaries.isEmpty {
                Text(noImpactText)
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(CelliumBrand.muted)
                    .frame(maxWidth: .infinity, minHeight: 100, alignment: .leading)
            } else {
                ProcessImpactChart(
                    summaries: summaries,
                    language: language,
                    reduceMotion: reduceMotion
                )
                .frame(height: max(170, CGFloat(summaries.count) * 28))
                ForEach(summaries) { summary in
                    processSummaryRow(summary)
                }
                Text(language == .spanish
                    ? "El consumo por app es una estimación basada en CPU/RAM y potencia observada. No es wattaje individual medido."
                    : "Per-app drain is estimated from CPU/RAM and observed battery power. It is not individually measured wattage.")
                    .font(.system(size: 9, weight: .regular, design: .rounded))
                    .foregroundStyle(CelliumBrand.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func processSummaryRow(_ summary: ProcessHistorySummary) -> some View {
        let isHovered = hoveredProcessID == summary.id
        let share = totalDrain > 0 ? (summary.estimatedDrainPercent ?? 0) / totalDrain : 0
        return HStack(spacing: 9) {
            if let icon = processImpacts.first(where: { $0.name == summary.name && $0.kind == summary.kind })?.icon {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                    .frame(width: 22)
            } else {
                Image(systemName: summary.kind.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(summary.kind.color)
                    .frame(width: 22)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(summary.name)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(summary.kind.label(for: language))
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundStyle(CelliumBrand.muted)
                }
                HStack(spacing: 6) {
                    Text(String(format: "CPU %.1f%%", summary.averageCPUPercent))
                    if let memory = summary.memoryPercent {
                        Text(String(format: "RAM %.1f%%", memory))
                    }
                    Text(observedDurationLabel(summary.observedMinutes))
                }
                .font(.system(size: 8, weight: .regular, design: .monospaced))
                .foregroundStyle(CelliumBrand.muted)
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(CelliumBrand.border.opacity(0.6))
                        Capsule()
                            .fill(summary.kind.color)
                            .frame(width: geometry.size.width * min(1, max(0, share)))
                    }
                }
                .frame(height: 4)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 3) {
                if let drain = summary.estimatedDrainPercent {
                    Text(formatEstimatedDrain(drain))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(drain >= 5 ? CelliumBrand.warning : CelliumBrand.signal)
                    if let rate = summary.estimatedBatteryPercentPerMinute {
                        Text(formatEstimatedRate(rate))
                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                            .foregroundStyle(CelliumBrand.muted)
                    }
                } else {
                    Text(language == .spanish ? "Sin estimación" : "No estimate")
                        .font(.system(size: 8, weight: .regular, design: .monospaced))
                        .foregroundStyle(CelliumBrand.muted)
                }
            }
            .frame(minWidth: 82, alignment: .trailing)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(language == .spanish ? "Consumo estimado" : "Estimated drain")
            .accessibilityValue(summary.estimatedDrainPercent.map(formatEstimatedDrain) ?? (language == .spanish ? "sin datos" : "no data"))
        }
        .padding(.vertical, 10)
        .padding(.horizontal, isHovered ? 8 : 0)
        .background(isHovered ? CelliumBrand.surface : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(Rectangle())
        .onHover { isInside in
            hoveredProcessID = isInside ? summary.id : nil
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isHovered)
    }

    private func sectionTitle(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 12, weight: .bold, design: .rounded))
            Text(subtitle)
                .font(.system(size: 9, weight: .regular, design: .rounded))
                .foregroundStyle(CelliumBrand.muted)
        }
    }

    private func observedDurationLabel(_ minutes: Double) -> String {
        let roundedMinutes = Int(minutes.rounded())
        if roundedMinutes >= 60 {
            return language == .spanish
                ? "observado \(roundedMinutes / 60)h"
                : "observed \(roundedMinutes / 60)h"
        }
        return language == .spanish
            ? "observado \(max(1, roundedMinutes))m"
            : "observed \(max(1, roundedMinutes))m"
    }

    private func formatEstimatedDrain(_ value: Double) -> String {
        if value < 0.01 { return language == .spanish ? "~<0.01% en rango" : "~<0.01% in range" }
        return String(format: language == .spanish ? "~%.1f%% en rango" : "~%.1f%% in range", value)
    }

    private func formatEstimatedRate(_ value: Double) -> String {
        if value < 0.01 { return "~<0.01%/min" }
        return String(format: "~%.2f%%/min", value)
    }
}

private struct ProcessHistoryChart: View {
    private struct Point: Identifiable {
        let id: String
        let date: Date
        let cpuPercent: Double
        let estimatedBatteryPercentPerMinute: Double?
    }

    let samples: [StoredProcessSample]
    let language: CelliumLanguage
    let range: HistoryRange
    @State private var hoveredPointID: String?
    @State private var hoveredX: CGFloat = 0

    private var points: [Point] {
        let calendar = Calendar.autoupdatingCurrent
        let grouped = Dictionary(grouping: samples) { sample in
            let components = calendar.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: sample.timestamp
            )
            return calendar.date(from: components) ?? sample.timestamp
        }
        let combined = grouped.map { date, bucket in
            let energy = bucket.compactMap(\.estimatedBatteryPercentPerMinute)
            return Point(
                id: "combined-\(date.timeIntervalSinceReferenceDate)",
                date: date,
                cpuPercent: bucket.reduce(0) { $0 + max(0, $1.cpuPercent) },
                estimatedBatteryPercentPerMinute: energy.isEmpty ? nil : energy.reduce(0, +)
            )
        }
        let ordered = combined.sorted { $0.date < $1.date }
        guard ordered.count > 240 else { return ordered }
        let lastIndex = ordered.count - 1
        let denominator = Double(239)
        return (0..<240).map { index in
            ordered[Int((Double(index) / denominator * Double(lastIndex)).rounded())]
        }
    }

    private var hoveredPoint: Point? {
        guard let hoveredPointID else { return nil }
        return points.first { $0.id == hoveredPointID }
    }

    private var cpuMaximum: Double {
        let maximum = points.map(\.cpuPercent).max() ?? 0
        guard maximum > 0 else { return 1 }
        if maximum <= 1 { return 1 }
        return ceil(maximum / 5) * 5
    }

    var body: some View {
        Chart {
            ForEach(points) { point in
                AreaMark(
                    x: .value(language == .spanish ? "Hora" : "Time", point.date),
                    y: .value(language == .spanish ? "CPU combinado" : "Combined CPU", point.cpuPercent)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [CelliumBrand.signal.opacity(0.32), CelliumBrand.signal.opacity(0.03)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                LineMark(
                    x: .value(language == .spanish ? "Hora" : "Time", point.date),
                    y: .value(language == .spanish ? "CPU combinado" : "Combined CPU", point.cpuPercent)
                )
                .foregroundStyle(CelliumBrand.signal)
                .interpolationMethod(.linear)
                .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                .symbol(Circle())
                .symbolSize(12)
            }
            if let hoveredPoint {
                RuleMark(x: .value(language == .spanish ? "Hora" : "Time", hoveredPoint.date))
                    .foregroundStyle(CelliumBrand.foreground.opacity(0.55))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .chartYScale(domain: 0...cpuMaximum)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                    .foregroundStyle(CelliumBrand.border.opacity(0.55))
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(axisDateLabel(for: date))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading)
        }
        .chartLegend(position: .bottom, spacing: 8)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover(coordinateSpace: .local) { phase in
                        switch phase {
                        case .active(let location):
                            guard let date: Date = proxy.value(atX: location.x), !points.isEmpty else { return }
                            hoveredPointID = points.min {
                                abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
                            }?.id
                            hoveredX = location.x
                        case .ended:
                            hoveredPointID = nil
                        }
                    }

                if let hoveredPoint {
                    HistoryHoverTooltip(text: tooltipText(for: hoveredPoint))
                        .position(
                            x: min(max(100, hoveredX), max(100, geometry.size.width - 100)),
                            y: 18
                        )
                }
            }
        }
        .padding(8)
        .background(CelliumBrand.surface, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .accessibilityLabel(language == .spanish ? "Uso combinado de CPU de apps y procesos" : "Combined app and process CPU usage")
    }

    private func axisDateLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language == .spanish ? "es_ES" : "en_US")
        formatter.dateFormat = range.resolution == .day ? (language == .spanish ? "d MMM" : "MMM d") : "HH:mm"
        return formatter.string(from: date)
    }

    private func tooltipText(for point: Point) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language == .spanish ? "es_ES" : "en_US")
        formatter.dateFormat = range.resolution == .day ? "d MMM yyyy" : "d MMM HH:mm"
        let cpu = String(format: "%.1f%%", point.cpuPercent)
        var text = "\(formatter.string(from: point.date)) · CPU combinado \(cpu)"
        if let energy = point.estimatedBatteryPercentPerMinute {
            text += String(format: " · ~%.2f%%/min", energy)
        }
        return text
    }
}

private struct ProcessImpactChart: View {
    let summaries: [ProcessHistorySummary]
    let language: CelliumLanguage
    let reduceMotion: Bool
    @State private var hoveredID: String?
    @State private var hoveredY: CGFloat = 0

    private var maximumDrain: Double {
        let maximum = summaries.compactMap(\.estimatedDrainPercent).max() ?? 0
        return max(1, ceil(maximum / 5) * 5)
    }

    private var hoveredSummary: ProcessHistorySummary? {
        guard let hoveredID else { return nil }
        return summaries.first { $0.id == hoveredID }
    }

    var body: some View {
        Chart {
            ForEach(summaries) { summary in
                impactMark(for: summary)
            }
        }
        .chartXScale(domain: 0...maximumDrain)
        .chartXAxis {
            AxisMarks(position: .bottom) { value in
                AxisGridLine().foregroundStyle(CelliumBrand.border.opacity(0.55))
                AxisValueLabel {
                    if let value = value.as(Double.self) {
                        Text(value < 0.01 ? "<.01%" : String(format: "%.0f%%", value))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisValueLabel {
                    if let name = value.as(String.self) {
                        Text(name)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(width: 92, alignment: .leading)
                    }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover(coordinateSpace: .local) { phase in
                        switch phase {
                        case .active(let location):
                            guard let categoryValue: String = proxy.value(atY: location.y) else { return }
                            hoveredID = summaries.first { category(for: $0) == categoryValue }?.id
                            hoveredY = location.y
                        case .ended:
                            hoveredID = nil
                        }
                    }

                if let hoveredSummary {
                    HistoryHoverTooltip(text: tooltip(for: hoveredSummary))
                        .position(
                            x: max(130, geometry.size.width - 110),
                            y: min(max(26, hoveredY), max(26, geometry.size.height - 26))
                        )
                }
            }
        }
        .padding(8)
        .background(CelliumBrand.surface, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .accessibilityLabel(language == .spanish ? "Consumo estimado por app y proceso" : "Estimated drain by app and process")
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: hoveredID)
    }

    @ChartContentBuilder
    private func impactMark(for summary: ProcessHistorySummary) -> some ChartContent {
        let drain = summary.estimatedDrainPercent ?? 0
        BarMark(
            x: .value(language == .spanish ? "Consumo estimado" : "Estimated drain", drain),
            y: .value(language == .spanish ? "Proceso" : "Process", category(for: summary))
        )
        .foregroundStyle(summary.kind.color)
        .opacity(hoveredID == nil || hoveredID == summary.id ? 1 : 0.32)
        .cornerRadius(4)
        .annotation(position: .trailing, alignment: .leading) {
            Text(drain < 0.01 ? "<0.01%" : String(format: "%.1f%%", drain))
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(CelliumBrand.muted)
        }
    }

    private func category(for summary: ProcessHistorySummary) -> String {
        "\(summary.name) · \(summary.kind.label(for: language))"
    }

    private func tooltip(for summary: ProcessHistorySummary) -> String {
        let drain = summary.estimatedDrainPercent ?? 0
        let rate = summary.estimatedBatteryPercentPerMinute ?? 0
        let drainText = drain < 0.01 ? "<0.01%" : String(format: "%.1f%%", drain)
        let rateText = rate < 0.01 ? "<0.01%/min" : String(format: "%.2f%%/min", rate)
        let observed = language == .spanish
            ? "observado \(Int(summary.observedMinutes.rounded()))m"
            : "observed \(Int(summary.observedMinutes.rounded()))m"
        if language == .spanish {
            return "\(summary.name) · \(drainText) en rango · \(rateText) · CPU \(String(format: "%.1f", summary.averageCPUPercent))% · \(observed)"
        }
        return "\(summary.name) · \(drainText) in range · \(rateText) · CPU \(String(format: "%.1f", summary.averageCPUPercent))% · \(observed)"
    }
}

private extension StoredProcessKind {
    var symbol: String {
        switch self {
        case .application: return "app.fill"
        case .daemon: return "gearshape.2.fill"
        case .script: return "scroll.fill"
        case .process: return "terminal.fill"
        }
    }

    var color: Color {
        switch self {
        case .application: return CelliumBrand.signal
        case .daemon: return CelliumBrand.accentStrong
        case .script: return CelliumBrand.warning
        case .process: return CelliumBrand.muted
        }
    }

    func label(for language: CelliumLanguage) -> String {
        switch (self, language) {
        case (.application, .spanish): return "app"
        case (.daemon, .spanish): return "servicio"
        case (.script, .spanish): return "tarea"
        case (.process, .spanish): return "proceso"
        case (.application, .english): return "app"
        case (.daemon, .english): return "service"
        case (.script, .english): return "task"
        case (.process, .english): return "process"
        }
    }
}

struct BatteryAlertsPage: View {
    @ObservedObject var model: BatteryViewModel

    private struct AlertMeasurement: Identifiable {
        let id: String
        let label: String
        let value: String
    }

    private var groupedEvents: [(date: Date, events: [StoredAlertEvent])] {
        let calendar = Calendar.autoupdatingCurrent
        let groups = Dictionary(grouping: model.alertEvents) {
            calendar.startOfDay(for: $0.occurredAt)
        }
        return groups.keys.sorted(by: >).map { date in
            (date: date, events: groups[date, default: []].sorted { $0.occurredAt > $1.occurredAt })
        }
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            alertContent
                .padding(18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(CelliumBrand.foreground)
    }

    @ViewBuilder
    private var alertContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                Label(model.copy(.alerts), systemImage: "bell.badge")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(CelliumBrand.muted)
                Spacer()
                Button(model.copy(.clearAlerts)) {
                    model.clearAlerts()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(model.alertEvents.isEmpty && model.proactiveAlert == nil)
            }

            if !model.intelligenceAnalysisLogs.isEmpty {
                intelligenceLogSection
            }

            if let alert = model.proactiveAlert {
                dayHeader(model.copy(.alertNow))
                alertCard(
                    title: alert.title,
                    body: alert.body,
                    severity: alert.severity,
                    date: Date(),
                    measurements: alert.measurements,
                    identifier: alert.identifier
                )
            }

            if groupedEvents.isEmpty, model.proactiveAlert == nil, model.intelligenceAnalysisLogs.isEmpty {
                Text(model.copy(.noData))
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(CelliumBrand.muted)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
            } else {
                ForEach(groupedEvents, id: \.date) { group in
                    VStack(alignment: .leading, spacing: 7) {
                        dayHeader(group.date)
                        ForEach(Array(group.events.enumerated()), id: \.offset) { _, event in
                            let presentation = presentation(for: event)
                            alertCard(
                                title: presentation.title,
                                body: presentation.body,
                                severity: event.severity,
                                date: event.occurredAt,
                                measurements: event.measurements,
                                identifier: event.identifier
                            )
                        }
                    }
                }
            }
        }
    }

    private var intelligenceLogSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Label(model.copy(.intelligenceLog), systemImage: "sparkles")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(0.6)
                        .foregroundStyle(CelliumBrand.muted)
                    Text(String(format: model.copy(.intelligenceLogDetail), model.intelligenceAnalysisCount))
                        .font(.system(size: 9, weight: .regular, design: .rounded))
                        .foregroundStyle(CelliumBrand.muted)
                 }
                 Spacer()
                 Button(model.copy(.clearIntelligenceLog)) {
                     model.clearIntelligenceAnalysisLog()
                 }
                 .buttonStyle(.bordered)
                 .controlSize(.mini)
                 Text(String(format: model.copy(.intelligenceRuns), model.intelligenceAnalysisCount))
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(CelliumBrand.signal)
            }

            ForEach(model.intelligenceAnalysisLogs) { run in
                intelligenceLogCard(run)
            }
        }
        .padding(.bottom, 4)
    }

    private func intelligenceLogCard(_ run: StoredIntelligenceAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: intelligenceStatusSymbol(run.status))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(intelligenceStatusColor(run.status))
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(intelligenceRunTitle(run))
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .lineLimit(2)
                        Spacer(minLength: 4)
                        Text(run.requestedAt, style: .time)
                            .font(.system(size: 8, weight: .regular, design: .monospaced))
                            .foregroundStyle(CelliumBrand.muted)
                    }
                    Text("\(run.provider) · \(run.model) · \(run.languageCode)")
                        .font(.system(size: 8, weight: .regular, design: .monospaced))
                        .foregroundStyle(CelliumBrand.muted)
                    Text(intelligenceStatusTitle(run.status))
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(intelligenceStatusColor(run.status))
                }
            }

            if let error = run.errorMessage, !error.isEmpty {
                Text(error)
                    .font(.system(size: 10, weight: .regular, design: .rounded))
                    .foregroundStyle(CelliumBrand.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let response = run.response, !response.isEmpty {
                DisclosureGroup(model.copy(.intelligenceResponse)) {
                    CelliumMarkdownText(markdown: response)
                        .font(.system(size: 10, weight: .regular, design: .rounded))
                        .foregroundStyle(CelliumBrand.muted)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }
                .font(.system(size: 10, weight: .semibold, design: .rounded))
            }

            DisclosureGroup(model.copy(.intelligencePrompt)) {
                Text(run.prompt)
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .foregroundStyle(CelliumBrand.muted)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
            .font(.system(size: 10, weight: .semibold, design: .rounded))

            if !run.evidence.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.copy(.intelligenceLocalEvidence))
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                    ForEach(run.evidence, id: \.self) { item in
                        Text("• \(item)")
                            .font(.system(size: 9, weight: .regular, design: .rounded))
                            .foregroundStyle(CelliumBrand.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if !run.recommendations.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.language == .spanish ? "Recomendaciones" : "Recommendations")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                    ForEach(run.recommendations, id: \.self) { item in
                        Text("• \(item)")
                            .font(.system(size: 9, weight: .regular, design: .rounded))
                            .foregroundStyle(CelliumBrand.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(12)
        .background(CelliumBrand.surface, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(CelliumBrand.border, lineWidth: 1)
        }
    }

    private func intelligenceRunTitle(_ run: StoredIntelligenceAnalysis) -> String {
        if run.kind == .chat {
            return model.language == .spanish ? "Conversación con el agente" : "Agent conversation"
        }
        return run.title ?? model.copy(.intelligence)
    }

    private func intelligenceStatusTitle(_ status: StoredIntelligenceRunStatus) -> String {
        switch status {
        case .running: return model.copy(.intelligenceRunning)
        case .succeeded: return model.copy(.intelligenceSucceeded)
        case .failed: return model.copy(.intelligenceFailed)
        }
    }

    private func intelligenceStatusSymbol(_ status: StoredIntelligenceRunStatus) -> String {
        switch status {
        case .running: return "arrow.triangle.2.circlepath"
        case .succeeded: return "checkmark.seal"
        case .failed: return "xmark.octagon"
        }
    }

    private func intelligenceStatusColor(_ status: StoredIntelligenceRunStatus) -> Color {
        switch status {
        case .running: return CelliumBrand.accentStrong
        case .succeeded: return CelliumBrand.signal
        case .failed: return CelliumBrand.warning
        }
    }

    private func dayHeader(_ date: Date) -> some View {
        Text(date, style: .date)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .tracking(0.8)
            .foregroundStyle(CelliumBrand.muted)
            .textCase(.uppercase)
            .environment(\.locale, Locale(identifier: model.language == .spanish ? "es_ES" : "en_US"))
    }

    private func dayHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .tracking(0.8)
            .foregroundStyle(CelliumBrand.muted)
            .textCase(.uppercase)
    }

    private func alertCard(
        title: String,
        body: String,
        severity: AlertSeverity,
        date: Date,
        measurements: [String: Double],
        identifier: String
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol(for: severity))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(color(for: severity))
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                    Spacer()
                    Text(date, style: .time)
                        .font(.system(size: 8, weight: .regular, design: .monospaced))
                        .foregroundStyle(CelliumBrand.muted)
                }
                Text(body)
                    .font(.system(size: 10, weight: .regular, design: .rounded))
                    .foregroundStyle(CelliumBrand.muted)
                    .fixedSize(horizontal: false, vertical: true)
                let displayMeasurements = measurementItems(for: measurements, identifier: identifier)
                if !displayMeasurements.isEmpty {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 4) {
                        ForEach(displayMeasurements) { measurement in
                            Text("\(measurement.label): \(measurement.value)")
                                .font(.system(size: 8, weight: .regular, design: .monospaced))
                                .foregroundStyle(CelliumBrand.muted)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(CelliumBrand.surface, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(CelliumBrand.border, lineWidth: 1)
        }
    }

    private func presentation(for event: StoredAlertEvent) -> (title: String, body: String) {
        let subject = event.subject?.trimmingCharacters(in: .whitespacesAndNewlines)
        let processName = subject?.isEmpty == false ? subject! : model.copy(.application)

        switch event.identifier {
        case "discharge":
            let rate = event.measurements["percentPerMinute"] ?? 0
            return (
                model.copy(.alertDischargeTitle),
                String(format: model.copy(.rapidDischargeAlert), rate)
            )
        case "system-memory":
            let memory = event.measurements["memoryPercent"] ?? 0
            return (
                model.copy(.alertMemoryTitle),
                String(format: model.copy(.memoryAlert), memory)
            )
        case "cycle-pace-high", "cycle-pace-elevated":
            let efc = event.measurements["rolling24HourEFC"] ?? 0
            let hardware = Int(event.measurements["hardwareCycleDelta24h"] ?? 0)
            return (
                model.language == .spanish
                    ? (event.identifier == "cycle-pace-high" ? "Ritmo de ciclos alto" : "Uso de batería elevado")
                    : (event.identifier == "cycle-pace-high" ? "High cycle pace" : "Elevated battery use"),
                model.language == .spanish
                    ? String(format: "%.2f EFC y +%d ciclos medidos en 24 h. Uso alto no significa daño confirmado.", efc, hardware)
                    : String(format: "%.2f EFC and +%d measured cycles in 24h. High use does not mean confirmed damage.", efc, hardware)
            )
        default:
            if event.identifier.hasPrefix("memory:") {
                let memory = memoryDescription(for: event.measurements)
                return (
                    "\(model.copy(.alertMemoryTitle)) · \(processName)",
                    String(format: model.copy(.appMemoryAlert), processName, memory)
                )
            }
            if event.identifier.hasPrefix("energy:") {
                let rate = event.measurements["percentPerMinute"] ?? 0
                return (
                    "\(model.copy(.alertEnergyTitle)) · \(processName)",
                    String(format: model.copy(.appEnergyAlert), processName, rate)
                )
            }
            if event.identifier.hasPrefix("cpu:") {
                let cpu = event.measurements["cpuPercent"] ?? 0
                return (
                    "\(model.copy(.alertCPUProcessTitle)) · \(processName)",
                    String(format: model.copy(.appCPUAlert), processName, cpu)
                )
            }

            let title = subject?.isEmpty == false
                ? String(format: model.copy(.alertActivity), processName)
                : model.copy(.alertBatteryEvent)
            return (title, model.copy(.alertRecorded))
        }
    }

    private func memoryDescription(for measurements: [String: Double]) -> String {
        if let bytes = measurements["residentMemoryBytes"] {
            return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory)
        }
        if let percent = measurements["memoryPercent"] {
            return String(format: "%.0f%%", percent)
        }
        return model.language == .spanish ? "un nivel elevado" : "a high amount"
    }

    private func measurementItems(
        for measurements: [String: Double],
        identifier: String
    ) -> [AlertMeasurement] {
        measurements.keys.sorted().compactMap { key in
            guard let value = measurements[key] else { return nil }
            let label: String
            switch key {
            case "cpuPercent":
                label = model.copy(.alertMeasurementCPU)
            case "memoryPercent":
                label = model.copy(.alertMeasurementMemory)
            case "residentMemoryBytes":
                label = model.copy(.alertMeasurementMemorySize)
            case "percentPerMinute":
                label = identifier == "discharge"
                    ? model.copy(.alertMeasurementDischarge)
                    : model.copy(.alertMeasurementEnergy)
            case "todayEFC":
                label = model.language == .spanish ? "EFC hoy" : "Today EFC"
            case "rolling24HourEFC":
                label = "EFC 24 h"
            case "todayUsagePercent":
                label = model.language == .spanish ? "Uso hoy" : "Use today"
            case "hardwareCycleDelta24h":
                label = model.language == .spanish ? "Ciclos 24 h" : "Cycles 24h"
            case "weeklyEFC":
                label = model.language == .spanish ? "EFC semana" : "Week EFC"
            case "projectedWeekEFC":
                label = model.language == .spanish ? "Proyección" : "Projection"
            case "weeklyBudgetEFC":
                label = model.language == .spanish ? "Presupuesto" : "Budget"
            default:
                return nil
            }
            return AlertMeasurement(
                id: key,
                label: label,
                value: measurementValue(value, key: key)
            )
        }
    }

    private func measurementValue(_ value: Double, key: String) -> String {
        switch key {
        case "residentMemoryBytes":
            return ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .memory)
        case "percentPerMinute":
            return String(format: "~%.2f%%/min", value)
        case "cpuPercent", "memoryPercent", "todayUsagePercent":
            return String(format: "%.0f%%", value)
        case "hardwareCycleDelta24h":
            return "+\(Int(value))"
        case "todayEFC", "rolling24HourEFC", "weeklyEFC", "projectedWeekEFC", "weeklyBudgetEFC":
            return String(format: "%.2f EFC", value)
        default:
            return String(format: "%.1f", value)
        }
    }

    private func symbol(for severity: AlertSeverity) -> String {
        switch severity {
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle"
        case .critical: return "exclamationmark.octagon"
        }
    }

    private func color(for severity: AlertSeverity) -> Color {
        switch severity {
        case .info: return CelliumBrand.signal
        case .warning: return CelliumBrand.warning
        case .critical: return CelliumBrand.critical
        }
    }
}
