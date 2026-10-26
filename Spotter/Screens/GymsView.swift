import CoreLocation
import MapKit
import SwiftUI
import UIKit

/// A gym from the map, with a listed daily and monthly pass.
struct GymPlace: Identifiable, Equatable {
    let id: String
    let name: String
    let address: String
    let coordinate: CLLocationCoordinate2D
    let daily: Double
    let monthly: Double
    let phone: String?
    let website: URL?
    let mapItem: MKMapItem

    static func == (lhs: GymPlace, rhs: GymPlace) -> Bool { lhs.id == rhs.id }

    static func make(_ item: MKMapItem) -> GymPlace? {
        let name = item.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !name.isEmpty else { return nil }
        let coordinate = item.placemark.coordinate
        let address = Self.address(for: item)
        let rates = GymPass.rates(name: name, coordinate: coordinate)
        let id = String(format: "%@|%.5f|%.5f", name, coordinate.latitude, coordinate.longitude)
        return GymPlace(
            id: id,
            name: name,
            address: address,
            coordinate: coordinate,
            daily: rates.daily,
            monthly: rates.monthly,
            phone: item.phoneNumber,
            website: item.url,
            mapItem: item
        )
    }

    private static func address(for item: MKMapItem) -> String {
        let mark = item.placemark
        let street = [mark.subThoroughfare, mark.thoroughfare].compactMap { $0 }.joined(separator: " ")
        let city = [mark.locality, mark.administrativeArea, mark.postalCode].compactMap { $0 }.joined(separator: " ")
        let parts = [street, city, mark.country].compactMap { $0 }.filter { !$0.isEmpty }
        if !parts.isEmpty { return parts.joined(separator: "\n") }
        return mark.title ?? item.name ?? ""
    }
}

enum GymManeuver {
    case depart, left, right, straight, uturn, arrive

    var phrase: String {
        switch self {
        case .depart: return String(localized: "Head toward the gym")
        case .left: return String(localized: "Turn left")
        case .right: return String(localized: "Turn right")
        case .straight: return String(localized: "Continue straight")
        case .uturn: return String(localized: "Make a U-turn")
        case .arrive: return String(localized: "You have arrived")
        }
    }

    init(modifier: String?, type: String?) {
        if type == "arrive" {
            self = .arrive
        } else if type == "depart" {
            self = .depart
        } else {
            switch modifier {
            case "left", "slight left", "sharp left": self = .left
            case "right", "slight right", "sharp right": self = .right
            case "uturn": self = .uturn
            default: self = .straight
            }
        }
    }

    init(apple text: String) {
        let lower = text.lowercased()
        if lower.contains("arrive") { self = .arrive }
        else if lower.contains("u-turn") || lower.contains("u turn") { self = .uturn }
        else if lower.contains("left") { self = .left }
        else if lower.contains("right") { self = .right }
        else if lower.contains("head") { self = .depart }
        else { self = .straight }
    }
}

struct GymStep: Identifiable {
    var id: Int
    var instruction: String
    var distance: CLLocationDistance
    var coordinate: CLLocationCoordinate2D
    var kind: GymManeuver

    /// Short line the coach says. Street names stay when the road is known.
    var spoken: String {
        if kind == .arrive { return String(localized: "You have arrived at the gym") }
        if instruction.isEmpty || instruction.localizedCaseInsensitiveContains("the road") {
            return kind.phrase
        }
        return instruction
    }
}

struct GymTrack {
    var coordinates: [CLLocationCoordinate2D]
    var distance: CLLocationDistance
    var expectedTravelTime: TimeInterval
    var steps: [GymStep]
    var mode: GymTravel
}

enum GymTravel: String, Hashable {
    case walk, drive

    var transportType: MKDirectionsTransportType {
        switch self {
        case .walk: return MKDirectionsTransportType.walking
        case .drive: return MKDirectionsTransportType.automobile
        }
    }
}

enum GymPassPlan: String, Codable, CaseIterable, Identifiable {
    case daily, monthly
    var id: String { rawValue }
    var title: String { self == .daily ? String(localized: "Daily") : String(localized: "Monthly") }
}

struct GymReservation: Codable, Equatable {
    var gymID: String
    var gymName: String
    var address: String
    var latitude: Double
    var longitude: Double
    var plan: GymPassPlan
    var days: Int
    var amount: Double
    var bookedAt: Date
}

enum GymPass {
    static let storeKey = "gymReservation"

