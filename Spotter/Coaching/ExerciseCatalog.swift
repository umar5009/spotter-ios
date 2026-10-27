import Foundation

/// Extra movements beyond the original twelve.
/// Exercises with an empty `programs` list are free. Goal programs are Spotter Pro.
enum ExerciseCatalog {
    static let extra: [ExerciseSpec] = freeMoves + sixPack + weightLoss + buildMuscle + getStrong + glutes + mobility

    // MARK: - Free library

    private static let freeMoves: [ExerciseSpec] = [
        reps(id: "forwardLunge", name: "Forward Lunge",
             equipment: "Bodyweight · Dumbbells",
             muscles: ["Quads", "Glutes", "Balance"],
             symbol: "figure.cross.training",
             required: [.shoulder, .hip, .knee, .ankle],
             metric: { p, _ in [p.kneeAngle(.left), p.kneeAngle(.right)].compactMap { $0 }.min() },
             restIsHigh: true, rest: 155, peak: 105,
             partial: "Drop the back knee closer to the floor.",
             rules: [torso(id: "flunge.torso", lean: 28)],
             steps: [
                "Stand tall, then step one foot forward.",
                "Lower until both knees bend to about 90°.",
                "Keep the front knee over the foot.",
                "Push through the front heel to stand. Alternate legs."
             ]),
        reps(id: "sideLunge", name: "Side Lunge",
             equipment: "Bodyweight",
             muscles: ["Glutes", "Adductors", "Quads"],
             symbol: "figure.flexibility",
             required: [.shoulder, .hip, .knee, .ankle],
             metric: { p, _ in [p.kneeAngle(.left), p.kneeAngle(.right)].compactMap { $0 }.min() },
             restIsHigh: true, rest: 155, peak: 105,
             partial: "Sit deeper into the hip of the bent leg.",
             rules: [torso(id: "slunge.torso", lean: 40)],
             steps: [
                "Stand tall, feet together.",
                "Step wide to one side and sit that hip back.",
                "Keep the other leg straight and the chest up.",
                "Drive through the bent heel to stand. Alternate sides."
             ]),
        reps(id: "stepUp", name: "Step-up",
             equipment: "Bench · Stair",
             muscles: ["Quads", "Glutes"],
             symbol: "figure.stairs",
             required: [.shoulder, .hip, .knee, .ankle],
             metric: { p, s in p.kneeAngle(s) },
             restIsHigh: false, rest: 105, peak: 165,
             partial: "Stand all the way up on the step.",
             rules: [torso(id: "step.torso", lean: 32)],
             steps: [
                "Put one whole foot on a sturdy step.",
                "Lean slightly forward and drive through that heel.",
                "Stand tall on the step. The trailing leg can tap.",
                "Lower with control and switch legs."
             ]),
        hold(id: "wallSit", name: "Wall Sit",
             equipment: "Wall",
             muscles: ["Quads", "Glutes"],
             symbol: "figure.strengthtraining.functional",
             required: [.shoulder, .hip, .knee, .ankle],
             inPosition: { p, s in
                guard let knee = p.kneeAngle(s) else { return false }
                return knee > 75 && knee < 125
             },
             position: "Sit until your thighs are about parallel.",
             rules: [torso(id: "wall.chest", lean: 35, cue: "Keep your chest up against the wall.")],
             steps: [
                "Back against a wall, feet a step forward.",
                "Slide down until your knees are near 90°.",
                "Knees stay over your ankles. Don't rest your hands on your thighs.",
                "Breathe. Spotter only times the seconds you hold the depth."
             ]),
        reps(id: "kneePushUp", name: "Knee Push-up",
             equipment: "Bodyweight",
             muscles: ["Chest", "Triceps", "Shoulders"],
             symbol: "figure.strengthtraining.traditional",
             required: [.shoulder, .elbow, .wrist, .hip, .knee],
             metric: { p, s in p.elbowAngle(s) },
             restIsHigh: true, rest: 150, peak: 105,
             partial: "Lower your chest closer to the floor.",
             rules: [sag(id: "kneePush.sag"), pike(id: "kneePush.pike")],
             steps: [
                "Hands just wider than shoulders, knees on the floor.",
                "Body in one line from head to knees.",
                "Lower until your elbows reach about 90°.",
                "Press the floor away."
             ],
             note: "A shorter lever than a full push-up. Keep the hips from sagging."),
        reps(id: "dip", name: "Bench Dip",
             equipment: "Bench · Chair",
             muscles: ["Triceps", "Chest", "Shoulders"],
             symbol: "figure.strengthtraining.traditional",
             required: [.shoulder, .elbow, .wrist, .hip],
             metric: { p, s in p.elbowAngle(s) },
             restIsHigh: true, rest: 155, peak: 95,
             partial: "Bend your elbows until they pass 90°.",
             rules: [FormRule(id: "dip.elbow", cue: String(localized: "Point your elbows straight back"), when: .bottom, penalty: 15, highlight: [.elbow, .shoulder]) { p, s in (p.armToTorso(s) ?? 0) > 55 }],
             steps: [
                "Hands on a bench behind you, fingers forward, legs out.",
                "Slide your hips off the bench.",
                "Bend the elbows straight back, shoulders down.",
                "Press until the arms are straight."
             ]),
        reps(id: "invertedRow", name: "Inverted Row",
             equipment: "Table · Bar",
             muscles: ["Upper back", "Biceps"],
             symbol: "figure.rowing",
             required: [.shoulder, .elbow, .wrist, .hip],
             metric: lying({ p, s in p.elbowAngle(s) }, rest: 155, minTilt: 35),
             restIsHigh: true, rest: 155, peak: 80,
             partial: "Pull your chest all the way to the bar.",
             rules: [sag(id: "irow.sag", cue: "Keep a straight line from head to heels.")],
             steps: [
                "Hang under a sturdy table or bar, body straight.",
                "Hands about shoulder-width, heels on the floor.",
                "Pull your chest up until your elbows pass your ribs.",
                "Lower slowly. Hips stay up."
             ]),
        reps(id: "pullUp", name: "Pull-up",
             place: .gym, equipment: "Pull-up bar",
             muscles: ["Lats", "Biceps", "Upper back"],
             symbol: "figure.climbing",
             camera: .front, bothSides: true,
             required: [.shoulder, .elbow, .wrist, .hip],
             metric: { p, _ in p.bothSides { p.elbowAngle($0) } },
             restIsHigh: true, rest: 160, peak: 70,
             partial: "Pull until your chin clears the bar.",
             rules: [torso(id: "pull.swing", lean: 25, cue: "Stop swinging. Pull with your back.")],
             steps: [
                "Hang with straight arms, thumbs around the bar.",
                "Brace, then pull your elbows down toward your ribs.",
                "Chin clears the bar. Shoulders stay away from your ears.",
                "Lower until the arms are straight again."
             ]),
        reps(id: "goodMorning", name: "Good Morning",
             place: .gym, equipment: "Barbell · Bodyweight",
             muscles: ["Hamstrings", "Glutes", "Back"],
             symbol: "figure.strengthtraining.traditional",
             required: [.shoulder, .hip, .knee, .ankle],
             metric: { p, s in p.hipAngle(s) },
             restIsHigh: true, rest: 165, peak: 110,
             partial: "Hinge a little further. Feel the hamstrings.",
             slow: 1.0,
             rules: [FormRule(id: "gm.knee", cue: String(localized: "Soften the knees. This is a hinge, not a squat"), when: .bottom, penalty: 15, highlight: [.knee]) { p, s in (p.kneeAngle(s) ?? 180) < 145 }],
             steps: [
                "Bar on your upper back, or hands behind your head.",
                "Soft knees, then push your hips straight back.",
                "Torso tips forward until the hamstrings load.",
                "Squeeze the glutes to stand tall."
             ],
             note: "A phone camera can't reliably see spinal rounding. Use a weight you can hold with a flat back."),
        reps(id: "frontRaise", name: "Front Raise",
             place: .gym, equipment: "Dumbbells",
             muscles: ["Front delts"],
             symbol: "figure.arms.open",
             camera: .front, bothSides: true,
             required: [.shoulder, .elbow, .hip],
             metric: { p, _ in p.bothSides { p.armToTorso($0) } },
             restIsHigh: false, rest: 20, peak: 85,
             partial: "Raise to shoulder height.",
             eccentric: .towardRest, slow: 0.8,
             rules: [FormRule(id: "front.high", cue: String(localized: "Stop at shoulder height"), penalty: 10, highlight: [.elbow, .shoulder], bothSides: true) { p, _ in (p.bothSides { p.armToTorso($0) } ?? 0) > 120 }],
             steps: [
                "Stand tall with light dumbbells in front of your thighs.",
                "Soft elbows. Raise the weights forward.",
                "Stop when your arms reach shoulder height.",
                "Lower slowly. No swinging."
             ]),
        reps(id: "deadBug", name: "Dead Bug",
             equipment: "Mat",
             muscles: ["Core"],
             symbol: "figure.core.training",
             required: [.shoulder, .hip, .knee, .ankle],
             metric: lying({ p, s in p.kneeAngle(s) }, rest: 95),
             restIsHigh: false, rest: 95, peak: 160,
             partial: "Straighten the leg until the knee is almost locked.",
             steps: [
                "Lie on your back, arms to the ceiling, knees over hips.",
                "Brace, then reach one leg long and the opposite arm overhead.",
                "The lower back stays glued down.",
                "Return and switch sides. Each reach counts."
             ]),
        hold(id: "birdDog", name: "Bird Dog",
             equipment: "Mat",
             muscles: ["Core", "Glutes", "Back"],
             symbol: "figure.mind.and.body",
             required: [.shoulder, .elbow, .hip, .knee],
             inPosition: { p, s in
                (p.bodyTilt(s) ?? 0) > 50 && (p.kneeAngle(s) ?? 0) > 150 && (p.elbowAngle(s) ?? 0) > 140
             },
             position: "On all fours, reach one arm and the opposite leg long.",
             steps: [
                "Hands under shoulders, knees under hips.",
                "Reach the arm and the opposite leg out until they're straight.",
                "Hips stay level. Don't sag.",
                "Hold, then switch sides."
             ],
             note: "Film from the side of the arm and leg you are extending."),
        hold(id: "superman", name: "Superman",
             equipment: "Mat",
             muscles: ["Lower back", "Glutes"],
             symbol: "figure.cooldown",
             required: [.shoulder, .hip, .knee, .ankle],
             inPosition: { p, s in
                (p.bodyTilt(s) ?? 0) > 55 && (p.hipAngle(s) ?? 0) > 155 && (p.kneeAngle(s) ?? 0) > 150
             },
             position: "Lie face down and lift your chest and legs.",
             rules: [FormRule(id: "super.low", cue: String(localized: "Lift your chest and thighs a little higher"), penalty: 0, highlight: [.shoulder, .hip]) { p, s in
                (p.bodyTilt(s) ?? 0) > 55 && (p.hipAngle(s) ?? 180) < 165
             }],
             steps: [
                "Lie face down, arms reaching forward.",
                "Lift your chest, arms, and straight legs off the floor.",
                "Look down. Squeeze the glutes.",
                "Hold, then lower with control."
             ])
    ]

