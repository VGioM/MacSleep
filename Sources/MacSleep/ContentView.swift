import AppKit
import SwiftUI

@MainActor
final class Model: ObservableObject {
    @Published var rules = Rules.load().rules
    @Published var catchUp = Rules.load().catchUp
    @Published var exceptions = Rules.load().pruned().exceptions
    @Published private(set) var saved = Rules.load()
    @Published private(set) var installed = Helper.isInstalled
    /// The service runs the binary of an older version of the app.
    @Published private(set) var outdated = Helper.isInstalled && !Helper.isCurrent
    @Published private(set) var system = PMSet.read()
    @Published var oneOff = Model.tomorrowMorning
    @Published var error: String?

    /// True when the window differs from what the service runs.
    var dirty: Bool { current != saved.pruned() || (!rules.isEmpty && (!installed || outdated)) }

    private var current: Settings { Settings(rules: rules, catchUp: catchUp, exceptions: exceptions) }

    /// A catch-up the daemon has scheduled (see CatchUp), still to come.
    var pendingCatchUp: OneOffEvent? { upcoming.first { $0.owner == CatchUp.owner } }

    var problem: String? {
        rules.contains { $0.days.isEmpty } ? "Chaque règle doit avoir au moins un jour." : nil
    }

    /// Upcoming events, soonest first.
    var upcoming: [OneOffEvent] {
        system.oneOff
            .filter { ($0.date ?? .distantPast) > Date() }
            .sorted { $0.date! < $1.date! }
    }

    /// A new rule starts as the counterpart of the previous one.
    func addRule() {
        if let last = rules.last, last.action.isNight {
            rules.append(Rule(action: .wakeorpoweron, at: 9 * 60, days: last.days))
        } else {
            rules.append(Rule(days: rules.last?.days ?? Weekday.all))
        }
    }

    func remove(_ rule: Rule) {
        rules.removeAll { $0.id == rule.id }
        exceptions.removeAll { $0.rule == rule.id }
    }

    // MARK: Ce soir seulement

    /// The skip or move of a rule's next occurrence, if it still matches the rule.
    func exception(for rule: Rule, now: Date = Date()) -> Exception? {
        exceptions.first { e in
            e.rule == rule.id && e.isCurrent(now: now)
                && Rules.minutes(of: e.date) == rule.at && rule.days.contains(Weekday(e.date))
        }
    }

    /// The occurrence « Sauter » and « Reporter » act on.
    func nextOccurrence(of rule: Rule) -> Date? {
        exception(for: rule)?.date ?? Rules.next(rule, after: Date())
    }

    func skip(_ rule: Rule) {
        guard let date = nextOccurrence(of: rule) else { return }
        set(Exception(rule: rule.id, date: date, moved: nil))
    }

    func move(_ rule: Rule, to moved: Date) {
        guard let date = nextOccurrence(of: rule) else { return }
        set(Exception(rule: rule.id, date: date, moved: moved))
    }

    func restore(_ rule: Rule) {
        exceptions.removeAll { $0.rule == rule.id }
    }

    private func set(_ e: Exception) {
        exceptions.removeAll { $0.rule == e.rule }
        exceptions.append(e)
    }

    func save() {
        guard problem == nil else { return }
        if rules.isEmpty {
            disableAll()
            return
        }
        error = nil
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("MacSleep-rules.json")
        do {
            try Rules.encode(current).write(to: file, options: .atomic)
        } catch {
            self.error = error.localizedDescription
            return
        }
        guard let script = Helper.installScript(rulesFile: file.path) else {
            error = "Impossible de trouver l'exécutable de l'app."
            return
        }
        runAdmin(script)
        try? FileManager.default.removeItem(at: file)
    }

    func disableAll() {
        guard installed else {
            rules = []
            return
        }
        runAdmin(Helper.uninstallScript)
        if error == nil { rules = [] }
    }

    func scheduleOneOff() {
        guard oneOff > Date() else {
            error = "Choisissez une date dans le futur."
            return
        }
        runAdmin(pmset(["schedule", "wakeorpoweron", PMSet.stamp(oneOff), Helper.manualOwner]))
    }

    func cancel(_ event: OneOffEvent) {
        guard let date = event.date, let owner = event.owner else { return }
        runAdmin(pmset(["schedule", "cancel", event.type, PMSet.stamp(date), owner]))
    }

    func refresh() {
        system = PMSet.read()
        installed = Helper.isInstalled
        outdated = installed && !Helper.isCurrent
        saved = Rules.load()
    }

    private func runAdmin(_ script: String) {
        error = Admin.run(script)
        refresh()
    }

    private func pmset(_ args: [String]) -> String {
        (["/usr/bin/pmset"] + args).map(shellQuote).joined(separator: " ")
    }

    private static var tomorrowMorning: Date {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        return Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }
}

struct ContentView: View {
    @StateObject private var model = Model()