    static func rates(name: String, coordinate: CLLocationCoordinate2D) -> (daily: Double, monthly: Double) {
        var hasher = Hasher()
        hasher.combine(name)
        hasher.combine(Int(coordinate.latitude * 1000))
        hasher.combine(Int(coordinate.longitude * 1000))
        let bucket = Int(UInt(bitPattern: hasher.finalize()) % 16)
        let daily = Double(15 + bucket)
        let monthly = (daily * 12).rounded()
        return (daily, monthly)
    }

    static func kilometers(_ meters: CLLocationDistance) -> String {
        let km = meters / 1000
        let places = km < 10 ? 1 : 0
        let value = km.formatted(.number.precision(.fractionLength(places)))
        return String(localized: "\(value) km")
    }
    static func money(_ amount: Double) -> String {
        amount.formatted(.currency(code: "USD").precision(.fractionLength(0)))
    }

    static func load() -> GymReservation? {
        guard let data = UserDefaults.standard.data(forKey: storeKey) else { return nil }
        return try? JSONDecoder().decode(GymReservation.self, from: data)
    }

    static func save(_ reservation: GymReservation) {
        guard let data = try? JSONEncoder().encode(reservation) else { return }
        UserDefaults.standard.set(data, forKey: storeKey)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: storeKey)
    }
}