    // MARK: - 6-Pack (Pro)

    private static let sixPack: [ExerciseSpec] = [
        reps(id: "crunch", name: "Crunch", programs: [.sixPack],
             equipment: "Mat", muscles: ["Abs"], symbol: "figure.core.training",
             required: [.shoulder, .hip, .knee],
             metric: lying({ p, s in p.hipAngle(s) }, rest: 145),
             restIsHigh: true, rest: 145, peak: 100,
             partial: "Curl your shoulders higher off the floor.",
             eccentric: .towardRest,
             rules: [FormRule(id: "crunch.neck", cue: String(localized: "Curl the ribs, not the neck"), when: .bottom, penalty: 10, highlight: [.shoulder]) { p, s in (p.hipAngle(s) ?? 180) < 80 }],
             steps: [
                "Lie on your back, knees bent, feet flat.",
                "Hands light at your temples. Don't pull the head.",
                "Curl the ribs toward the pelvis.",
                "Lower until the shoulder blades touch, then go again."
             ]),
        reps(id: "sitUp", name: "Sit-up", programs: [.sixPack],
             equipment: "Mat", muscles: ["Abs", "Hip flexors"], symbol: "figure.core.training",
             required: [.shoulder, .hip, .knee],
             metric: lying({ p, s in p.hipAngle(s) }, rest: 145),
             restIsHigh: true, rest: 145, peak: 70,
             partial: "Come all the way up to sitting.",
             eccentric: .towardRest,
             steps: [
                "Lie on your back, knees bent.",
                "Brace, then sit all the way up.",
                "Reach toward your knees at the top.",
                "Lower one vertebra at a time."
             ]),
        reps(id: "bicycleCrunch", name: "Bicycle Crunch", programs: [.sixPack],
             equipment: "Mat", muscles: ["Abs", "Obliques"], symbol: "figure.core.training",
             required: [.shoulder, .hip, .knee],
             metric: lying({ p, _ in [p.kneeAngle(.left), p.kneeAngle(.right)].compactMap { $0 }.min() }, rest: 140),
             restIsHigh: true, rest: 140, peak: 70,
             partial: "Bring the knee closer to the opposite elbow.",
             steps: [
                "Lie on your back, hands at your temples, legs up.",
                "Twist one elbow toward the opposite knee.",
                "Straighten the other leg long.",
                "Switch sides. Each twist counts."
             ]),
        reps(id: "legRaise", name: "Leg Raise", programs: [.sixPack],
             equipment: "Mat", muscles: ["Lower abs", "Hip flexors"], symbol: "figure.core.training",
             required: [.shoulder, .hip, .knee, .ankle],
             metric: lying({ p, s in p.hipAngle(s) }, rest: 160),
             restIsHigh: true, rest: 160, peak: 95,
             partial: "Lift your legs until they're vertical.",
             eccentric: .towardRest, slow: 0.8,
             rules: [FormRule(id: "leg.back", cue: String(localized: "Press your lower back into the floor"), penalty: 15, highlight: [.hip]) { p, s in (p.bodyLineOffset(s) ?? 0) > 0.08 }],
             steps: [
                "Lie on your back, legs straight, hands by your hips.",
                "Brace, then lift the legs to about 90°.",
                "Knees stay nearly straight.",
                "Lower slowly until the heels hover."
             ]),
        reps(id: "reverseCrunch", name: "Reverse Crunch", programs: [.sixPack],
             equipment: "Mat", muscles: ["Lower abs"], symbol: "figure.core.training",
             required: [.shoulder, .hip, .knee],
             metric: lying({ p, s in p.hipAngle(s) }, rest: 130),
             restIsHigh: true, rest: 130, peak: 85,
             partial: "Curl your hips up off the floor.",
             eccentric: .towardRest,
             steps: [
                "Lie on your back, knees bent at 90°, feet up.",
                "Curl the pelvis toward the ribs.",
                "Hips leave the floor. Knees stay bent.",
                "Lower with control. Don't swing the legs."
             ]),
        reps(id: "mountainClimber", name: "Mountain Climber", programs: [.sixPack, .weightLoss],
             equipment: "Bodyweight", muscles: ["Core", "Hip flexors", "Shoulders"],
             symbol: "figure.highintensity.intervaltraining",
             required: [.shoulder, .hip, .knee, .ankle],
             metric: lying({ p, _ in [p.kneeAngle(.left), p.kneeAngle(.right)].compactMap { $0 }.min() }, rest: 155, minTilt: 50),
             restIsHigh: true, rest: 155, peak: 85,
             partial: "Drive the knee further toward your chest.",
             rules: [sag(id: "climb.sag", cue: "Hips are sagging. Hold the plank.")],
             steps: [
                "Start in a straight-arm plank.",
                "Drive one knee toward the chest.",
                "Switch legs. Hips stay level.",
                "Each knee drive counts."
             ]),
        hold(id: "hollowHold", name: "Hollow Hold", programs: [.sixPack],
             equipment: "Mat", muscles: ["Abs"], symbol: "figure.core.training",
             required: [.shoulder, .hip, .knee, .ankle],
             inPosition: { p, s in
                (p.bodyTilt(s) ?? 0) > 35 && (p.hipAngle(s) ?? 0) > 140 && (p.kneeAngle(s) ?? 0) > 150
             },
             position: "Lie on your back, lower back down, arms and legs long.",
             rules: [FormRule(id: "hollow.back", cue: String(localized: "Press your lower back into the floor"), penalty: 0, highlight: [.hip]) { p, s in (p.bodyLineOffset(s) ?? 0) > 0.06 }],
             steps: [
                "Lie on your back and flatten the lower back.",
                "Reach the arms overhead and the legs long, slightly off the floor.",
                "Ribs stay down. Breathe.",
                "Spotter times only the seconds your back stays down."
             ]),
        hold(id: "sidePlank", name: "Side Plank", programs: [.sixPack],
             equipment: "Mat", muscles: ["Obliques", "Shoulders", "Glutes"],
             symbol: "figure.core.training",
             required: [.shoulder, .hip, .ankle],
             inPosition: { p, s in (p.bodyTilt(s) ?? 0) > 55 },
             position: "Stack your feet and lift into a side plank.",
             rules: [sag(id: "side.sag", amount: 0.08, cue: "Hips are dropping. Lift them in line with your body.")],
             steps: [
                "Lie on your side, elbow under the shoulder.",
                "Stack the feet and lift the hips.",
                "Body in one straight line. Top hand can rest on the hip.",
                "Hold, then switch sides."
             ]),
        reps(id: "vUp", name: "V-up", programs: [.sixPack],
             equipment: "Mat", muscles: ["Abs", "Hip flexors"], symbol: "figure.core.training",
             required: [.shoulder, .hip, .knee, .ankle],
             metric: lying({ p, s in p.hipAngle(s) }, rest: 150),
             restIsHigh: true, rest: 150, peak: 75,
             partial: "Reach your hands all the way to your toes.",
             eccentric: .towardRest,
             steps: [
                "Lie flat, arms overhead, legs straight.",
                "Lift the arms and the legs together into a V.",
                "Reach toward your toes at the top.",
                "Lower with control until you're long again."
             ]),
        reps(id: "flutterKick", name: "Flutter Kick", programs: [.sixPack],
             equipment: "Mat", muscles: ["Lower abs"], symbol: "figure.pool.swim",
             required: [.shoulder, .hip, .knee, .ankle],
             metric: lying({ p, s in p.hipAngle(s) }, rest: 160),
             restIsHigh: true, rest: 160, peak: 130,
             partial: "Kick from the hip, legs long.",
             rules: [FormRule(id: "flutter.knee", cue: String(localized: "Keep the legs straight"), penalty: 10, highlight: [.knee]) { p, s in (p.kneeAngle(s) ?? 180) < 150 }],
             steps: [
                "Lie on your back, hands under your hips, legs straight.",
                "Hover the heels and kick up and down in a small range.",
                "Lower back stays down.",
                "Each kick counts."
             ]),
        reps(id: "toeReach", name: "Toe Reach", programs: [.sixPack],
             equipment: "Mat", muscles: ["Abs"], symbol: "figure.core.training",
             required: [.shoulder, .hip, .knee, .ankle],
             metric: lying({ p, s in p.hipAngle(s) }, rest: 150),
             restIsHigh: true, rest: 150, peak: 85,
             partial: "Reach higher toward your toes.",
             steps: [
                "Lie on your back and lift the legs vertical.",
                "Reach both hands toward the toes.",
                "Shoulder blades leave the floor.",
                "Lower the shoulders and reach again."
             ]),
        reps(id: "russianTwist", name: "Russian Twist", programs: [.sixPack],
             equipment: "Mat", muscles: ["Obliques"], symbol: "figure.core.training",
             camera: .front,
             required: [.shoulder, .hip, .knee],
             metric: { p, s in p.torsoLean(s) },
             restIsHigh: false, rest: 8, peak: 26,
             partial: "Rotate further to the side.",
             steps: [
                "Sit with knees bent and heels light on the floor.",
                "Lean the chest back slightly and brace.",
                "Rotate the shoulders to one side, then back to center.",
                "Each side counts. Face the camera."
             ])
    ]