    var body: some View {
        VStack(spacing: 0) {
            header
            Form {
                if let event = model.pendingCatchUp, let date = event.date {
                    Section {
                        HStack {
                            Label("\(EventRow.noun(event.type)) de rattrapage \(EventRow.when(date)) : le Mac s'est rallumé pendant la nuit.",
                                  systemImage: "moon.haze.fill")
                                .foregroundStyle(.indigo)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer()
                            Button("Annuler") { model.cancel(event) }
                        }
                    }
                }

                Section {
                    if model.rules.isEmpty {
                        Text("Aucune règle. Ajoutez par exemple « Éteindre à 2:00 le lundi » puis « Réveiller ou allumer à 9:00 le lundi ».")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach($model.rules) { $rule in
                        RuleRow(rule: $rule, next: model.nextOccurrence(of: rule), exception: model.exception(for: rule),
                                onDelete: { model.remove(rule) }, onSkip: { model.skip(rule) },
                                onMove: { model.move(rule, to: $0) }, onRestore: { model.restore(rule) })
                    }
                    Button { model.addRule() } label: {
                        Label("Ajouter une règle", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.borderless)
                } header: {
                    Text("Règles")
                } footer: {
                    Text("L'interrupteur met une règle en pause. « Sauter » et « Reporter » ne changent que sa prochaine fois : elle reprend ensuite comme d'habitude.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if model.rules.contains(where: { $0.action == .shutdown }) {
                        warning("Un document non enregistré peut bloquer l'extinction.")
                    }
                }

                Section {
                    Toggle("Rattraper la nuit si le Mac se rallume", isOn: $model.catchUp)
                    Text("Si le Mac est allumé ou réveillé après une veille ou une extinction programmée et avant le réveil suivant, il est remis en veille ou éteint 10 minutes plus tard, une seule fois par nuit. Une notification le signale et MacSleep s'ouvre pour pouvoir l'annuler.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Section("Réveil ponctuel") {
                    HStack {
                        DatePicker("Le", selection: $model.oneOff, in: Date()...)
                        Button("Programmer") { model.scheduleOneOff() }
                    }
                }

                Section {
                    if model.upcoming.isEmpty {
                        Text("Aucun événement programmé.").foregroundStyle(.secondary)
                    }
                    ForEach(model.upcoming.prefix(10)) { event in
                        EventRow(event: event) { model.cancel(event) }
                    }
                } header: {
                    HStack {
                        Text("Prochains événements dans macOS")
                        Spacer()
                        Button { model.refresh() } label: { Image(systemName: "arrow.clockwise") }
                            .buttonStyle(.borderless)
                            .help("Relire le planning")
                    }
                }

                if !model.system.repeating.isEmpty {
                    Section("Ancien planning récurrent") {
                        ForEach(model.system.repeating, id: \.self) {
                            Text($0).font(.callout.monospaced())
                        }
                        warning("Il sera supprimé à l'enregistrement : les règles le remplacent.")
                    }
                }

                if let error = model.error {
                    Section {
                        Label(error, systemImage: "xmark.octagon.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)

            footer
        }
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .animation(.default, value: model.rules)
    }

    private var header: some View {
        let active = model.installed && model.saved.rules.contains(where: \.enabled)
        let next = model.upcoming.first { $0.fromRule }
        return HStack(spacing: 14) {
            Image(systemName: active ? "moon.zzz.fill" : "powersleep")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(active ? Color.indigo : Color.secondary)
                .frame(width: 52, height: 52)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("MacSleep").font(.title2.bold())
                Group {
                    if !active {
                        Text("Aucune règle active.")
                    } else if let next, let date = next.date {
                        Text("Prochain : \(EventRow.noun(next.type).lowercased()) \(EventRow.when(date))")
                    } else {
                        Text("\(model.saved.rules.filter(\.enabled).count) règle(s) active(s).")
                    }
                }
                .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
    }

    private var footer: some View {
        VStack(alignment: .trailing, spacing: 8) {
            if let problem = model.problem {
                warning(problem)
            } else if model.outdated && !model.rules.isEmpty {
                warning("MacSleep a été mis à jour : enregistrez pour mettre le service à jour.")
            }
            HStack {
                Button("Tout désactiver", role: .destructive) { model.disableAll() }
                    .disabled(!model.installed && model.rules.isEmpty)
                Spacer()
                if model.dirty {
                    Text("Modifications non enregistrées")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Enregistrer") { model.save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.problem != nil || !model.dirty)
            }
            Text("macOS demande le mot de passe administrateur à chaque modification.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 18)
    }
}

private func warning(_ text: String) -> some View {
    Label(text, systemImage: "exclamationmark.triangle.fill")
        .foregroundStyle(.orange)
        .fixedSize(horizontal: false, vertical: true)
}

struct RuleRow: View {
    @Binding var rule: Rule
    let next: Date?
    let exception: Exception?
    let onDelete: () -> Void
    let onSkip: () -> Void
    let onMove: (Date) -> Void
    let onRestore: () -> Void
    @State private var moving = false
    @State private var movedTo = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle("Active", isOn: $rule.enabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .help(rule.enabled ? "Mettre la règle en pause" : "Réactiver la règle")
                Image(systemName: rule.action.symbol)
                    .foregroundStyle(rule.action.isNight ? Color.indigo : Color.orange)
                    .frame(width: 20)
                Picker("Action", selection: $rule.action) {
                    ForEach(Action.allCases) { Text($0.label).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
                Text("à")
                DatePicker("Heure", selection: time, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                Spacer()
                Button(action: onDelete) {
                    Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
                .help("Supprimer la règle")
            }
            HStack {
                DayPicker(days: $rule.days)
                Text(rule.days.isEmpty ? "" : Rules.describe(rule.days))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.leading, 28)
            .opacity(rule.enabled ? 1 : 0.45)
            if !rule.enabled {
                Text("En pause : cette règle ne fait rien.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 28)
            } else if let next {
                once(next)
                    .font(.caption)
                    .padding(.leading, 28)
            }
        }
        .padding(.vertical, 2)
    }

    /// « Ce soir seulement »: the next occurrence, skipped, moved, or as it is.
    @ViewBuilder private func once(_ date: Date) -> some View {
        HStack(spacing: 8) {
            if let exception, let moved = exception.moved {
                Label("\(rule.action.noun) \(rule.action.isNight ? "reportée" : "reporté") : \(EventRow.when(date)) → \(Rules.format(Rules.minutes(of: moved)))\(Calendar.current.isDate(moved, inSameDayAs: date) ? "" : " (\(moved.formatted(.dateTime.weekday(.wide))))")",
                      systemImage: "clock.arrow.circlepath")
                    .foregroundStyle(.indigo)
                Spacer()
                Button("Rétablir", action: onRestore)
            } else if exception != nil {
                Label("\(rule.action.noun) \(rule.action.isNight ? "sautée" : "sauté") : \(EventRow.when(date)), seulement cette fois", systemImage: "forward.end.fill")
                    .foregroundStyle(.indigo)
                Spacer()
                Button("Rétablir", action: onRestore)
            } else {
                Text("Prochaine fois : \(EventRow.when(date))")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Sauter", action: onSkip)
                    .help("Ne rien faire cette fois-ci, puis reprendre comme d'habitude")
                Button("Reporter…") {
                    movedTo = date.addingTimeInterval(3600)
                    moving = true
                }
                .help("Une autre heure, cette fois-ci seulement")
                .popover(isPresented: $moving) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("\(rule.action.noun) du \(EventRow.when(date)), cette fois-ci seulement :")
                            .fixedSize(horizontal: false, vertical: true)
                        DatePicker("À", selection: $movedTo, in: Date()...date.addingTimeInterval(24 * 3600))
                        HStack {
                            Spacer()
                            Button("Annuler") { moving = false }
                            Button("Reporter") {
                                onMove(movedTo)
                                moving = false
                            }
                            .keyboardShortcut(.defaultAction)
                        }
                    }
                    .padding(14)
                    .frame(width: 320)
                }
            }
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
    }

    private var time: Binding<Date> {
        Binding(get: { Rules.date(rule.at) }, set: { rule.at = Rules.minutes(of: $0) })
    }
}

struct EventRow: View {
    let event: OneOffEvent
    let onCancel: () -> Void

    var body: some View {
        HStack {
            Text("\(Self.noun(event.type)) \(event.date.map(Self.when) ?? "")")
                .foregroundStyle(event.fromRule || event.isManual ? .primary : .secondary)
            Spacer()
            if event.fromRule {
                Text("règle").font(.caption).foregroundStyle(.secondary)
            } else if event.isManual {
                Button("Annuler", action: onCancel)
            } else {
                Text(event.owner ?? "système")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    static func noun(_ type: String) -> String {
        switch type {
        case "wake", "wakeorpoweron": "Réveil"
        case "poweron": "Allumage"
        case "sleep": "Veille"
        case "shutdown": "Extinction"
        case "restart": "Redémarrage"
        default: type
        }
    }

    static func when(_ date: Date) -> String {
        let day = date.formatted(.dateTime.weekday(.wide).day().month(.wide))
        return "\(day) à \(Rules.format(Rules.minutes(of: date)))"
    }
}

/// Seven round toggles, Monday first.
struct DayPicker: View {
    @Binding var days: Set<Weekday>

    var body: some View {
        HStack(spacing: 5) {
            ForEach(Weekday.allCases) { day in
                let on = days.contains(day)
                Button {
                    if on { days.remove(day) } else { days.insert(day) }
                } label: {
                    Text(day.initial)
                        .font(.callout.weight(.semibold))
                        .frame(width: 26, height: 26)
                        .foregroundStyle(on ? Color.white : Color.primary)
                        .background(on ? Color.accentColor : Color.secondary.opacity(0.15), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(day.name.capitalized)
            }
        }
    }
}