@MainActor
final class GymMapModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var gyms: [GymPlace] = []
    @Published var selectedID: String?
    @Published var track: GymTrack?
    /// Road points for the shortest route. Drawn as-is so the line follows streets.
    @Published var routeCoordinates: [CLLocationCoordinate2D] = []
    @Published var camera: MapCameraPosition = .automatic
    @Published var authorization: CLAuthorizationStatus
    @Published var searching = false
    @Published var status: String?
    @Published var travel: GymTravel = .walk
    @Published var showDetail = false
    private var routedGymID: String?
    @Published var reservation: GymReservation?

    private let manager = CLLocationManager()
    @Published private(set) var userLocation: CLLocation?
    private var lastSearch: CLLocation?
    private var lastRouteOrigin: CLLocation?
    private var didFrame = false
    private var searchTask: Task<Void, Never>?
    private var routeTask: Task<Void, Never>?
    private var routeGeneration = 0
    @Published var routeNote: String?
    @Published var routeInFlight = false
    @Published var heading: CLLocationDirection = 0
    @Published var headingValid = false
    @Published var guidanceCue: String?
    private var nextStepIndex = 0
    private var previewedStepID: Int?
    private var actedStepID: Int?
    private var announcedArrival = false
    private var applyingCamera = false
    private var followUser = false
    private var wantsFollow = false

    override init() {
        authorization = CLLocationManager().authorizationStatus
        reservation = GymPass.load()
        super.init()
    }

    var selected: GymPlace? { gyms.first { $0.id == selectedID } }

    func start() {
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 30
        manager.headingFilter = 12
        authorization = manager.authorizationStatus
        switch authorization {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.startUpdatingLocation()
            manager.startUpdatingHeading()
            if let location = manager.location { adopt(location) }
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            status = String(localized: "Location is off. Turn it on to see gyms and a route.")
        default:
            break
        }
    }

    func stop() {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
        searchTask?.cancel()
        routeTask?.cancel()
    }

    func choose(_ id: String?) {
        guard let id else { return }
        showDetail = true
        if selectedID != id {
            selectedID = id
        }
    }

    func focus(_ id: String?) {
        guard let id else { return }
        guard let gym = gyms.first(where: { $0.id == id }), let origin = userLocation else {
            routeNote = String(localized: "Waiting for your location to draw the path.")
            return
        }
        if id == routedGymID, routeCoordinates.count > 1 { return }
        track = nil
        routeCoordinates = []
        routeNote = nil
        lastRouteOrigin = nil
        resetGuidance()
        routedGymID = id
        tuneLocation()
        drawRoute(to: gym, from: origin, fit: true)
    }

    func setTravel(_ mode: GymTravel) {
        guard travel != mode else { return }
        travel = mode
        track = nil
        routeCoordinates = []
        routeNote = nil
        lastRouteOrigin = nil
        resetGuidance()
        tuneLocation()
        guard let gym = selected, let origin = userLocation else { return }
        drawRoute(to: gym, from: origin, fit: true)
    }

    func openDirections() {
        guard let gym = selected else { return }
        let mode = travel == .walk ? MKLaunchOptionsDirectionsModeWalking : MKLaunchOptionsDirectionsModeDriving
        SpotterAnalytics.click("gym_directions", screen: "gyms", ["mode": travel.rawValue])
        gym.mapItem.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: mode])
    }

    func reserve(plan: GymPassPlan, days: Int) {
        guard let gym = selected else { return }
        let amount = plan == .daily ? gym.daily * Double(max(1, days)) : gym.monthly
        let saved = GymReservation(
            gymID: gym.id,
            gymName: gym.name,
            address: gym.address,
            latitude: gym.coordinate.latitude,
            longitude: gym.coordinate.longitude,
            plan: plan,
            days: plan == .daily ? max(1, days) : 1,
            amount: amount,
            bookedAt: .now
        )
        GymPass.save(saved)
        reservation = saved
        SpotterAnalytics.click("gym_reserve", screen: "gyms", ["plan": plan.rawValue])
        Haptics.success()
    }

    func clearReservation() {
        GymPass.clear()
        reservation = nil
        SpotterAnalytics.click("gym_reserve_clear", screen: "gyms")
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorization = manager.authorizationStatus
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            status = nil
            manager.startUpdatingLocation()
        case .denied, .restricted:
            status = String(localized: "Location is off. Turn it on to see gyms and a route.")
            manager.stopUpdatingLocation()
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        adopt(location)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let value = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        guard value >= 0 else { return }
        heading = value
        headingValid = true
    }

    func beginGuidance() {
        wantsFollow = true
        followUser = track != nil
        if followUser, let userLocation { follow(userLocation) }
    }

    func userMovedCamera(to center: CLLocationCoordinate2D) {
        if applyingCamera {
            applyingCamera = false
            return
        }
        guard let userLocation else {
            followUser = false
            return
        }
        followUser = meters(from: userLocation, to: center) < 80
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if gyms.isEmpty {
            status = String(localized: "Spotter couldn't read your location.")
        }
    }

    private func adopt(_ location: CLLocation) {
        userLocation = location
        if location.course >= 0, location.speed > 0.4 {
            heading = location.course
            headingValid = true
        }
        if !didFrame {
            didFrame = true
            applyingCamera = true
            camera = .region(MKCoordinateRegion(center: location.coordinate, latitudinalMeters: 3500, longitudinalMeters: 3500))
        }
        if lastSearch == nil || location.distance(from: lastSearch!) > 800 {
            lastSearch = location
            search(around: location)
        }
        if let gym = selected, !routeInFlight {
            let offRoute = metersOffRoute(location)
            if routeCoordinates.count < 2 || offRoute > 120 {
                drawRoute(to: gym, from: location, fit: routeCoordinates.count < 2)
            } else {
                guide(location)
            }
        }
        follow(location)
    }

    private func guide(_ location: CLLocation) {
        guard let track, track.mode == travel, let gym = selected else { return }
        let gymPoint = CLLocation(latitude: gym.coordinate.latitude, longitude: gym.coordinate.longitude)
        let arrival: CLLocationDistance = travel == .walk ? 28 : 45
        if location.distance(from: gymPoint) <= arrival {
            let line = String(localized: "You have arrived at \(gym.name)")
            guidanceCue = line
            if !announcedArrival {
                announcedArrival = true
                VoiceCoach.shared.say(line, key: "gym.arrive.\(gym.id)", cooldown: 120, priority: true)
                Haptics.success()
            }
            return
        }
        let steps = track.steps
        guard !steps.isEmpty else { return }
        while nextStepIndex < steps.count {
            let here = meters(from: location, to: steps[nextStepIndex].coordinate)
            let upcoming = nextStepIndex + 1 < steps.count
                ? meters(from: location, to: steps[nextStepIndex + 1].coordinate)
                : CLLocationDistance.greatestFiniteMagnitude
            if upcoming + 20 < here {
                nextStepIndex += 1
                continue
            }
            break
        }
        guard nextStepIndex < steps.count else { return }
        let step = steps[nextStepIndex]
        let away = meters(from: location, to: step.coordinate)
        let pass: CLLocationDistance = travel == .walk ? 18 : 40
        let approach: CLLocationDistance = travel == .walk ? 40 : 150
        if away <= pass {
            let line = step.kind == .arrive ? String(localized: "You have arrived at \(gym.name)") : step.spoken
            guidanceCue = line
            if actedStepID != step.id {
                actedStepID = step.id
                VoiceCoach.shared.say(line, key: "gym.act.\(gym.id).\(step.id)", cooldown: 20, priority: true)
            }
            nextStepIndex += 1
            return
        }
        if away <= approach {
            let line = String(localized: "\(step.spoken) ahead")
            guidanceCue = line
            if previewedStepID != step.id {
                previewedStepID = step.id
                VoiceCoach.shared.say(line, key: "gym.preview.\(gym.id).\(step.id)", cooldown: 30, priority: true)
            }
        }
    }

    private func follow(_ location: CLLocation) {
        guard followUser, !showDetail, track != nil else { return }
        applyingCamera = true
        let span: CLLocationDistance = travel == .walk ? 420 : 780
        camera = .region(MKCoordinateRegion(center: location.coordinate, latitudinalMeters: span, longitudinalMeters: span))
    }

    private func meters(from location: CLLocation, to coordinate: CLLocationCoordinate2D) -> CLLocationDistance {
        location.distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
    }

    private func resetGuidance() {
        nextStepIndex = 0
        previewedStepID = nil
        actedStepID = nil
        announcedArrival = false
        guidanceCue = nil
    }

    private func tuneLocation() {
        let guiding = selectedID != nil
        manager.distanceFilter = guiding ? 8 : 30
        manager.desiredAccuracy = guiding ? kCLLocationAccuracyBest : kCLLocationAccuracyNearestTenMeters
    }

    private func search(around location: CLLocation) {
        searchTask?.cancel()
        searching = true
        status = nil
        let region = MKCoordinateRegion(center: location.coordinate, latitudinalMeters: 8000, longitudinalMeters: 8000)
        searchTask = Task {
            let found = await Self.lookup(region: region)
            guard !Task.isCancelled else { return }
            searching = false
            gyms = found
            if found.isEmpty {
                status = String(localized: "No gyms showed up nearby.")
            } else if selectedID == nil, let reserved = reservation, found.contains(where: { $0.id == reserved.gymID }) {
                choose(reserved.gymID)
            }
        }
    }

    private func drawRoute(to gym: GymPlace, from origin: CLLocation, fit: Bool) {
        routeGeneration += 1
        let generation = routeGeneration
        routeInFlight = true
        routeNote = nil
        lastRouteOrigin = origin
        let mode = travel
        routeTask = Task {
            let track = await Self.roadPath(from: origin, to: gym, mode: mode)
            guard generation == self.routeGeneration else { return }
            routeInFlight = false
            guard var track else {
                self.track = nil
                routeCoordinates = []
                routeNote = String(localized: "No road path is available for this gym yet.")
                return
            }
            var coords = track.coordinates
            if let first = coords.first {
                let start = CLLocation(latitude: first.latitude, longitude: first.longitude)
                if origin.distance(from: start) < 250 {
                    coords.insert(origin.coordinate, at: 0)
                }
            }
            let measured = Self.length(of: coords)
            track.coordinates = coords
            track.distance = measured
            track.expectedTravelTime = Self.travelTime(distance: measured, mode: mode, routerSeconds: track.expectedTravelTime)
            self.track = track
            routeCoordinates = coords
            if coords.count < 2 {
                routeNote = String(localized: "No road path is available for this gym yet.")
                return
            }
            routeNote = nil
            resetGuidance()
            tuneLocation()
            if wantsFollow, !showDetail, let userLocation {
                followUser = true
                follow(userLocation)
            } else if fit {
                applyingCamera = true
                let rect = Self.boundingRect(coords)
                let padX = max(rect.size.width * 0.45, 2000)
                let padY = max(rect.size.height * 0.45, 2000)
                camera = .rect(rect.insetBy(dx: -padX, dy: -padY))
            }
            if let userLocation { guide(userLocation) }
        }
    }

    /// Distance from the user to the nearest point already on the drawn path.
    private func metersOffRoute(_ location: CLLocation) -> CLLocationDistance {
        guard routeCoordinates.count > 1 else { return .greatestFiniteMagnitude }
        let step = max(1, routeCoordinates.count / 50)
        var best = CLLocationDistance.greatestFiniteMagnitude
        var index = 0
        while index < routeCoordinates.count {
            let point = routeCoordinates[index]
            best = min(best, location.distance(from: CLLocation(latitude: point.latitude, longitude: point.longitude)))
            index += step
        }
        return best
    }

    /// Walking uses a foot network. Driving uses a car network. A car route is never shown as a walk.
    nonisolated private static func roadPath(from origin: CLLocation, to gym: GymPlace, mode: GymTravel) async -> GymTrack? {
        if let street = await streetRoute(from: origin.coordinate, to: gym.coordinate, mode: mode) {
            return street
        }
        let destinations = [gym.mapItem, MKMapItem(placemark: MKPlacemark(coordinate: gym.coordinate))]
        for destination in destinations {
            if let path = await appleRoute(from: origin.coordinate, to: destination, transport: mode.transportType) {
                let track = GymTrack(route: path, mode: mode)
                let speed = track.distance / max(track.expectedTravelTime, 1)
                if mode == .walk, speed > 2.8 { continue }
                return track
            }
        }
        return nil
    }

    nonisolated private static func appleRoute(from coordinate: CLLocationCoordinate2D, to destination: MKMapItem, transport: MKDirectionsTransportType) async -> MKRoute? {
        let request = MKDirections.Request()
        let start = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        start.name = "Current location"
        request.source = start
        request.destination = destination
        request.transportType = transport
        let response = try? await MKDirections(request: request).calculate()
        return response?.routes.min { $0.distance < $1.distance }
    }

    /// Foot and car are different road networks, so the kilometres and the minutes both change with the mode.
    nonisolated private static func streetRoute(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D, mode: GymTravel) async -> GymTrack? {
        let bases = mode == .walk
            ? ["https://routing.openstreetmap.de/routed-foot/route/v1/foot"]
            : [
                "https://routing.openstreetmap.de/routed-car/route/v1/driving",
                "https://router.project-osrm.org/route/v1/driving"
            ]
        for base in bases {
            if let track = await streetRoute(base: base, from: start, to: end, mode: mode) {
                return track
            }
        }
        return nil
    }

    nonisolated private static func streetRoute(base: String, from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D, mode: GymTravel) async -> GymTrack? {
        let origin = String(format: "%.6f,%.6f", locale: Locale(identifier: "en_US_POSIX"), start.longitude, start.latitude)
        let finish = String(format: "%.6f,%.6f", locale: Locale(identifier: "en_US_POSIX"), end.longitude, end.latitude)
        var parts = URLComponents(string: "\(base)/\(origin);\(finish)")
        parts?.queryItems = [
            URLQueryItem(name: "overview", value: "full"),
            URLQueryItem(name: "geometries", value: "geojson"),
            URLQueryItem(name: "steps", value: "true"),
            URLQueryItem(name: "alternatives", value: "true"),
            URLQueryItem(name: "continue_straight", value: "false")
        ]
        guard let url = parts?.url else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("Spotter/1.0", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let decoded = try? JSONDecoder().decode(StreetRouteResponse.self, from: data),
              decoded.code == "Ok",
              let route = decoded.routes.min(by: { $0.distance < $1.distance }) else { return nil }
        let speed = route.distance / max(route.duration, 1)
        if mode == .walk, speed > 2.8 { return nil }
        let coordinates = route.geometry.coordinates.compactMap { pair -> CLLocationCoordinate2D? in
            guard pair.count == 2 else { return nil }
            return CLLocationCoordinate2D(latitude: pair[1], longitude: pair[0])
        }
        guard coordinates.count > 1 else { return nil }
        let steps = (route.legs.first?.steps ?? []).enumerated().compactMap { index, step -> GymStep? in
            let kind = GymManeuver(modifier: step.maneuver.modifier, type: step.maneuver.type)
            guard step.distance >= 30 || kind == .arrive || kind == .depart else { return nil }
            guard let location = step.maneuver.location, location.count == 2 else { return nil }
            let coordinate = CLLocationCoordinate2D(latitude: location[1], longitude: location[0])
            return GymStep(id: index, instruction: step.instruction, distance: step.distance, coordinate: coordinate, kind: kind)
        }
        let measured = length(of: coordinates)
        return GymTrack(
            coordinates: coordinates,
            distance: measured,
            expectedTravelTime: travelTime(distance: measured, mode: mode, routerSeconds: route.duration),
            steps: steps,
            mode: mode
        )
    }

    /// Length of the line actually drawn, so the kilometres match the path on the map.
    nonisolated private static func length(of coordinates: [CLLocationCoordinate2D]) -> CLLocationDistance {
        guard coordinates.count > 1 else { return 0 }
        var total: CLLocationDistance = 0
        for index in 1..<coordinates.count {
            let previous = CLLocation(latitude: coordinates[index - 1].latitude, longitude: coordinates[index - 1].longitude)
            let point = CLLocation(latitude: coordinates[index].latitude, longitude: coordinates[index].longitude)
            total += previous.distance(from: point)
        }
        return total
    }

    /// Keeps a router's time only when the speed fits the mode. A walk is about 4.5 km/h.
    nonisolated private static func travelTime(distance: CLLocationDistance, mode: GymTravel, routerSeconds: TimeInterval) -> TimeInterval {
        let speed = distance / max(routerSeconds, 1)
        switch mode {
        case .walk:
            if speed >= 0.7 && speed <= 2.2 { return routerSeconds }
            return distance / 1.25
        case .drive:
            if speed >= 4 && speed <= 36 { return routerSeconds }
            return distance / 8.3
        }
    }

    private static func boundingRect(_ coordinates: [CLLocationCoordinate2D]) -> MKMapRect {
        var rect = MKMapRect.null
        for coordinate in coordinates {
            let point = MKMapPoint(coordinate)
            rect = rect.union(MKMapRect(x: point.x, y: point.y, width: 0, height: 0))
        }
        return rect
    }

    private static func lookup(region: MKCoordinateRegion) async -> [GymPlace] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "gym"
        request.region = region
        request.resultTypes = .pointOfInterest
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.fitnessCenter])
        let response = try? await MKLocalSearch(request: request).start()
        let places = response?.mapItems.compactMap(GymPlace.make) ?? []
        var seen = Set<String>()
        return places.filter { seen.insert($0.id).inserted }.prefix(20).map { $0 }
    }
}