    // MARK: - Weight Loss (Pro)

    private static let weightLoss: [ExerciseSpec] = [
        reps(id: "jumpingJack", name: "Jumping Jack", programs: [.weightLoss],
             equipment: "Bodyweight", muscles: ["Full body", "Shoulders"],
             symbol: "figure.mixed.cardio", camera: .front, bothSides: true,
             required: [.shoulder, .elbow, .hip, .ankle],
             metric: { p, _ in p.bothSides { p.armToTorso($0) } },
             restIsHigh: false, rest: 25, peak: 140,
             partial: "Take the arms all the way overhead.",
             eccentric: .towardRest,
             rules: [FormRule(id: "jack.even", cue: String(localized: "Raise both arms together"), penalty: 10, highlight: [.wrist], bothSides: true) { p, _ in (p.wristImbalance ?? 0) > 0.25 }],
             steps: [
                "Stand tall, arms at your sides.",
                "Jump your feet out as the arms swing overhead.",
                "Land softly.",
                "Jump back in as the arms come down."
             ]),
        reps(id: "highKnees", name: "High Knees", programs: [.weightLoss],
             equipment: "Bodyweight", muscles: ["Hip flexors", "Quads", "Core"],
             symbol: "figure.highintensity.intervaltraining", camera: .front,
             required: [.shoulder, .hip, .knee, .ankle],
             metric: { p, _ in [p.kneeAngle(.left), p.kneeAngle(.right)].compactMap { $0 }.min() },
             restIsHigh: true, rest: 155, peak: 85,
             partial: "Drive the knee higher.",
             rules: [torso(id: "knees.tall", lean: 22, cue: "Stay tall. Don't lean back.")],
             steps: [
                "Stand tall and run in place.",
                "Drive one knee up to about hip height.",
                "Land on the ball of the foot and switch.",
                "Each knee lift counts."
             ]),
        reps(id: "squatJump", name: "Squat Jump", programs: [.weightLoss],
             equipment: "Bodyweight", muscles: ["Quads", "Glutes"],
             symbol: "figure.highintensity.intervaltraining",
             required: [.shoulder, .hip, .knee, .ankle],
             metric: { p, s in p.hipDepth(s) },
             restIsHigh: true, rest: 0.75, peak: 0.2,
             partial: "Squat deeper before you leave the floor.",
             rules: [torso(id: "sjump.chest", lean: 55, cue: "Keep your chest up as you dip.")],
             steps: [
                "Feet about shoulder-width.",
                "Sit into a squat, then jump.",
                "Land softly and stick the landing.",
                "Reset your feet before the next one."
             ],
             note: "Spotter counts the squat. Land quietly."),
        reps(id: "burpee", name: "Burpee", programs: [.weightLoss],
             equipment: "Bodyweight", muscles: ["Full body"],
             symbol: "figure.highintensity.intervaltraining",
             required: [.shoulder, .hip, .knee, .ankle],
             metric: { p, s in p.bodyTilt(s) },
             restIsHigh: false, rest: 18, peak: 70,
             partial: "Get all the way down to the floor, then stand.",
             rules: [sag(id: "burpee.sag", cue: "Hips are sagging in the plank.")],
             steps: [
                "Stand tall, then squat and put your hands on the floor.",
                "Jump or step the feet back to a plank.",
                "Jump or step the feet back in.",
                "Stand tall to finish the rep."
             ]),
        reps(id: "buttKick", name: "Butt Kick", programs: [.weightLoss],
             equipment: "Bodyweight", muscles: ["Hamstrings", "Quads"],
             symbol: "figure.run", camera: .side,
             required: [.hip, .knee, .ankle],
             metric: { p, _ in [p.kneeAngle(.left), p.kneeAngle(.right)].compactMap { $0 }.min() },
             restIsHigh: true, rest: 165, peak: 75,
             partial: "Kick the heel closer to your glute.",
             rules: [torso(id: "butt.tall", lean: 22, cue: "Stay tall while you kick.")],
             steps: [
                "Jog in place, tall through the chest.",
                "Kick one heel up toward the glute.",
                "Switch legs. Don't lean forward.",
                "Each kick counts."
             ]),
        reps(id: "skater", name: "Skater", programs: [.weightLoss],
             equipment: "Bodyweight", muscles: ["Glutes", "Quads", "Balance"],
             symbol: "figure.dance",
             required: [.shoulder, .hip, .knee, .ankle],
             metric: { p, _ in [p.kneeAngle(.left), p.kneeAngle(.right)].compactMap { $0 }.min() },
             restIsHigh: true, rest: 155, peak: 115,
             partial: "Sit deeper as you land.",
             rules: [torso(id: "skater.chest", lean: 40, cue: "Chest stays up over the landing leg.")],
             steps: [
                "Stand on one leg, the other reaching behind.",
                "Bound sideways and land on the other foot.",
                "Sit into that hip. The trailing leg swings behind.",
                "Bound back. Each landing counts."
             ]),
        reps(id: "jumpLunge", name: "Jump Lunge", programs: [.weightLoss],
             equipment: "Bodyweight", muscles: ["Quads", "Glutes"],
             symbol: "figure.cross.training",
             required: [.shoulder, .hip, .knee, .ankle],
             metric: { p, _ in [p.kneeAngle(.left), p.kneeAngle(.right)].compactMap { $0 }.min() },
             restIsHigh: true, rest: 155, peak: 105,
             partial: "Drop deeper before you jump.",
             rules: [torso(id: "jlunge.torso", lean: 30, cue: "Stay tall as you land.")],
             steps: [
                "Split your stance and lower into a lunge.",
                "Jump and switch legs in the air.",
                "Land softly with both knees bent.",
                "Each switch counts."
             ])
    ]

