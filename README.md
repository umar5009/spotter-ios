# Spotter: AI Personal Trainer (iOS)

Spotter watches you through the iPhone camera, tracks your body with Apple Vision, counts reps, scores every rep's form from 0 to 100, and corrects you out loud ("Keep your chest up", "Hips are sagging") in real time. It works for home (bodyweight) and gym (dumbbells/barbells) training. All processing happens on the device.

## Run it

1. Requires **Xcode 16 or newer** and iOS 17+.
2. Open `Spotter.xcodeproj`.
3. Select the **Spotter** target → *Signing & Capabilities* → choose your Team, and change the bundle ID (`com.yourcompany.spotter`) to your own.
4. **Run on a real iPhone** for the camera. In the Simulator the trainer shows an animated demo squat, so you can still see the UI and the cues.
5. Prop the phone up 2–3 m away, side-on for most exercises, and start.

### Test subscriptions locally
*Product → Scheme → Edit Scheme → Run → Options → StoreKit Configuration →* select `Spotter.storekit`.
Products: `spotter.pro.yearly` ($39.99 with a 7-day free trial) and `spotter.pro.monthly` ($4.99).
In Debug builds, Profile → Developer → "Unlock Pro (debug)" also works.

## What's inside

| Area | Files |
|---|---|
| Camera + Vision pose detection, smoothing | `Pose/CameraManager.swift`, `Pose/Joint.swift` |
| Body geometry (angles, depth, body line) | `Pose/PoseGeometry.swift` |
| Exercise definitions + form rules | `Coaching/ExerciseLibrary.swift`, `Coaching/Exercise.swift` |
| Rep counting, scoring, tempo, holds | `Coaching/ExerciseAnalyzer.swift` |
| Live session flow (framing → countdown → set → rest) | `Coaching/TrainerSession.swift` |
| Voice + haptics | `Coaching/VoiceCoach.swift` |
| Live trainer UI (skeleton, cue banner, range bar) | `Trainer/` |
| Onboarding, Today, Exercises, Progress, Profile | `Screens/` |
| StoreKit 2 + paywall | `Store/` |
| Workout history (SwiftData) | `Models/WorkoutLog.swift` |

## Exercises (9)

- **Free:** Squat, Push-up, Plank
- **Pro, home:** Reverse Lunge, Glute Bridge
- **Pro, gym:** Romanian Deadlift, Overhead Press, Bicep Curl, Lateral Raise

Each exercise has a rep metric (for example hip depth, elbow angle or hip angle), full-range thresholds, form rules with score penalties, and optional tempo checks (lowering too fast).

## Add an exercise

Add an `ExerciseSpec` in `ExerciseLibrary.swift`:

1. Pick a metric from `PoseGeometry.swift`, or add one.
2. Set the `rest` and `peak` values. Log the metric while doing the movement to tune them.
3. Add `FormRule`s. Each rule has a closure that returns `true` when form is wrong.
4. Add the spec to `all`.

## Tuning and known limits

- 2D pose estimation can't see spinal rounding or depth toward the camera. Rules only use what is reliable from the recommended camera angle.
- Thresholds suit typical adult proportions. Test with real users and adjust.
- Lighting matters. Bright, even light and fitted clothing track best.

## Roadmap ideas
- Progressive overload suggestions from the form score and reps
- Apple Watch heart rate and HealthKit workout saving
- Rep video clips of your worst rep (on-device)
- More gym lifts (bench press with a side camera, hip thrust, rows)
- Web checkout for the US, now that external payment links are allowed