struct GymsView: View {
    @StateObject private var model = GymMapModel()
    @State private var plan: GymPassPlan = .daily
    @State private var days = 1

    var body: some View {
        ZStack(alignment: .top) {
            Map(position: $model.camera, selection: Binding(
                get: { model.selectedID },
                set: { model.choose($0) }
            )) {
                if let here = model.userLocation?.coordinate {
                    Annotation("You", coordinate: here, anchor: .center) {
                        traveler
                    }
                }
                ForEach(model.gyms) { gym in
                    Annotation(gym.name, coordinate: gym.coordinate, anchor: .bottom) {
                        pricePin(gym, selected: model.selectedID == gym.id)
                    }
                    .tag(gym.id)
                }
                if model.routeCoordinates.count > 1 {
                    MapPolyline(coordinates: model.routeCoordinates)
                        .stroke(Theme.accent, lineWidth: 7)
                }
            }
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
            .mapControls {
                MapUserLocationButton()
                MapCompass()
            }
            if let cue = model.guidanceCue {
                Text(cue)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.black)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Theme.accent, in: Capsule())
                    .padding(.top, 12)
                    .padding(.horizontal, 24)
            }
            if model.searching {
                ProgressView()
                    .padding(10)
                    .background(.ultraThinMaterial, in: Circle())
                    .padding(.top, 12)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { panel }
        .background(Theme.bg.ignoresSafeArea())
        .onAppear { model.start() }
        .onDisappear { model.stop() }
        .onChange(of: model.selectedID) { _, id in
            model.focus(id)
        }
        .onChange(of: model.showDetail) { _, open in
            if !open { model.beginGuidance() }
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            model.userMovedCamera(to: context.region.center)
        }
        .sheet(isPresented: $model.showDetail) {
            if let gym = model.selected {
                GymDetailSheet(gym: gym, plan: $plan, days: $days)
                    .environmentObject(model)
            }
        }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let reservation = model.reservation {
                reserved(reservation)
            }
            if let status = model.status, model.selected == nil {
                Text(status)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                if model.authorization == .denied || model.authorization == .restricted {
                    Button("Open Settings") {
                        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                        UIApplication.shared.open(url)
                    }
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.accent)
                }
            }
            nearby
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
    }

    private var nearby: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Nearby gyms").eyebrow(Theme.accent)
            if model.gyms.isEmpty && !model.searching {
                Text("Your location stays on the map while this tab is open.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(model.gyms) { gym in
                        Button {
                            SpotterAnalytics.click("gym_select", screen: "gyms")
                            model.choose(gym.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(gym.name)
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                Text("\(GymPass.money(gym.daily))/day · \(GymPass.money(gym.monthly))/mo")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            .padding(12)
                            .frame(width: 180, alignment: .leading)
                            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func reserved(_ reservation: GymReservation) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Reserved").eyebrow(Theme.accent)
                Text(reservation.plan == .daily
                     ? String(localized: "\(reservation.gymName) · \(reservation.days)d · \(GymPass.money(reservation.amount))")
                     : String(localized: "\(reservation.gymName) · month · \(GymPass.money(reservation.amount))"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
            }
            Spacer()
            Button("Clear") { model.clearReservation() }
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private func pricePin(_ gym: GymPlace, selected: Bool) -> some View {
        let amount = plan == .daily ? gym.daily : gym.monthly
        return Button {
            SpotterAnalytics.click("gym_select", screen: "gyms", ["source": "map"])
            model.choose(gym.id)
        } label: {
            VStack(spacing: 3) {
                Text(GymPass.money(amount))
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(selected ? .black : .white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(selected ? Theme.accent : Color.black.opacity(0.92), in: Capsule())
                Image(systemName: "dumbbell.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(selected ? .black : Theme.accent)
                    .frame(width: 22, height: 22)
                    .background(selected ? Theme.accent : Color.black.opacity(0.92), in: Circle())
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(gym.name), \(GymPass.money(amount))"))
    }

    private var traveler: some View {
        let walking = model.travel == .walk
        return ZStack {
            if model.headingValid {
                Image(systemName: "arrowtriangle.up.fill")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(Theme.accent)
                    .offset(y: -28)
                    .rotationEffect(.degrees(model.heading))
            }
            Circle()
                .fill(Theme.accent)
                .frame(width: 40, height: 40)
                .overlay(Circle().stroke(.white, lineWidth: 2))
            Image(systemName: walking ? "figure.walk" : "car.fill")
                .font(.system(size: walking ? 18 : 16, weight: .bold))
                .foregroundStyle(.black)
                .rotationEffect(.degrees(walking || !model.headingValid ? 0 : model.heading - 90))
        }
        .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
    }
}

struct GymDetailSheet: View {
    let gym: GymPlace
    @Binding var plan: GymPassPlan
    @Binding var days: Int
    @EnvironmentObject private var model: GymMapModel
    @Environment(\.dismiss) private var dismiss

    private var liveMeters: CLLocationDistance? {
        guard let origin = model.userLocation else { return nil }
        return origin.distance(from: CLLocation(latitude: gym.coordinate.latitude, longitude: gym.coordinate.longitude))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(gym.name).font(.display(28, weight: .heavy)).foregroundStyle(.white)
                        Text(gym.address)
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    distanceBlock
                    priceBlock
                    contactBlock
                    Button {
                        model.reserve(plan: plan, days: days)
                    } label: {
                        Text("Reserve")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    Button {
                        model.openDirections()
                    } label: {
                        Label("Directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                    }
                    .buttonStyle(GlassButtonStyle())
                }
                .padding(20)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Gym")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        .presentationDragIndicator(.visible)
    }

    private var distanceBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("From you").eyebrow(Theme.accent)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "location.fill").foregroundStyle(Theme.accent)
                Text(shownDistance)
                    .font(.display(22, weight: .heavy))
                    .foregroundStyle(.white)
            }
            Text("Spotter calls each turn while this tab is open.")
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
            if let cue = model.guidanceCue {
                Text(cue)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Theme.accent, in: Capsule())
            }
            Picker("Route", selection: Binding(
                get: { model.travel },
                set: { model.setTravel($0) }
            )) {
                Label("Walk", systemImage: "figure.walk").tag(GymTravel.walk)
                Label("Drive", systemImage: "car.fill").tag(GymTravel.drive)
            }
            .pickerStyle(.segmented)
            if model.routeInFlight {
                Text("Finding the shortest road path…")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
            } else if let track = model.track, track.mode == model.travel {
                Text(routeLine(track))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(track.steps) { step in
                        if !step.instruction.isEmpty {
                            HStack(alignment: .top, spacing: 8) {
                                Text(GymPass.kilometers(step.distance))
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(Theme.accent)
                                    .frame(width: 64, alignment: .leading)
                                Text(step.instruction)
                                    .font(.subheadline)
                                    .foregroundStyle(.white)
                            }
                        }
                    }
                }
            } else if let note = model.routeNote {
                Text(note)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private var priceBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Pass").eyebrow()
            HStack(spacing: 8) {
                priceChoice(.daily, amount: gym.daily, caption: String(localized: "per day"))
                priceChoice(.monthly, amount: gym.monthly, caption: String(localized: "per month"))
            }
            if plan == .daily {
                Stepper(value: $days, in: 1...14) {
                    Text(days == 1 ? String(localized: "1 day") : String(localized: "\(days) days"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                }
            }
            Text(totalLine)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
            Text("Listed pass price in USD. Reserving saves it on this iPhone. Spotter does not charge the gym.")
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
        }
    }

    private var contactBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Contact").eyebrow()
            if let phone = gym.phone, let url = phoneURL(phone) {
                Button {
                    SpotterAnalytics.click("gym_call", screen: "gyms")
                    UIApplication.shared.open(url)
                } label: {
                    contactRow("phone.fill", phone)
                }
                .buttonStyle(.plain)
            } else {
                contactRow("phone.fill", String(localized: "No phone listed"))
            }
            if let website = gym.website {
                Button {
                    SpotterAnalytics.click("gym_website", screen: "gyms")
                    UIApplication.shared.open(website)
                } label: {
                    contactRow("safari", website.host ?? website.absoluteString)
                }
                .buttonStyle(.plain)
            } else {
                contactRow("safari", String(localized: "No website listed"))
            }
        }
    }

    private func contactRow(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(Theme.accent)
                .frame(width: 28)
            Text(text)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer()
        }
        .padding(12)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func priceChoice(_ choice: GymPassPlan, amount: Double, caption: String) -> some View {
        let on = plan == choice
        return Button {
            plan = choice
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(choice.title).font(.caption.weight(.bold)).foregroundStyle(on ? Theme.accent : Theme.textTertiary)
                Text(GymPass.money(amount)).font(.display(18, weight: .heavy)).foregroundStyle(.white)
                Text(caption).font(.caption).foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(on ? Theme.accentSoft : Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(on ? Theme.accent.opacity(0.5) : Theme.stroke))
        }
        .buttonStyle(.plain)
    }

    private var totalLine: String {
        if plan == .daily {
            let total = gym.daily * Double(days)
            return String(localized: "\(GymPass.money(gym.daily)) × \(days) = \(GymPass.money(total))")
        }
        return String(localized: "\(GymPass.money(gym.monthly)) for the month")
    }

    private var shownDistance: String {
        if let track = model.track, track.mode == model.travel {
            return GymPass.kilometers(track.distance)
        }
        return liveMeters.map(GymPass.kilometers) ?? String(localized: "Waiting for your location")
    }

    private func routeLine(_ track: GymTrack) -> String {
        let distance = GymPass.kilometers(track.distance)
        let minutes = max(1, Int((track.expectedTravelTime / 60).rounded()))
        let mode = track.mode == .walk ? String(localized: "walk") : String(localized: "drive")
        return String(localized: "Shortest path \(distance) · \(minutes) min \(mode)")
    }

    private func phoneURL(_ phone: String) -> URL? {
        let digits = phone.filter { $0.isNumber || $0 == "+" }
        guard !digits.isEmpty else { return nil }
        return URL(string: "tel:\(digits)")
    }
}

extension GymTrack {
    init(route: MKRoute, mode: GymTravel) {
        let line = route.polyline
        var coords: [CLLocationCoordinate2D] = []
        if line.pointCount > 1 {
            coords = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: line.pointCount)
            line.getCoordinates(&coords, range: NSRange(location: 0, length: line.pointCount))
        }
        let steps = route.steps.enumerated().compactMap { index, step -> GymStep? in
            let kind = GymManeuver(apple: step.instructions)
            guard !step.instructions.isEmpty, step.distance >= 30 || kind == .arrive || kind == .depart else { return nil }
            let count = step.polyline.pointCount
            guard count > 0 else { return nil }
            var points = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: count)
            step.polyline.getCoordinates(&points, range: NSRange(location: 0, length: count))
            guard let coordinate = points.first else { return nil }
            return GymStep(id: index, instruction: step.instructions, distance: step.distance, coordinate: coordinate, kind: kind)
        }
        self.init(coordinates: coords, distance: route.distance, expectedTravelTime: route.expectedTravelTime, steps: steps, mode: mode)
    }
}

private struct StreetRouteResponse: Decodable {
    struct Route: Decodable {
        struct Geometry: Decodable { let coordinates: [[Double]] }
        struct Leg: Decodable {
            struct Step: Decodable {
                struct Maneuver: Decodable {
                    let type: String?
                    let modifier: String?
                    let location: [Double]?
                }
                let distance: Double
                let name: String?
                let maneuver: Maneuver

                var instruction: String {
                    let road = (name?.isEmpty == false) ? name! : String(localized: "the road")
                    switch maneuver.modifier {
                    case "left", "slight left", "sharp left":
                        return String(localized: "Turn left onto \(road)")
                    case "right", "slight right", "sharp right":
                        return String(localized: "Turn right onto \(road)")
                    case "uturn":
                        return String(localized: "Make a U-turn onto \(road)")
                    case "straight":
                        return maneuver.type == "depart"
                            ? String(localized: "Head onto \(road)")
                            : String(localized: "Continue on \(road)")
                    default:
                        if maneuver.type == "arrive" { return String(localized: "Arrive at the gym") }
                        if maneuver.type == "depart" { return String(localized: "Head onto \(road)") }
                        return String(localized: "Continue on \(road)")
                    }
                }
            }
            let steps: [Step]
        }
        let distance: Double
        let duration: Double
        let geometry: Geometry
        let legs: [Leg]
    }
    let code: String
    let routes: [Route]
}