    // MARK: - Build Muscle (Pro)

    private static let buildMuscle: [ExerciseSpec] = [
        reps(id: "diamondPushUp", name: "Diamond Push-up", programs: [.buildMuscle],
             equipment: "Bodyweight", muscles: ["Triceps", "Chest"],
             symbol: "figure.strengthtraining.traditional",
             required: [.shoulder, .elbow, .wrist, .hip],
             metric: { p, s in p.elbowAngle(s) },
             restIsHigh: true, rest: 150, peak: 90,
             partial: "Lower until your chest meets your hands.",
             rules: [FormRule(id: "diamond.elbow", cue: String(localized: "Keep your elbows close to your ribs"), when: .bottom, penalty: 15, highlight: [.elbow]) { p, s in (p.armToTorso(s) ?? 0) > 50 }, sag(id: "diamond.sag")],
             steps: [
                "Hands together under your chest, thumbs and index fingers touching.",
                "Body in one line.",
                "Lower until the elbows pass 90°.",
                "Press back up. Elbows stay tucked."
             ]),
        reps(id: "pikePushUp", name: "Pike Push-up", programs: [.buildMuscle],
             equipment: "Bodyweight", muscles: ["Shoulders", "Triceps"],
             symbol: "figure.yoga",
             required: [.shoulder, .elbow, .hip, .ankle],
             metric: { p, s in p.elbowAngle(s) },
             restIsHigh: true, rest: 155, peak: 95,
             partial: "Lower the crown of your head toward the floor.",
             rules: [FormRule(id: "pike.hips", cue: String(localized: "Pike your hips higher"), penalty: 15, highlight: [.hip]) { p, s in (p.bodyLineOffset(s) ?? 0) > -0.04 }],
             steps: [
                "Start in a downward dog, hips high, hands under shoulders.",
                "Bend the elbows and lower the head toward the floor.",
                "Hips stay up. Don't collapse into a regular push-up.",
                "Press back to the pike."
             ]),
        reps(id: "inclinePushUp", name: "Incline Push-up", programs: [.buildMuscle],
             equipment: "Bench · Counter", muscles: ["Chest", "Shoulders", "Triceps"],
             symbol: "figure.strengthtraining.traditional",
             required: [.shoulder, .elbow, .wrist, .hip],
             metric: { p, s in p.elbowAngle(s) },
             restIsHigh: true, rest: 155, peak: 110,
             partial: "Lower your chest toward the bench.",
             rules: [sag(id: "incline.sag"), pike(id: "incline.pike")],
             steps: [
                "Hands on a bench or counter, body in one line.",
                "The higher the hands, the easier the push-up.",
                "Lower the chest toward the edge.",
                "Press until the arms are straight."
             ]),
        reps(id: "declinePushUp", name: "Decline Push-up", programs: [.buildMuscle],
             equipment: "Bench", muscles: ["Upper chest", "Shoulders", "Triceps"],
             symbol: "figure.strengthtraining.traditional",
             required: [.shoulder, .elbow, .wrist, .hip, .ankle],
             metric: { p, s in p.elbowAngle(s) },
             restIsHigh: true, rest: 150, peak: 85,
             partial: "Lower your chest closer to the floor.",
             rules: [sag(id: "decline.sag")],
             steps: [
                "Feet on a bench, hands on the floor.",
                "Body in one line, glutes tight.",
                "Lower until the elbows pass 90°.",
                "Press the floor away."
             ]),
        reps(id: "bulgarianSplit", name: "Bulgarian Split Squat", programs: [.buildMuscle],
             place: .gym, equipment: "Bench · Dumbbells",
             muscles: ["Quads", "Glutes"], symbol: "figure.cross.training",
             required: [.shoulder, .hip, .knee, .ankle],
             metric: { p, _ in [p.kneeAngle(.left), p.kneeAngle(.right)].compactMap { $0 }.min() },
             restIsHigh: true, rest: 155, peak: 100,
             partial: "Lower the back knee closer to the floor.",
             rules: [torso(id: "bulg.torso", lean: 30, cue: "Stay tall over the front foot.")],
             steps: [
                "Rear foot on a bench behind you.",
                "Front foot far enough that the knee can bend freely.",
                "Lower until the front thigh is about parallel.",
                "Drive through the front heel. Finish the set, then switch."
             ]),
        reps(id: "sumoSquat", name: "Sumo Squat", programs: [.buildMuscle],
             equipment: "Bodyweight · Dumbbell",
             muscles: ["Glutes", "Adductors", "Quads"],
             symbol: "figure.strengthtraining.functional", camera: .front,
             required: [.shoulder, .hip, .knee, .ankle],
             metric: { p, s in p.hipDepth(s) },
             restIsHigh: true, rest: 0.75, peak: 0.18,
             partial: "Sit deeper between your heels.",
             rules: [FormRule(id: "sumo.knees", cue: String(localized: "Push your knees out over your toes"), when: .bottom, penalty: 20, highlight: [.knee], bothSides: true) { p, _ in p.kneesCaving() }],
             steps: [
                "Feet wide, toes turned out.",
                "Hold a weight at your chest if you have one.",
                "Sit straight down between your heels.",
                "Drive the floor away and stand tall."
             ]),
        reps(id: "hammerCurl", name: "Hammer Curl", programs: [.buildMuscle],
             place: .gym, equipment: "Dumbbells",
             muscles: ["Biceps", "Forearms"], symbol: "dumbbell.fill",
             required: [.shoulder, .elbow, .wrist, .hip],
             metric: { p, s in p.elbowAngle(s) },
             restIsHigh: true, rest: 145, peak: 65,
             partial: "Curl all the way up.",
             eccentric: .towardRest, slow: 0.8,
             rules: [
                FormRule(id: "hammer.elbow", cue: String(localized: "Pin your elbows to your sides"), penalty: 15, highlight: [.elbow, .shoulder]) { p, s in (p.armToTorso(s) ?? 0) > 35 },
                torso(id: "hammer.swing", lean: 15, cue: "Stop swinging. Stand tall.")
             ],
             steps: [
                "Stand tall, palms facing each other.",
                "Curl without rotating the wrists.",
                "Squeeze at the top. Elbows stay still.",
                "Lower slowly."
             ]),
        reps(id: "uprightRow", name: "Upright Row", programs: [.buildMuscle],
             place: .gym, equipment: "Dumbbells · Barbell",
             muscles: ["Side delts", "Upper traps"], symbol: "dumbbell.fill",
             camera: .front, bothSides: true,
             required: [.shoulder, .elbow, .wrist, .hip],
             metric: { p, _ in p.bothSides { p.elbowAngle($0) } },
             restIsHigh: true, rest: 155, peak: 75,
             partial: "Pull until your elbows are in line with your shoulders.",
             eccentric: .towardRest, slow: 0.8,
             rules: [torso(id: "upright.swing", lean: 15, cue: "Stop leaning back to swing the weight.")],
             steps: [
                "Stand tall, weights in front of the thighs.",
                "Lead with the elbows and pull them up and out.",
                "Stop when the elbows reach shoulder height.",
                "Lower slowly. Don't shrug the weight to your chin."
             ]),
        reps(id: "rearDeltFly", name: "Rear Delt Fly", programs: [.buildMuscle],
             place: .gym, equipment: "Dumbbells",
             muscles: ["Rear delts", "Upper back"], symbol: "figure.arms.open",
             camera: .front, bothSides: true,
             required: [.shoulder, .elbow, .hip],
             metric: { p, _ in
                guard (p.torsoLean(.left) ?? p.torsoLean(.right) ?? 0) > 30 else { return 15 }
                return p.bothSides { p.armToTorso($0) }
             },
             restIsHigh: false, rest: 15, peak: 70,
             partial: "Raise your arms out until they're in line with your back.",
             eccentric: .towardRest, slow: 0.8,
             rules: [FormRule(id: "rear.hinge", cue: String(localized: "Stay hinged. Chest toward the floor"), penalty: 15, highlight: [.shoulder, .hip]) { p, s in (p.torsoLean(s) ?? 0) < 30 }],
             steps: [
                "Hinge until your chest faces the floor, soft knees.",
                "Light dumbbells hanging under the shoulders.",
                "Raise the arms out to the sides, elbows softly bent.",
                "Lower slowly. Torso stays still."
             ]),
        reps(id: "facePull", name: "Face Pull", programs: [.buildMuscle],
             place: .gym, equipment: "Cable · Band",
             muscles: ["Rear delts", "Upper back"], symbol: "figure.arms.open",
             camera: .front, bothSides: true,
             required: [.shoulder, .elbow, .wrist, .hip],
             metric: { p, _ in
                guard (p.torsoLean(.left) ?? p.torsoLean(.right) ?? 0) > 15 else { return 20 }
                return p.bothSides { p.armToTorso($0) }
             },
             restIsHigh: false, rest: 20, peak: 80,
             partial: "Pull your hands back toward your face.",
             eccentric: .towardRest,
             rules: [FormRule(id: "face.elbow", cue: String(localized: "Bend your elbows and pull toward your face"), penalty: 15, highlight: [.elbow]) { p, _ in (p.bothSides { p.elbowAngle($0) } ?? 0) > 155 }],
             steps: [
                "Band or cable at face height.",
                "Pull the hands toward your ears, elbows high.",
                "Squeeze the shoulder blades. Don't turn it into a shrug.",
                "Return until the arms are almost straight."
             ]),
        reps(id: "tricepKickback", name: "Tricep Kickback", programs: [.buildMuscle],
             place: .gym, equipment: "Dumbbell",
             muscles: ["Triceps"], symbol: "dumbbell.fill",
             required: [.shoulder, .elbow, .wrist, .hip],
             metric: { p, s in
                guard (p.torsoLean(s) ?? 0) > 30 else { return 95 }
                return p.elbowAngle(s)
             },
             restIsHigh: false, rest: 95, peak: 160,
             partial: "Straighten the arm all the way back.",
             eccentric: .towardRest, slow: 0.8,
             rules: [FormRule(id: "kick.hinge", cue: String(localized: "Hinge over and pin your upper arm"), penalty: 15, highlight: [.shoulder, .hip]) { p, s in (p.torsoLean(s) ?? 0) < 30 }],
             steps: [
                "Hinge, upper arm pinned to your side.",
                "Start with the elbow bent about 90°.",
                "Straighten the arm until it lines up with your torso.",
                "Bend slowly. The upper arm doesn't swing."
             ]),
        reps(id: "chinUp", name: "Chin-up", programs: [.buildMuscle],
             place: .gym, equipment: "Pull-up bar",
             muscles: ["Biceps", "Lats"], symbol: "figure.climbing",
             camera: .front, bothSides: true,
             required: [.shoulder, .elbow, .wrist, .hip],
             metric: { p, _ in p.bothSides { p.elbowAngle($0) } },
             restIsHigh: true, rest: 160, peak: 70,
             partial: "Pull until your chin clears the bar.",
             rules: [torso(id: "chin.swing", lean: 25, cue: "Stop kicking. Pull with control.")],
             steps: [
                "Hang with palms facing you, arms straight.",
                "Pull your elbows down until the chin clears the bar.",
                "Pause without shrugging.",
                "Lower until the arms are straight."
             ],
             note: "Same shape as a pull-up, with an underhand grip.")
    ]

