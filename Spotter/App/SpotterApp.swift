import Darwin
import FirebaseCore
import FirebaseMessaging
import SwiftUI
import SwiftData

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        FirebaseApp.configure()
        SpotterAnalytics.start()
        PushManager.shared.start()
        if let remote = launchOptions?[.remoteNotification] as? [AnyHashable: Any] {
            PushManager.shared.handle(userInfo: remote)
        }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
    }

    /// iPhone Duo's open screen is landscape. A portrait-only app is letterboxed in the middle of it.
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        if UIDevice.current.userInterfaceIdiom == .pad { return .all }
        return Self.isDuo ? .allButUpsideDown : .portrait
    }

    /// Cover and inner displays on iPhone Duo (iPhone19,4). Other iPhones stay portrait.
    private static var isDuo: Bool {
        let model = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? hardwareModel
        return model == "iPhone19,4"
    }

    private static var hardwareModel: String {
        var system = utsname()
        uname(&system)
        return withUnsafePointer(to: &system.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
    }
}

@main
struct SpotterApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = StoreManager()

    init() {
        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = UIColor(Theme.bg)
        tab.shadowColor = UIColor(white: 1, alpha: 0.06)
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab

        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = UIColor(Theme.bg)
        nav.shadowColor = .clear
        nav.titleTextAttributes = [.foregroundColor: UIColor.white]
        nav.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
        UINavigationBar.appearance().prefersLargeTitles = false
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
        .defaultSize(width: 1400, height: 2000)
        .modelContainer(for: [WorkoutLog.self, SetLog.self, WeightEntry.self, MealEntry.self])
    }
}

/// App-wide navigation state: the live workout cover and the paywall sheet.
final class AppRouter: ObservableObject {
    @Published var activeWorkout: ActiveWorkout?
    @Published var showPaywall = false

    func start(_ workout: ActiveWorkout) {
        SpotterAnalytics.log("workout_start", [
            "title": workout.title,
            "exercise_count": workout.plan.count
        ])
        activeWorkout = workout
    }
}

struct RootView: View {
    @AppStorage("onboarded") private var onboarded = false
    @StateObject private var router = AppRouter()
    @EnvironmentObject private var store: StoreManager
    @State private var tab = 0
    @State private var showLaunch = true
    @State private var showCoach = false
    @StateObject private var photos = ProgressPhotoCenter()
    @ObservedObject private var push = PushManager.shared

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            app
            if showLaunch {
                LaunchSplash {
                    showLaunch = false
                    logScreen()
                }
                    .zIndex(1)
            }
            if onboarded, !showLaunch, router.activeWorkout == nil, !router.showPaywall, !showCoach {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        SiriOrbButton {
                            SpotterAnalytics.click("open_coach", screen: "root")
                            showCoach = true
                        }
                    }
                }
                .padding(.trailing, 18)
                .padding(.bottom, UIDevice.current.userInterfaceIdiom == .pad ? 24 : 88)
            }
        }
        .onChange(of: tab) { _, new in
            SpotterAnalytics.click("tab", screen: "root", ["tab": tabName(new)])
            logScreen()
            if new == 3 {
                refreshPhotoPrompt()
            } else {
                photos.hidePrompt()
            }
        }
        .onChange(of: onboarded) { _, done in
            if done {
                logScreen()
                if store.isPro { refreshPhotoPrompt() }
            }
        }
        .onChange(of: store.isPro) { _, pro in
            SpotterAnalytics.sync(isPro: pro)
            Task { await DayReminder.reschedule() }
        }
        .onChange(of: push.pendingRoute) { _, route in
            guard let route else { return }
            open(route)
            push.pendingRoute = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            push.refreshAuthorization()
            Task { await DayReminder.reschedule() }
            refreshPhotoPrompt()
        }
        .onChange(of: showLaunch) { _, _ in refreshPhotoPrompt() }
        .onChange(of: router.showPaywall) { _, _ in refreshPhotoPrompt() }
    }

    private func refreshPhotoPrompt() {
        guard onboarded, !showLaunch, router.activeWorkout == nil, tab == 3 else { return }
        photos.consider(paywallVisible: router.showPaywall)
    }

    private func logScreen() {
        guard onboarded else {
            SpotterAnalytics.screen("onboarding")
            return
        }
        SpotterAnalytics.screen(tabName(tab))
    }

    private func tabName(_ tab: Int) -> String {
        switch tab {
        case 0: return "today"
        case 1: return "exercises"
        case 2: return "gyms"
        case 3: return "progress"
        case 4: return "settings"
        case 5: return "meals"
        default: return "today"
        }
    }

    private func open(_ route: String) {
        switch route {
        case "today": tab = 0
        case "exercises": tab = 1
        case "gyms": tab = 2
        case "streaks", "progress": tab = 3
        case "profile", "settings": tab = 4
        case "meals", "nutrition": tab = 5
        case "progressPhoto":
            tab = 3
            photos.presentFromNotification()
        case "paywall":
            tab = 0
            router.showPaywall = true
        default:
            break
        }
    }

    private var app: some View {
        Group {
            if onboarded {
                TabView(selection: $tab) {
                    HomeView()
                        .tabItem { Label("Today", systemImage: "bolt.heart.fill") }
                        .tag(0)
                    LibraryView()
                        .tabItem { Label("Exercises", systemImage: "figure.strengthtraining.traditional") }
                        .tag(1)
                    GymsView()
                        .tabItem { Label("Gyms", systemImage: "mappin.and.ellipse") }
                        .tag(2)
                    ProgressScreen()
                        .tabItem { Label("Progress", systemImage: "chart.line.uptrend.xyaxis") }
                        .tag(3)
                    NutritionView()
                        .tabItem { Label("Meals", systemImage: "fork.knife") }
                        .tag(5)
                    ProfileView()
                        .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                        .tag(4)
                }
                .sheet(isPresented: $showCoach) {
                    CoachChatView()
                        .environmentObject(store)
                }
            } else {
                OnboardingView {
                    SpotterAnalytics.log("onboarding_complete", [
                        "goal": UserDefaults.standard.string(forKey: "goal") ?? "strength",
                        "place": UserDefaults.standard.string(forKey: "place") ?? "home",
                        "level": UserDefaults.standard.string(forKey: "level") ?? "beginner"
                    ])
                    SpotterAnalytics.sync(isPro: store.isPro)
                    withAnimation(.easeInOut) { onboarded = true }
                }
            }
        }
        .environmentObject(router)
        .environmentObject(photos)
        .modifier(ProgressPhotoPrompt(photos: photos))
        .fullScreenCover(item: $router.activeWorkout) { workout in
            TrainerView(workout: workout)
                .environmentObject(store)
                .environmentObject(router)
        }
        .sheet(isPresented: $router.showPaywall) {
            PaywallView()
                .environmentObject(store)
        }
        .overlay { LossCelebrationLayer() }
    }
}
