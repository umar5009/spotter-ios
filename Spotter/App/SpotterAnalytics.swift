import Foundation
import FirebaseAnalytics
import SwiftUI

/// Product analytics. Body weight, height, and video are never included.
enum SpotterAnalytics {
    static func start() {
        Analytics.setAnalyticsCollectionEnabled(true)
    }

    /// One event for every tap. The event name is `spotter_` plus the control, for example `spotter_start_workout`.
    static func click(_ target: String, screen: String, _ extra: [String: Any] = [:]) {
        var params = extra
        params["screen"] = screen
        log(target, params)
    }

    static func log(_ name: String, _ parameters: [String: Any] = [:]) {
        var clean: [String: Any] = [:]
        for (key, value) in parameters {
            if let text = value as? String {
                clean[key] = String(text.prefix(100))
            } else {
                clean[key] = value
            }
        }
        let event = name.hasPrefix("spotter_") ? name : "spotter_\(name)"
        Analytics.logEvent(String(event.prefix(40)), parameters: clean.isEmpty ? nil : clean)
    }

    static func screen(_ name: String) {
        log("screen_view", [AnalyticsParameterScreenName: name])
    }

    static func sync(isPro: Bool) {
        let defaults = UserDefaults.standard
        Analytics.setUserProperty(defaults.string(forKey: "goal"), forName: "goal")
        Analytics.setUserProperty(defaults.string(forKey: "place"), forName: "place")
        Analytics.setUserProperty(defaults.string(forKey: "level"), forName: "level")
        Analytics.setUserProperty(defaults.string(forKey: "weightUnit"), forName: "weight_unit")
        Analytics.setUserProperty(isPro ? "true" : "false", forName: "is_pro")
    }
}

extension View {
    /// Logs a click without replacing the control's own action. Use this on links.
    func trackClick(_ target: String, screen: String, _ extra: [String: Any] = [:]) -> some View {
        simultaneousGesture(TapGesture().onEnded {
            SpotterAnalytics.click(target, screen: screen, extra)
        })
    }
}