    // MARK: - Get Strong (Pro)

    private static let getStrong: [ExerciseSpec] = [
        reps(id: "deadlift", name: "Deadlift", programs: [.getStrong],
             place: .gym, equipment: "Barbell",
             muscles: ["Hamstrings", "Glutes", "Back"],
             symbol: "figure.strengthtraining.traditional",
             required: [.shoulder, .wrist, .hip, .knee, .ankle],
             metric: { p, s in p.hipAngle(s) },
             restIsHigh: true, rest: 165, peak: 95,
             partial: "Stand all the way tall at the top.",
             slow: 1.0,
             rules: [FormRule(id: "dl.bar", cue: String(localized: "Keep the bar close to your legs"), when: .bottom, penalty: 15, highlight: [.wrist]) { p, s in
                guard let w = p.px(s.wrist), let k = p.px(s.knee), let torso = p.torsoLength, torso > 0 else { return false }
                return abs(w.x - k.x) / torso > 0.45
             }],
             steps: [
                "Feet under the bar, about hip-width.",
                "Hinge and bend the knees to grip the bar.",
                "Chest up, bar against the legs, then stand.",
                "Lower it along the legs until the plates meet the floor."
             ],
             note: "A phone camera can't reliably see spinal rounding. Keep a brace and a weight you can hold still."),
        reps(id: "frontSquat", name: "Front Squat", programs: [.getStrong],
             place: .gym, equipment: "Barbell · Dumbbells",
             muscles: ["Quads", "Core"], symbol: "figure.strengthtraining.functional",
             required: [.shoulder, .hip, .knee, .ankle],
             metric: { p, s in p.hipDepth(s) },
             restIsHigh: true, rest: 0.75, peak: 0.18,
             partial: "Sit deeper. Thighs toward parallel.",
             rules: [torso(id: "front.chest", lean: 42, when: .bottom, cue: "Elbows up. Keep the chest tall.")],
             steps: [
                "Bar on the front of the shoulders, elbows high.",
                "Feet about shoulder-width.",
                "Sit straight down between your heels.",
                "Drive up. Elbows stay up the whole way."
             ]),
        reps(id: "pushPress", name: "Push Press", programs: [.getStrong],
             place: .gym, equipment: "Barbell · Dumbbells",
             muscles: ["Shoulders", "Triceps", "Legs"],
             symbol: "figure.strengthtraining.traditional", camera: .front, bothSides: true,
             required: [.shoulder, .elbow, .wrist, .hip],
             metric: { p, _ in p.bothSides { p.elbowAngle($0) } },
             restIsHigh: false, rest: 100, peak: 160,
             partial: "Lock the weight out overhead.",
             eccentric: .towardRest, slow: 0.8,
             rules: [FormRule(id: "ppress.even", cue: String(localized: "Press both arms evenly"), penalty: 15, highlight: [.wrist, .elbow], bothSides: true) { p, _ in (p.wristImbalance ?? 0) > 0.18 }],
             steps: [
                "Weights at the shoulders, elbows under the wrists.",
                "Dip the knees a little, then drive up.",
                "Press to a full lockout as the legs straighten.",
                "Lower to the shoulders with control."
             ]),
        reps(id: "pendlayRow", name: "Pendlay Row", programs: [.getStrong],
             place: .gym, equipment: "Barbell",
             muscles: ["Upper back", "Lats"], symbol: "figure.rowing",
             required: [.shoulder, .elbow, .wrist, .hip, .knee],
             metric: { p, s in
                guard (p.torsoLean(s) ?? 0) > 40 else { return 155 }
                return p.elbowAngle(s)
             },
             restIsHigh: true, rest: 155, peak: 70,
             partial: "Pull the bar into your lower ribs.",
             eccentric: .towardRest,
             rules: [FormRule(id: "pendlay.hinge", cue: String(localized: "Chest stays toward the floor"), penalty: 15, highlight: [.shoulder, .hip]) { p, s in (p.torsoLean(s) ?? 90) < 50 }],
             steps: [
                "Hinge until your back is near parallel, bar on the floor.",
                "Pull the bar into the lower ribs.",
                "Lower it back to the floor and pause.",
                "Torso stays still between reps."
             ],
             note: "A phone camera can't reliably see if your back rounds. Keep a flat back.")
    ]

