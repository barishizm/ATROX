import Charts
import DataKit
import DesignSystem
import SwiftUI

/// Weight history: Swift Charts trend, the list of measurements and a sheet to add a new one.
struct MeasurementsView: View {
    let model: ProfileModel
    @State private var showingAdd = false
    @Environment(\.locale) private var locale

    var body: some View {
        List {
            if model.trendPoints.isEmpty {
                Section {
                    EmptyState(
                        systemImage: "chart.xyaxis.line", title: "measurements.empty.title",
                        message: "measurements.empty.message", actionTitle: "measurements.add"
                    ) { showingAdd = true }
                    .listRowBackground(Color.clear)
                    .accessibilityIdentifier("measurements-empty")
                }
            } else {
                Section("measurements.chart.title") {
                    WeightChart(points: model.trendPoints, unit: model.weightUnit)
                    if let change = model.weightChangeKg { changeRow(change) }
                }
                .listRowBackground(DSColor.surface)
                Section("measurements.history") {
                    ForEach(model.measurements) { row($0) }
                        .onDelete { offsets in
                            let ids = offsets.map { model.measurements[$0].id }
                            Task { for id in ids { await model.deleteMeasurement(id: id) } }
                        }
                }
                .listRowBackground(DSColor.surface)
            }
        }
        .scrollContentBackground(.hidden)
        .background(DSColor.background)
        .navigationTitle("measurements.title")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("measurements.add", systemImage: "plus") { showingAdd = true }
                    .accessibilityIdentifier("measurements-add")
            }
        }
        .sheet(isPresented: $showingAdd) { AddMeasurementSheet(model: model) }
        .accessibilityIdentifier("measurements-screen")
    }

    private func changeRow(_ kilograms: Double) -> some View {
        let unit = model.weightUnit
        let value = unit.value(fromKilograms: kilograms)
            .formatted(.number.precision(.fractionLength(0...1)).sign(strategy: .always()).locale(locale))
        return LabeledContent("measurements.change") {
            Text(verbatim: "\(value) \(unit.symbol)").font(DSFont.numericSmall)
        }
    }

    private func row(_ measurement: MeasurementSnapshot) -> some View {
        LabeledContent {
            Text(verbatim: WeightFormat.string(kilograms: measurement.input.weightKg, unit: model.weightUnit, locale: locale))
                .font(DSFont.numericSmall)
        } label: {
            Text(measurement.input.date, format: .dateTime.day().month().year())
        }
    }
}

private struct WeightChart: View {
    let points: [WeightPoint]
    let unit: WeightUnit

    var body: some View {
        Chart(points) { point in
            let value = unit.value(fromKilograms: point.kilograms)
            LineMark(x: .value("Date", point.date), y: .value("Weight", value))
                .foregroundStyle(DSColor.accent)
                .interpolationMethod(.monotone)
            PointMark(x: .value("Date", point.date), y: .value("Weight", value))
                .foregroundStyle(DSColor.accent)
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartYAxisLabel(unit.symbol)
        .frame(height: 220)
        .accessibilityLabel(Text("measurements.chart.title"))
        .accessibilityIdentifier("weight-chart")
    }
}

private struct AddMeasurementSheet: View {
    let model: ProfileModel
    @State private var weightText = ""
    @State private var date = Date()
    @State private var showsInvalid = false
    @State private var isSaving = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("measurements.add.weight")
                        TextField("", text: $weightText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .accessibilityIdentifier("measurement-weight")
                        Text(verbatim: model.weightUnit.symbol).foregroundStyle(DSColor.textSecondary)
                    }
                    DatePicker("measurements.add.date", selection: $date, in: ...Date(), displayedComponents: .date)
                }
                if showsInvalid || model.actionFailed {
                    Text("measurements.add.invalid").font(DSFont.footnote).foregroundStyle(DSColor.error)
                }
            }
            .scrollContentBackground(.hidden)
            .background(DSColor.background)
            .navigationTitle("measurements.add")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("common.cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("profile.edit.save", action: save)
                        .disabled(weightText.isEmpty || isSaving)
                        .accessibilityIdentifier("measurement-save")
                }
            }
            .task {
                if weightText.isEmpty, let kg = model.latestWeightKg {
                    weightText = model.weightUnit.value(fromKilograms: kg)
                        .formatted(.number.precision(.fractionLength(0...1)).grouping(.never).locale(locale))
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func save() {
        guard let kg = WeightFormat.kilograms(from: weightText, unit: model.weightUnit, locale: locale),
              OnboardingRules.isValidWeight(kg: kg) else {
            showsInvalid = true
            return
        }
        showsInvalid = false
        isSaving = true
        Task {
            if await model.addMeasurement(weightKg: kg, date: date) { dismiss() }
            isSaving = false
        }
    }
}
