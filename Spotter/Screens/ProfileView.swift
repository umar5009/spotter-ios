import SwiftUI
import UIKit

struct ProfileView: View {
    @EnvironmentObject private var store: StoreManager
    @EnvironmentObject private var router: AppRouter
    @ObservedObject private var push = PushManager.shared
    @AppStorage("voiceEnabled") private var voiceEnabled = true
    @AppStorage("freeCoachingIDs") private var freeCoachingRaw = ""
    @AppStorage("place") private var placeRaw = TrainingPlace.home.rawValue
    @AppStorage("level") private var levelRaw = Level.beginner.rawValue
    @AppStorage("goal") private var goalRaw = Goal.strength.rawValue
    @AppStorage("onboarded") private var onboarded = true
    @AppStorage("weightUnit") private var weightUnitRaw = Measure.Weight.kilograms.rawValue
    @AppStorage("heightUnit") private var heightUnitRaw = Measure.Height.centimeters.rawValue
    @AppStorage(DayReminder.hourKey) private var reminderHour = 8
    @AppStorage(DayReminder.minuteKey) private var reminderMinute = 0

    private var coachFooter: String {
        _ = freeCoachingRaw
        let names = FreeCoaching.displayNames
        if store.isPro || names.isEmpty {
            return String(localized: "Spotter speaks rep counts and form corrections and lowers your music while it talks.")
        }
        return String(localized: "Live form coaching is free on \(names). Other exercises count reps without corrections until you upgrade. Voice still calls your rep count.")
    }

    private var reminderTime: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(from: DateComponents(hour: reminderHour, minute: reminderMinute)) ?? .now
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                reminderHour = parts.hour ?? 8
                reminderMinute = parts.minute ?? 0
            }
        )
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if store.isPro {
                        Label("Spotter Pro is active", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(Theme.accent)
                    } else {
                        Button {
                            SpotterAnalytics.click("open_paywall", screen: "profile", ["source": "membership"])
                            router.showPaywall = true
                        } label: {
                            Label("Upgrade to Spotter Pro", systemImage: "sparkles")
                                .foregroundStyle(Theme.accent)
                        }
                    }
                    Button("Restore purchases") {
                        SpotterAnalytics.click("restore", screen: "profile")
                        Task { await store.restore() }
                    }
                } header: { Text("Membership") }

                Section {
                    NavigationLink {
                        HistoryView()
                    } label: {
                        Label("Weight, workouts and exercises", systemImage: "clock.arrow.circlepath")
                    }
                    .trackClick("open_history", screen: "profile")
                } header: { Text("History") }

                Section {
                    Picker("Goal", selection: $goalRaw) {
                        ForEach(Goal.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    Picker("Train at", selection: $placeRaw) {
                        ForEach(TrainingPlace.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    Picker("Level", selection: $levelRaw) {
                        ForEach(Level.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                } header: { Text("Your plan") }
                .onChange(of: goalRaw) { _, value in
                    SpotterAnalytics.click("plan_goal", screen: "profile", ["value": value])
                    SpotterAnalytics.sync(isPro: store.isPro)
                    Task { await DayReminder.reschedule() }
                }
                .onChange(of: placeRaw) { _, value in
                    SpotterAnalytics.click("plan_place", screen: "profile", ["value": value])
                    SpotterAnalytics.sync(isPro: store.isPro)
                    Task { await DayReminder.reschedule() }
                }
                .onChange(of: levelRaw) { _, value in
                    SpotterAnalytics.click("plan_level", screen: "profile", ["value": value])
                    SpotterAnalytics.sync(isPro: store.isPro)
                    Task { await DayReminder.reschedule() }
                }

                Section {
                    Picker("Weight", selection: $weightUnitRaw) {
                        ForEach(Measure.Weight.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    Picker("Height", selection: $heightUnitRaw) {
                        ForEach(Measure.Height.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                } header: { Text("Units") } footer: {
                    Text("Body weight, the load on a lift, and your height all follow these units. BMI stays the same either way.")
                }
                .onChange(of: weightUnitRaw) { _, value in
                    SpotterAnalytics.click("weight_unit", screen: "profile", ["value": value])
                    SpotterAnalytics.sync(isPro: store.isPro)
                }
                .onChange(of: heightUnitRaw) { _, value in
                    SpotterAnalytics.click("height_unit", screen: "profile", ["value": value])
                }

                Section {
                    Toggle("Voice coaching", isOn: $voiceEnabled)
                        .onChange(of: voiceEnabled) { _, on in
                            SpotterAnalytics.click("voice_coaching", screen: "profile", ["enabled": on ? "true" : "false"])
                        }
                } header: { Text("Coach") } footer: {
                    Text(coachFooter)
                }

                Section {
                    Toggle("Push notifications", isOn: Binding(
                        get: { push.wantsPush && push.isAuthorized },
                        set: { on in
                            SpotterAnalytics.click("push_notifications", screen: "profile", ["enabled": on ? "true" : "false"])
                            Task { await push.setEnabled(on) }
                        }
                    ))
                    DatePicker("Reminder time", selection: reminderTime, displayedComponents: .hourAndMinute)
                } header: { Text("Notifications") } footer: {
                    Text("A reminder each day names that day's exercises. Turn them off here, or in iOS Settings.")
                }
                .onChange(of: reminderHour) { _, _ in
                    Task { await DayReminder.reschedule() }
                }
                .onChange(of: reminderMinute) { _, _ in
                    Task { await DayReminder.reschedule() }
                }

                Section {
                    Label("Pose detection runs entirely on your iPhone. Video is never recorded or uploaded.", systemImage: "lock.shield.fill")
                        .font(.subheadline)
                    Label("Spotter is a training aid, not medical advice. Stop if you feel pain and talk to a professional about injuries.", systemImage: "heart.text.square.fill")
                        .font(.subheadline)
                } header: { Text("Privacy & safety") }

                #if DEBUG
                Section {
                    if let token = push.token {
                        Button("Copy push token") {
                            SpotterAnalytics.click("copy_push_token", screen: "profile")
                            UIPasteboard.general.string = token
                        }
                    }
                    Toggle("Unlock Pro (debug)", isOn: Binding(
                        get: { UserDefaults.standard.bool(forKey: "debugPro") },
                        set: {
                            SpotterAnalytics.click("debug_pro", screen: "profile", ["enabled": $0 ? "true" : "false"])
                            store.setDebugPro($0)
                        }))
                    Button("Replay onboarding") {
                        SpotterAnalytics.click("replay_onboarding", screen: "profile")
                        onboarded = false
                    }
                } header: { Text("Developer") }
                #endif
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg.ignoresSafeArea())
            .onAppear { push.refreshAuthorization() }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarTitleDisplayMode(.inline)
        }
    }
}