    // MARK: - Glutes (Pro)

    private static let glutes: [ExerciseSpec] = [
        reps(id: "donkeyKick", name: "Donkey Kick", programs: [.glutes],
             equipment: "Mat", muscles: ["Glutes"], symbol: "figure.strengthtraining.functional",
             required: [.shoulder, .hip, .knee],
             metric: lying({ p, s in p.hipAngle(s) }, rest: 100, minTilt: 40),
             restIsHigh: false, rest: 100, peak: 165,
             partial: "Kick the heel up and squeeze the glute.",
             eccentric: .towardRest,
             steps: [
                "On all fours, hands under shoulders.",
                "Knee bent, kick one heel toward the ceiling.",
                "Squeeze at the top. Don't arch the lower back.",
                "Lower the knee and go again. Switch sides."
             ]),
        reps(id: "fireHydrant", name: "Fire Hydrant", programs: [.glutes],
             equipment: "Mat", muscles: ["Glutes"], symbol: "figure.strengthtraining.functional",
             required: [.shoulder, .hip, .knee, .ankle],
             metric: lying(kneeLift, rest: -0.85, minTilt: 40),
             restIsHigh: false, rest: -0.85, peak: -0.15,
             partial: "Lift the knee higher, out to the side.",
             eccentric: .towardRest,
             steps: [
                "On all fours, knee under the hip.",
                "Keep the knee bent and lift it out to the side.",
                "Stop around hip height. Hips stay square.",
                "Lower and repeat. Switch sides."
             ]),
        reps(id: "frogPump", name: "Frog Pump", programs: [.glutes],
             equipment: "Mat", muscles: ["Glutes"], symbol: "figure.cooldown",
             required: [.shoulder, .hip, .knee],
             metric: lying({ p, s in p.hipAngle(s) }, rest: 115, minTilt: 40),
             restIsHigh: false, rest: 115, peak: 165,
             partial: "Drive the hips higher and squeeze.",
             eccentric: .towardRest,
             steps: [
                "Lie on your back, soles of the feet together, knees out.",
                "Press the hips up.",
                "Squeeze the glutes at the top. Ribs stay down.",
                "Lower with control."
             ]),
        reps(id: "singleLegBridge", name: "Single-leg Glute Bridge", programs: [.glutes],
             equipment: "Mat", muscles: ["Glutes", "Hamstrings"],
             symbol: "figure.cooldown",
             required: [.shoulder, .hip, .knee, .ankle],
             metric: lying({ p, s in p.hipAngle(s) }, rest: 140, minTilt: 40),
             restIsHigh: false, rest: 140, peak: 168,
             partial: "Drive the hips all the way up.",
             eccentric: .towardRest,
             steps: [
                "Lie on your back, one foot flat, the other leg long.",
                "Press through the heel and lift the hips.",
                "Hips stay level. Don't let the free side drop.",
                "Lower slowly. Finish the set, then switch."
             ])
    ]

    // MARK: - Mobility (Pro)

    private static let mobility: [ExerciseSpec] = [
        hold(id: "hipFlexorStretch", name: "Hip Flexor Stretch", programs: [.mobility],
             equipment: "Mat", muscles: ["Hip flexors"], symbol: "figure.flexibility",
             required: [.shoulder, .hip, .knee, .ankle],
             inPosition: { p, s in
                let knee = [p.kneeAngle(.left), p.kneeAngle(.right)].compactMap { $0 }.min() ?? 180
                return knee < 120 && (p.torsoLean(s) ?? 90) < 32
             },
             position: "Half-kneel and shift your hips forward.",
             rules: [torso(id: "flexor.tall", lean: 25, cue: "Stay tall. Tuck the hips under.")],
             steps: [
                "One knee on the floor, the other foot forward.",
                "Squeeze the glute of the back leg and shift forward.",
                "Ribs down. You should feel the front of the back hip.",
                "Hold, then switch sides."
             ]),
        hold(id: "worldsGreatest", name: "World's Greatest Stretch", programs: [.mobility],
             equipment: "Mat", muscles: ["Hips", "Thoracic spine", "Hamstrings"],
             symbol: "figure.flexibility",
             required: [.shoulder, .elbow, .hip, .knee],
             inPosition: { p, s in
                let knee = [p.kneeAngle(.left), p.kneeAngle(.right)].compactMap { $0 }.min() ?? 180
                return knee < 125 && (p.armToTorso(s) ?? 0) > 55
             },
             position: "Lunge, then reach the inside arm toward the ceiling.",
             steps: [
                "Step into a long lunge and put both hands inside the front foot.",
                "Drop the back knee if you need to.",
                "Rotate the chest and reach one arm up.",
                "Hold, then switch sides."
             ]),
        hold(id: "downwardDog", name: "Downward Dog", programs: [.mobility],
             equipment: "Mat", muscles: ["Hamstrings", "Shoulders", "Calves"],
             symbol: "figure.yoga",
             required: [.shoulder, .hip, .knee, .ankle],
             inPosition: { p, s in
                let hip = p.hipAngle(s) ?? 180
                let tilt = p.bodyTilt(s) ?? 0
                return hip < 100 && tilt > 20 && tilt < 80
             },
             position: "Hips high, heels reaching toward the floor.",
             rules: [FormRule(id: "dog.knee", cue: String(localized: "Straighten the legs as far as you can"), penalty: 0, highlight: [.knee]) { p, s in (p.kneeAngle(s) ?? 180) < 150 }],
             steps: [
                "From your hands and knees, lift the hips up and back.",
                "Press the floor away. Head hangs between the arms.",
                "Heels reach toward the floor. A soft knee bend is fine.",
                "Hold and breathe."
             ]),
        hold(id: "hamstringStretch", name: "Hamstring Stretch", programs: [.mobility],
             equipment: "Mat", muscles: ["Hamstrings"], symbol: "figure.flexibility",
             required: [.shoulder, .hip, .knee, .ankle],
             inPosition: { p, s in (p.kneeAngle(s) ?? 0) > 155 && (p.hipAngle(s) ?? 180) < 120 },
             position: "Hinge forward over a straight leg.",
             steps: [
                "One leg straight, the other soft.",
                "Hinge from the hips, chest toward the thigh.",
                "Keep that knee straight. Don't round to chase the toes.",
                "Hold, then switch legs."
             ]),
        reps(id: "catCow", name: "Cat-Cow", programs: [.mobility],
             equipment: "Mat", muscles: ["Spine", "Core"], symbol: "figure.mind.and.body",
             required: [.shoulder, .hip, .knee],
             metric: lying({ p, s in p.hipAngle(s) }, rest: 155, minTilt: 40),
             restIsHigh: true, rest: 155, peak: 105,
             partial: "Round a little further, then arch back.",
             steps: [
                "On all fours, hands under shoulders, knees under hips.",
                "Round the back and tuck the chin.",
                "Then drop the belly and lift the chest.",
                "Each round-and-arch counts as one."
             ]),
        reps(id: "thoracicOpen", name: "Thoracic Open", programs: [.mobility],
             equipment: "Mat", muscles: ["Upper back", "Shoulders"],
             symbol: "figure.flexibility",
             required: [.shoulder, .elbow, .hip, .knee],
             metric: lying({ p, s in p.armToTorso(s) }, rest: 25, minTilt: 40),
             restIsHigh: false, rest: 25, peak: 100,
             partial: "Reach the arm higher toward the ceiling.",
             steps: [
                "On all fours, one hand behind your head.",
                "Rotate the chest and reach that elbow toward the ceiling.",
                "Follow the elbow with your eyes.",
                "Return and repeat, then switch arms."
             ]),
        hold(id: "childsPose", name: "Child's Pose", programs: [.mobility],
             equipment: "Mat", muscles: ["Back", "Hips"], symbol: "figure.yoga",
             required: [.shoulder, .hip, .knee],
             inPosition: { p, s in (p.hipAngle(s) ?? 180) < 80 && (p.kneeAngle(s) ?? 180) < 90 },
             position: "Sit the hips back toward the heels and fold.",
             steps: [
                "Kneel, big toes together, knees apart if that's easier.",
                "Sit the hips toward the heels.",
                "Walk the hands forward and let the chest sink.",
                "Hold and breathe into the back."
             ])
    ]

    // MARK: - Builders

    private static func reps(
        id: String, name: String,
        programs: [ExerciseProgram] = [],
        place: ExerciseCategory = .home,
        equipment: String, muscles: [String], symbol: String,
        camera: CameraAngle = .side, bothSides: Bool = false,
        required: [JointRole],
        metric: @escaping (Pose, Side) -> Double?,
        restIsHigh: Bool, rest: Double, peak: Double,
        partial: String,
        eccentric: RepConfig.Eccentric = .towardPeak,
        slow: Double? = nil,
        rules: [FormRule] = [],
        steps: [String],
        note: String? = nil
    ) -> ExerciseSpec {
        ExerciseSpec(
            id: id,
            name: String(localized: String.LocalizationValue(stringLiteral: name)),
            category: place,
            equipment: String(localized: String.LocalizationValue(stringLiteral: equipment)),
            muscles: muscles.map { String(localized: String.LocalizationValue(stringLiteral: $0)) },
            symbol: symbol,
            camera: camera,
            programs: programs,
            required: required,
            bothSidesRequired: bothSides,
            kind: .reps(RepConfig(
                metric: metric,
                restIsHigh: restIsHigh,
                rest: rest,
                peak: peak,
                partialCue: String(localized: String.LocalizationValue(stringLiteral: partial)),
                eccentric: eccentric,
                minEccentricSeconds: slow)),
            rules: rules,
            steps: steps.map { String(localized: String.LocalizationValue(stringLiteral: $0)) },
            note: note.map { String(localized: String.LocalizationValue(stringLiteral: $0)) })
    }

    private static func hold(
        id: String, name: String,
        programs: [ExerciseProgram] = [],
        place: ExerciseCategory = .home,
        equipment: String, muscles: [String], symbol: String,
        camera: CameraAngle = .side,
        required: [JointRole],
        inPosition: @escaping (Pose, Side) -> Bool,
        position: String,
        rules: [FormRule] = [],
        steps: [String],
        note: String? = nil
    ) -> ExerciseSpec {
        ExerciseSpec(
            id: id,
            name: String(localized: String.LocalizationValue(stringLiteral: name)),
            category: place,
            equipment: String(localized: String.LocalizationValue(stringLiteral: equipment)),
            muscles: muscles.map { String(localized: String.LocalizationValue(stringLiteral: $0)) },
            symbol: symbol,
            camera: camera,
            programs: programs,
            required: required,
            bothSidesRequired: false,
            kind: .hold(HoldConfig(
                inPosition: inPosition,
                positionCue: String(localized: String.LocalizationValue(stringLiteral: position)))),
            rules: rules,
            steps: steps.map { String(localized: String.LocalizationValue(stringLiteral: $0)) },
            note: note.map { String(localized: String.LocalizationValue(stringLiteral: $0)) })
    }

    /// Returns the resting value unless the body is horizontal enough (floor work, plank, all fours).
    private static func lying(_ metric: @escaping (Pose, Side) -> Double?, rest: Double, minTilt: Double = 45) -> (Pose, Side) -> Double? {
        { pose, side in
            guard (pose.bodyTilt(side) ?? 0) >= minTilt else { return rest }
            return metric(pose, side)
        }
    }

    /// Knee height relative to the hip, in shin lengths. About -0.9 when the knee hangs, near 0 at hip height.
    private static func kneeLift(_ pose: Pose, _ side: Side) -> Double? {
        guard let hip = pose.px(side.hip), let knee = pose.px(side.knee), let ankle = pose.px(side.ankle) else { return nil }
        let shin = Geo.distance(knee, ankle)
        guard shin > 1 else { return nil }
        return Double((hip.y - knee.y) / shin)
    }

    private static func torso(id: String, lean: Double, when: FormRule.When = .moving, cue: String = "Stay tall. Keep your chest up.") -> FormRule {
        FormRule(id: id, cue: String(localized: String.LocalizationValue(stringLiteral: cue)), when: when, penalty: 15, highlight: [.shoulder, .hip]) { p, s in
            (p.torsoLean(s) ?? 0) > lean
        }
    }

    private static func sag(id: String, amount: Double = 0.06, cue: String = "Squeeze your glutes. Hips are sagging.") -> FormRule {
        FormRule(id: id, cue: String(localized: String.LocalizationValue(stringLiteral: cue)), penalty: 15, highlight: [.hip]) { p, s in
            (p.bodyLineOffset(s) ?? 0) > amount
        }
    }

    private static func pike(id: String) -> FormRule {
        FormRule(id: id, cue: String(localized: "Lower your hips into a straight line"), penalty: 15, highlight: [.hip]) { p, s in
            (p.bodyLineOffset(s) ?? 0) < -0.08
        }
    }
}
