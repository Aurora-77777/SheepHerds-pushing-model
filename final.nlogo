globals [
  herd-center-x
  herd-center-y
  goal-location
  goal-radius

  ; Group metrics for research analysis
  current-polarization
  current-elongation
  current-cohesion
  barycenter-speed

  ; Data recording for paper writing
  polarization-history
  elongation-history
  cohesion-history
  speed-history

  ; Parameters for analysis
  alignment-strength
  separation-strength
  cohesion-strength
  pdf-update-interval
  pdf-bin-count

  ; Task completion tracking
  completion-time        ; Tick when last sheep entered pen
  ; World dimensions for torus calculations
  torus-world-width
  torus-world-height
]

breed [sheep a-sheep]
breed [dogs a-dog]

sheep-own [
  sheep-speed
  vx vy
  in-pen?              ; Whether in the pen
]

dogs-own [
  mode
  target-sheep
  dog-speed
  vx vy
  lateral-movement
  patrol-angle         ; Patrol angle
  target-x target-y    ; Target position (for smooth movement)
  dog-id              ; Unique dog identifier
  phase-offset         ; Phase offset for zigzag movement
  assigned-sector      ; Assigned sector (angle within 0-360 degree range)

  ; State variables for waiting sheep group response
  last-move-time       ; Last movement time
  waiting-for-response ; Whether waiting for sheep group response
  target-group-center-x ; Target group center X coordinate (for detecting response)
  target-group-center-y ; Target group center Y coordinate (for detecting response)
  response-check-start  ; Start time of waiting for response

  ; Z-pattern sweeping state variables
  zigzag-phase         ; Z-pattern movement phase
  zigzag-direction     ; Z-pattern movement direction (1 or -1)
  current-sweep-center-x ; Current sweep center X coordinate
  current-sweep-center-y ; Current sweep center Y coordinate
  sweep-width          ; Sweep width
  sweep-step           ; Current sweep step
]

to setup
  clear-all
  ; Set up torus world, connecting four boundaries
  set-default-shape sheep "sheep"
  set-default-shape dogs "circle"

  ; Calculate world dimensions for torus calculations
  set torus-world-width max-pxcor - min-pxcor + 1
  set torus-world-height max-pycor - min-pycor + 1

  ; Set parameters
  set alignment-strength 0.4
  set separation-strength 0.6
  set cohesion-strength 0.8
  set pdf-update-interval 20
  set pdf-bin-count 20

  ; Initialize data
  set polarization-history []
  set elongation-history []
  set cohesion-history []
  set speed-history []
  set completion-time 0  ; Initialize completion time

  ; Create sheep
  create-sheep num-sheep [
    setxy random-xcor random-ycor
    set sheep-speed sheep-base-speed
    set color white
    set size 0.8
    set vx 0
    set vy 0
    set heading random 360
    set in-pen? false
  ]
  ; Create sheepdogs - ensure only specified number created
  create-dogs num-dogs [
    setxy (random-float (max-pxcor - min-pxcor) + min-pxcor)
          (random-float (max-pycor - min-pycor) + min-pycor)
    set color red
    set size 1.5
    set mode "collecting"
    set dog-speed dog-base-speed
    set vx 0
    set vy 0
    set lateral-movement 0

    ; Assign unique individual characteristics to each dog
    set dog-id who  ; Use NetLogo's built-in ID
    set phase-offset (who * 90)  ; 90-degree phase difference between dogs, ensuring zigzag movements are not synchronized
    set assigned-sector (who * (360 / num-dogs))  ; Evenly distribute sectors
    set patrol-angle assigned-sector  ; Set initial patrol angle based on assigned sector

    set target-x xcor
    set target-y ycor

    ; Initialize response waiting state variables
    set last-move-time 0
    set waiting-for-response false
    set target-group-center-x 0
    set target-group-center-y 0
    set response-check-start 0

    ; Initialize Z-pattern sweeping state variables
    set zigzag-phase 1
    set zigzag-direction 1
    set current-sweep-center-x 0
    set current-sweep-center-y 0
    set sweep-width 0
    set sweep-step 0
  ]

  ; Set up pen - dynamically adjust size based on sheep count
  ; Place pen at world center
  set goal-location patch 0 0
  ask goal-location [ set pcolor green ]

  ; Calculate appropriate pen radius based on sheep count
  ; Each sheep needs approximately 1 square unit of space, plus some margin
  let required-area count sheep * 1.2  ; Add 20% margin
  let calculated-radius sqrt(required-area / 3.14159)  ; Calculate radius from area

  ; Ensure pen is not too small or too large
  let min-radius 3
  let max-radius 12
  let pen-radius calculated-radius
  if pen-radius < min-radius [ set pen-radius min-radius ]
  if pen-radius > max-radius [ set pen-radius max-radius ]

  ; Update global goal-radius parameter
  set goal-radius pen-radius


  ask patches [
    let patch-dist torus-distance pxcor pycor ([pxcor] of goal-location) ([pycor] of goal-location)
    if patch-dist <= pen-radius [
      set pcolor green
    ]
    if patch-dist <= pen-radius and patch-dist > (pen-radius - 1) [
      set pcolor lime
    ]
  ]

  ; Improve initial distribution: sheep more dispersed, avoid overlap
  ask sheep [
    ; Ensure sheep are not generated inside pen, at least 2 units away from pen perimeter
    let safe-distance pen-radius + 5  ; Increase safe distance from 3 to 5
    let attempts 0
    let valid-position false

    while [not valid-position and attempts < 100] [  ; Increase attempts to 100
      ; Use larger spread range
      let spread-factor 1.5
      setxy (random-float (max-pxcor - min-pxcor) * spread-factor + min-pxcor)
            (random-float (max-pycor - min-pycor) * spread-factor + min-pycor)

      let dist-to-pen torus-distance xcor ycor ([pxcor] of goal-location) ([pycor] of goal-location)
      ; Check distance to other sheep, avoid overlap
      let too-close-to-others false
      let nearby-sheep-check other sheep in-radius 2.5
      if any? nearby-sheep-check [
        set too-close-to-others true
      ]

      if dist-to-pen > safe-distance and not too-close-to-others [
        set valid-position true
      ]
      set attempts attempts + 1
    ]

    ; If no suitable position found, force placement in safe area with spreading
    if not valid-position [
      let angle random 360
      let radius safe-distance + random-float 10  ; Increase random range
      let safe-x [pxcor] of goal-location + radius * cos(angle)
      let safe-y [pycor] of goal-location + radius * sin(angle)

      ; Ensure within world boundaries
      if safe-x > max-pxcor [ set safe-x max-pxcor - 1 ]
      if safe-x < min-pxcor [ set safe-x min-pxcor + 1 ]
      if safe-y > max-pycor [ set safe-y max-pycor - 1 ]
      if safe-y < min-pycor [ set safe-y min-pycor + 1 ]

      setxy safe-x safe-y
    ]
  ]

  ask dogs [
    ; Ensure sheepdogs are not generated inside pen and away from each other
    let dog-safe-distance pen-radius + 8  ; Increase safe distance
    let dog-attempts 0
    let dog-valid-position false

    ; Angle-based dispersion based on dog-id, ensure no overlap
    let base-angle assigned-sector + random-float 60 - 30  ; Add randomness to assigned sector
    let base-radius dog-safe-distance + random-float 8

    while [not dog-valid-position and dog-attempts < 50] [
      ; Use angle dispersion instead of completely random
      let try-x [pxcor] of goal-location + base-radius * cos(base-angle)
      let try-y [pycor] of goal-location + base-radius * sin(base-angle)

      ; Ensure within world boundaries
      if try-x > max-pxcor [ set try-x max-pxcor - 2 ]
      if try-x < min-pxcor [ set try-x min-pxcor + 2 ]
      if try-y > max-pycor [ set try-y max-pycor - 2 ]
      if try-y < min-pycor [ set try-y min-pycor + 2 ]

      setxy try-x try-y

      ; Check distance to other sheepdogs
      let too-close-to-other-dogs false
      let other-dogs other dogs
      if any? other-dogs [
        let min-dog-dist min [torus-distance xcor ycor ([xcor] of myself) ([ycor] of myself)] of other-dogs
        if min-dog-dist < 8 [  ; Minimum distance 8 units
          set too-close-to-other-dogs true
        ]
      ]

      let dist-to-pen torus-distance xcor ycor ([pxcor] of goal-location) ([pycor] of goal-location)
      if dist-to-pen > dog-safe-distance and not too-close-to-other-dogs [
        set dog-valid-position true
      ]

      ; If too close, adjust angle and try again
      set base-angle base-angle + 45
      set base-radius base-radius + 2
      set dog-attempts dog-attempts + 1
    ]

    ; Final guarantee: if still no suitable position found, force dispersion
    if not dog-valid-position [
      let final-angle assigned-sector + (dog-id * 120)  ; Large angle dispersion
      let final-radius dog-safe-distance + (dog-id * 5)
      let final-x [pxcor] of goal-location + final-radius * cos(final-angle)
      let final-y [pycor] of goal-location + final-radius * sin(final-angle)

      ; Ensure within world boundaries
      if final-x > max-pxcor [ set final-x max-pxcor - 2 ]
      if final-x < min-pxcor [ set final-x min-pxcor + 2 ]
      if final-y > max-pycor [ set final-y max-pycor - 2 ]
      if final-y < min-pycor [ set final-y min-pycor + 2 ]

      setxy final-x final-y
    ]
  ]

  ; Relocate any sheep that might be inside pen
  let sheep-in-pen-initial count sheep with [torus-distance xcor ycor ([pxcor] of goal-location) ([pycor] of goal-location) <= pen-radius * 1.08]
  if sheep-in-pen-initial > 0 [
    ask sheep with [torus-distance xcor ycor ([pxcor] of goal-location) ([pycor] of goal-location) <= pen-radius * 1.08] [
      let relocation-attempts 0
      let relocated false

      while [not relocated and relocation-attempts < 50] [
        let escape-angle random 360
        let escape-radius pen-radius + 10 + random-float 20
        let new-x [pxcor] of goal-location + escape-radius * cos(escape-angle)
        let new-y [pycor] of goal-location + escape-radius * sin(escape-angle)

        ; Ensure within world boundaries
        if new-x > max-pxcor [ set new-x max-pxcor - 1 ]
        if new-x < min-pxcor [ set new-x min-pxcor + 1 ]
        if new-y > max-pycor [ set new-y max-pycor - 1 ]
        if new-y < min-pycor [ set new-y min-pycor + 1 ]

        setxy new-x new-y

        let new-dist torus-distance xcor ycor ([pxcor] of goal-location) ([pycor] of goal-location)
        if new-dist > pen-radius + 8 [
          set relocated true
        ]
        set relocation-attempts relocation-attempts + 1
      ]
    ]
  ]

  reset-ticks
end

to go
  ; Update sheep status
  update-sheep-status
  ; Move sheep
  move-sheep
  ; Sheepdog behavior
  ask dogs [ intelligent-shepherding ]
  ; Calculate metrics for research analysis
  calculate-metrics
  record-data

  ; Update PDF plots for data visualization
  if ticks mod pdf-update-interval = 0 and ticks > 0 [
    update-pdfs
  ]

  let pen-radius goal-radius
  let pen-detection-radius pen-radius * 1.08
  let sheep-in-pen count sheep with [
    torus-distance xcor ycor ([pxcor] of goal-location) ([pycor] of goal-location) <= pen-detection-radius
  ]
  ifelse sheep-in-pen = count sheep [
    if completion-time = 0 [
      set completion-time ticks
      ask dogs [ set mode "patrolling" ]
    ]
    if (ticks - completion-time) >= 100 [
      user-message "Congratulations! All sheep have entered the pen!"
      stop
    ]
  ][
    set completion-time 0
  ]
  tick
end

to update-sheep-status
  let pen-radius goal-radius
  ask sheep [
    let was-in-pen in-pen?
    ; Use slightly more generous pen detection for better completion
    let pen-detection-radius pen-radius * 1.08
    ; Use torus distance to determine if inside pen
    set in-pen? (torus-distance xcor ycor ([pxcor] of goal-location) ([pycor] of goal-location) <= pen-detection-radius)

    ; Color coding based on research literature characteristics
    ifelse in-pen? [
      set color gray  ; Settled sheep turn gray
    ] [
      set color white  ; All active sheep are white
    ]
  ]
end

to move-sheep
  ; === Simplified sheep behavior: only basic group behavior, no active movement toward pen ===

  let pen-radius goal-radius
  let pen-detection-radius pen-radius * 1.08
  let sheep-outside sheep with [torus-distance xcor ycor ([pxcor] of goal-location) ([pycor] of goal-location) > pen-detection-radius]

  ; If no sheep outside, stop movement
  if count sheep-outside = 0 [
    set herd-center-x mean [xcor] of sheep
    set herd-center-y mean [ycor] of sheep
    stop
  ]

  ; Use center of sheep outside pen
  set herd-center-x mean [xcor] of sheep-outside
  set herd-center-y mean [ycor] of sheep-outside

  ; Only move sheep outside pen
  ask sheep-outside [
    let move-x 0
    let move-y 0

    ; === 1. Avoid sheepdogs (most important behavior) ===
    let nearby-dogs dogs in-radius sheep-dog-perception-radius
    if any? nearby-dogs [
      ask nearby-dogs [
        let dog-dist torus-distance xcor ycor ([xcor] of myself) ([ycor] of myself)
        if dog-dist > 0.1 [
          let avoid-strength avoidance-strength / dog-dist

          ; Calculate escape direction
          let avoid-dx [xcor] of myself - xcor
          let avoid-dy [ycor] of myself - ycor

          ; torus correction
          if abs(avoid-dx) > torus-world-width / 2 [
            ifelse avoid-dx > 0 [ set avoid-dx avoid-dx - torus-world-width ]
            [ set avoid-dx avoid-dx + torus-world-width ]
          ]
          if abs(avoid-dy) > torus-world-height / 2 [
            ifelse avoid-dy > 0 [ set avoid-dy avoid-dy - torus-world-height ]
            [ set avoid-dy avoid-dy + torus-world-height ]
          ]

          let avoid-dist sqrt(avoid-dx ^ 2 + avoid-dy ^ 2)
          if avoid-dist > 0 [
            set avoid-dx (avoid-dx / avoid-dist) * avoid-strength
            set avoid-dy (avoid-dy / avoid-dist) * avoid-strength

            ask myself [
              set move-x move-x + avoid-dx
              set move-y move-y + avoid-dy
            ]
          ]
        ]
      ]
    ]

    ; === 2. Separation: avoid overcrowding ===
    let nearby-sheep other sheep-outside in-radius 2.0
    if any? nearby-sheep [
      let sep-x 0
      let sep-y 0
      ask nearby-sheep [
        let sep-dist torus-distance xcor ycor ([xcor] of myself) ([ycor] of myself)
        if sep-dist > 0.1 [
          let sep-dx [xcor] of myself - xcor
          let sep-dy [ycor] of myself - ycor

          ; torus correction
          if abs(sep-dx) > torus-world-width / 2 [
            ifelse sep-dx > 0 [ set sep-dx sep-dx - torus-world-width ]
            [ set sep-dx sep-dx + torus-world-width ]
          ]
          if abs(sep-dy) > torus-world-height / 2 [
            ifelse sep-dy > 0 [ set sep-dy sep-dy - torus-world-height ]
            [ set sep-dy sep-dy + torus-world-height ]
          ]

          let separation-force separation-strength / sep-dist
          set sep-dx (sep-dx / sep-dist) * separation-force
          set sep-dy (sep-dy / sep-dist) * separation-force

          ask myself [
            set sep-x sep-x + sep-dx
            set sep-y sep-y + sep-dy
          ]
        ]
      ]
      set move-x move-x + sep-x
      set move-y move-y + sep-y
    ]

    ; === 3. Slight group cohesion (very weak) ===
    let cohesion-sheep other sheep-outside in-radius (sheep-cohesion-radius * 0.5)
    if any? cohesion-sheep and count cohesion-sheep > 3 [
      let center-x mean [xcor] of cohesion-sheep
      let center-y mean [ycor] of cohesion-sheep

      let cohesion-dx center-x - xcor
      let cohesion-dy center-y - ycor

      ; torus correction
      if abs(cohesion-dx) > torus-world-width / 2 [
        ifelse cohesion-dx > 0 [ set cohesion-dx cohesion-dx - torus-world-width ]
        [ set cohesion-dx cohesion-dx + torus-world-width ]
      ]
      if abs(cohesion-dy) > torus-world-height / 2 [
        ifelse cohesion-dy > 0 [ set cohesion-dy cohesion-dy - torus-world-height ]
        [ set cohesion-dy cohesion-dy + torus-world-height ]
      ]

      ; Very weak cohesion force
      set move-x move-x + cohesion-dx * cohesion-strength * 0.05
      set move-y move-y + cohesion-dy * cohesion-strength * 0.05
    ]

    ; === 4. Random walk (add unpredictability) ===
    if random-float 1 < 0.3 [
      set move-x move-x + (random-float 1.0 - 0.5)
      set move-y move-y + (random-float 1.0 - 0.5)
    ]

    ; === 5. Speed limitation ===
    let max-speed sheep-base-speed
    let current-speed sqrt(move-x ^ 2 + move-y ^ 2)
    if current-speed > max-speed [
      set move-x (move-x / current-speed) * max-speed
      set move-y (move-y / current-speed) * max-speed
    ]

    ; Apply movement
    set vx move-x
    set vy move-y

    ; Execute movement
    if abs(vx) > 0.01 or abs(vy) > 0.01 [
      setxy (xcor + vx) (ycor + vy)
      set heading atan vx vy
    ]
  ]

  ; Sheep inside pen remain stationary
  ask sheep with [torus-distance xcor ycor ([pxcor] of goal-location) ([pycor] of goal-location) <= pen-detection-radius] [
    set vx vx * 0.9
    set vy vy * 0.9
    if abs(vx) > 0.01 or abs(vy) > 0.01 [
      setxy (xcor + vx) (ycor + vy)
    ]
  ]
end

to intelligent-shepherding
  let sheep-outside sheep with [not in-pen?]
  if count sheep-outside = 0 [
    set mode "patrolling"
    set color gray
    patrol-around-pen
    ; Remove print debug statements
    stop
  ]

  ; Calculate sheep group status - Important: only calculate center of sheep outside pen
  let sheep-center-x mean [xcor] of sheep-outside
  let sheep-center-y mean [ycor] of sheep-outside
  let goal-x [pxcor] of goal-location
  let goal-y [pycor] of goal-location

  ; Calculate key distances (using torus distance)
  let group-to-goal-dist torus-distance sheep-center-x sheep-center-y goal-x goal-y
  let dog-to-group-dist torus-distance xcor ycor sheep-center-x sheep-center-y
  let group-spread max [torus-distance xcor ycor sheep-center-x sheep-center-y] of sheep-outside

  ; Detect scattered sheep (too far from group center) - Key fix: only check sheep outside pen!
  let scattered-sheep sheep-outside with [torus-distance xcor ycor sheep-center-x sheep-center-y > collection-threshold]
  let scattered-count count scattered-sheep
  let remaining-sheep-count count sheep-outside

  ; === Simplified debug info ===
  ; Remove all print statements

  ; === Redesigned behavior decision system ===

  ; 1. FINAL-PUSH - Final stage (highest priority)
  if remaining-sheep-count <= 2 [
    set mode "final-push"
    set color pink
    final-push-behavior sheep-outside
    ; Remove print debug statements
    stop
  ]

  ; 2. DRIVING - Priority push when far from pen (priority 2)
  if group-to-goal-dist > driving-distance [
    ; But if too many scattered sheep (>60%), gather first - greatly increase threshold from 40% to 60%
    ifelse scattered-count > (remaining-sheep-count * 0.4) [
      set mode "collecting"
      set color yellow
      collecting-behavior scattered-sheep sheep-center-x sheep-center-y
      ; Remove print debug statements
    ] [
      set mode "driving"
      set color red
      driving-behavior sheep-center-x sheep-center-y goal-x goal-y
      ; Remove print debug statements
    ]
    stop
  ]

  ; 3. COLLECTING - Gather when severely scattered (priority 3) - further lower threshold
  if scattered-count > (remaining-sheep-count * 0.5) and scattered-count > 15 [
    set mode "collecting"
    set color yellow
    collecting-behavior scattered-sheep sheep-center-x sheep-center-y
    ; Remove print debug statements
    stop
  ]

  ; 4. FIXING/EYE - Threaten when group too dispersed (priority 4)
  if group-spread > sheep-cohesion-radius * 3.0 [
    set mode "fixing"
    set color orange
    fixing-eye-behavior sheep-outside sheep-center-x sheep-center-y
    ; Remove print debug statements
    stop
  ]

  ; 5. FLANKING - Direction control at medium distance (priority 5)
  if group-to-goal-dist <= driving-distance and group-to-goal-dist > 8 [
    set mode "flanking"
    set color magenta
    flanking-behavior sheep-outside sheep-center-x sheep-center-y goal-x goal-y
    ; Remove print debug statements
    stop
  ]

  ; 6. BALANCING - Fine adjustment when approaching target (default mode)
  set mode "balancing"
  set color cyan
  balancing-behavior sheep-outside sheep-center-x sheep-center-y goal-x goal-y
  ; Remove print debug statements
end

; === 1. COLLECTING: Gather scattered individuals ===
to collecting-behavior [scattered-sheep group-x group-y]
  ; Redesigned: identify sheep clusters, guide at tail end of small groups, rather than breaking them up
  if count scattered-sheep > 0 [

    ; === Step 1: Identify sheep clusters ===
    let sheep-clusters identify-sheep-clusters scattered-sheep

    ; === Step 2: Handle clusters or individual sheep ===
    ifelse length sheep-clusters > 0 [
      ; === When clusters exist: guide by cluster ===
      let target-cluster-index (dog-id mod length sheep-clusters)
      let target-cluster item target-cluster-index sheep-clusters

      if length target-cluster > 0 [
        ; === Step 3: Calculate target cluster information ===
        let cluster-sheep turtle-set target-cluster
        let cluster-center-x mean [xcor] of cluster-sheep
        let cluster-center-y mean [ycor] of cluster-sheep
        let cluster-size count cluster-sheep

        ; === Step 4: Calculate direction from small group to main group ===
        let cluster-to-main-dx group-x - cluster-center-x
        let cluster-to-main-dy group-y - cluster-center-y

        ; torus correction
        if abs(cluster-to-main-dx) > torus-world-width / 2 [
          ifelse cluster-to-main-dx > 0 [ set cluster-to-main-dx cluster-to-main-dx - torus-world-width ]
          [ set cluster-to-main-dx cluster-to-main-dx + torus-world-width ]
        ]
        if abs(cluster-to-main-dy) > torus-world-height / 2 [
          ifelse cluster-to-main-dy > 0 [ set cluster-to-main-dy cluster-to-main-dy - torus-world-height ]
          [ set cluster-to-main-dy cluster-to-main-dy + torus-world-height ]
        ]

        ; Normalize direction - fix division by zero error
        let dir-dist sqrt(cluster-to-main-dx ^ 2 + cluster-to-main-dy ^ 2)
        ifelse dir-dist > 0.01 [  ; Add stricter check to avoid division by zero
          set cluster-to-main-dx cluster-to-main-dx / dir-dist
          set cluster-to-main-dy cluster-to-main-dy / dir-dist
        ] [
          ; If distance too small, use default direction
          set cluster-to-main-dx 1
          set cluster-to-main-dy 0
        ]

        ; === Step 5: Position at tail end of small group (side away from main group) ===
        let herding-distance 3.5 + (cluster-size * 0.3)  ; Adjust distance based on group size
        let pos-x cluster-center-x + (- cluster-to-main-dx) * herding-distance
        let pos-y cluster-center-y + (- cluster-to-main-dy) * herding-distance

        ; === Step 6: Slight swaying to increase herding pressure ===
        let cluster-zigzag-amplitude 0.8
        let cluster-zigzag-frequency 10 + dog-id * 2
        let zigzag-offset sin(ticks * cluster-zigzag-frequency) * cluster-zigzag-amplitude

        ; Sway perpendicular to "small group-main group" line
        let perpendicular-x (- cluster-to-main-dy) * zigzag-offset
        let perpendicular-y cluster-to-main-dx * zigzag-offset

        set pos-x pos-x + perpendicular-x
        set pos-y pos-y + perpendicular-y

        ; === Step 7: Avoid multi-dog overlap ===
        let angular-offset (dog-id * 30)  ; Angular offset
        let offset-rad (angular-offset * pi / 180)
        let offset-x (- cluster-to-main-dx) * cos(offset-rad) - (- cluster-to-main-dy) * sin(offset-rad)
        let offset-y (- cluster-to-main-dx) * sin(offset-rad) + (- cluster-to-main-dy) * cos(offset-rad)

        set pos-x pos-x + offset-x * 1.2
        set pos-y pos-y + offset-y * 1.2

        ; Move to position
        move-to-position pos-x pos-y (dog-base-speed * 1.2)

        ; Debug info
        if dog-id = 0 and ticks mod 60 = 0 [
        ]
      ]
    ] [
      ; === When no clusters: individual sheep herding strategy (prevent aimless) ===
      ; This is the key backup plan!
      let sorted-scattered sort-on [(torus-distance xcor ycor group-x group-y)] scattered-sheep
      let target-index (dog-id mod length sorted-scattered)
      let selected-sheep item target-index sorted-scattered

      let sheep-x [xcor] of selected-sheep
      let sheep-y [ycor] of selected-sheep

      ; Calculate direction from individual sheep to main group
      let sheep-to-main-dx group-x - sheep-x
      let sheep-to-main-dy group-y - sheep-y

      ; torus correction
      if abs(sheep-to-main-dx) > torus-world-width / 2 [
        ifelse sheep-to-main-dx > 0 [ set sheep-to-main-dx sheep-to-main-dx - torus-world-width ]
        [ set sheep-to-main-dx sheep-to-main-dx + torus-world-width ]
      ]
      if abs(sheep-to-main-dy) > torus-world-height / 2 [
        ifelse sheep-to-main-dy > 0 [ set sheep-to-main-dy sheep-to-main-dy - torus-world-height ]
        [ set sheep-to-main-dy sheep-to-main-dy + torus-world-height ]
      ]

      ; Normalize direction - fix division by zero error
      let single-dir-dist sqrt(sheep-to-main-dx ^ 2 + sheep-to-main-dy ^ 2)
      ifelse single-dir-dist > 0.01 [  ; Add stricter check to avoid division by zero
        set sheep-to-main-dx sheep-to-main-dx / single-dir-dist
        set sheep-to-main-dy sheep-to-main-dy / single-dir-dist
      ] [
        ; If distance too small, use default direction
        set sheep-to-main-dx 1
        set sheep-to-main-dy 0
      ]

      ; Position sheepdog at outer rear of individual sheep
      let single-herding-distance 3.2
      let single-pos-x sheep-x + (- sheep-to-main-dx) * single-herding-distance
      let single-pos-y sheep-y + (- sheep-to-main-dy) * single-herding-distance

      ; Active Z-pattern movement
      let single-zigzag sin(ticks * (12 + dog-id * 3)) * 1.0
      set single-pos-x single-pos-x + (- sheep-to-main-dy) * single-zigzag
      set single-pos-y single-pos-y + sheep-to-main-dx * single-zigzag

      ; Multi-dog dispersion, avoid overlap
      let single-angular-offset (dog-id * 45)
      let single-offset-rad (single-angular-offset * pi / 180)
      let single-offset-x (- sheep-to-main-dx) * cos(single-offset-rad) - (- sheep-to-main-dy) * sin(single-offset-rad)
      let single-offset-y (- sheep-to-main-dx) * sin(single-offset-rad) + (- sheep-to-main-dy) * cos(single-offset-rad)

      set single-pos-x single-pos-x + single-offset-x * 1.0
      set single-pos-y single-pos-y + single-offset-y * 1.0

      ; Active movement
      move-to-position single-pos-x single-pos-y (dog-base-speed * 1.5)

      ; Debug info
      if dog-id = 0 and ticks mod 60 = 0 [
      ]
    ]
  ]
end

to-report identify-sheep-clusters [sheep-list]
  ; Use simple distance clustering to identify sheep group clusters
  let clusters []
  let unprocessed-sheep []

  ; Convert sheep-list to list
  ask sheep-list [
    set unprocessed-sheep lput self unprocessed-sheep
  ]

  let cluster-radius 4.0  ; Clustering radius: sheep within 4 units considered same group

  ; Clustering algorithm
  while [length unprocessed-sheep > 0] [
    let seed-sheep first unprocessed-sheep
    set unprocessed-sheep remove seed-sheep unprocessed-sheep

    let current-cluster (list seed-sheep)
    let need-expansion true

    ; Expand cluster: find all adjacent sheep
    while [need-expansion] [
      set need-expansion false
      let new-neighbors []

      ; For each sheep in current cluster, find its neighbors
      foreach current-cluster [ cluster-sheep ->
        let sheep-x [xcor] of cluster-sheep
        let sheep-y [ycor] of cluster-sheep

        foreach unprocessed-sheep [ potential-neighbor ->
          let neighbor-x [xcor] of potential-neighbor
          let neighbor-y [ycor] of potential-neighbor
          let sheep-distance torus-distance sheep-x sheep-y neighbor-x neighbor-y

          if sheep-distance <= cluster-radius [
            if not member? potential-neighbor new-neighbors [
              set new-neighbors lput potential-neighbor new-neighbors
            ]
          ]
        ]
      ]

      ; Add new neighbors to current cluster
      if length new-neighbors > 0 [
        set need-expansion true
        foreach new-neighbors [ neighbor ->
          set current-cluster lput neighbor current-cluster
          set unprocessed-sheep remove neighbor unprocessed-sheep
        ]
      ]
    ]

    ; Only consider clusters with size >= 2 as valid clusters
    if length current-cluster >= 2 [
      set clusters lput current-cluster clusters
    ]
  ]

  report clusters
end

; === 2. FIXING/EYE: Threatening gathering ===
to fixing-eye-behavior [sheep-group group-x group-y]
  ; Classic "eye contact" behavior of border collies
  ; Maintain threatening presence in front of sheep group, induce gathering

  ; Calculate group's movement direction
  let group-vx mean [vx] of sheep-group
  let group-vy mean [vy] of sheep-group
  let group-speed sqrt(group-vx ^ 2 + group-vy ^ 2)

  ; Position in front of group's movement direction - greatly reduce distance
  let ahead-distance 2.5 + (dog-id mod 3) * 0.4  ; Reduced from 8+2 to 2.5+0.4
  let pos-x group-x
  let pos-y group-y

  ifelse group-speed > 0.1 [
    ; Position based on group movement direction
    set pos-x group-x + (group-vx / group-speed) * ahead-distance
    set pos-y group-y + (group-vy / group-speed) * ahead-distance
  ] [
    ; When group is stationary, position at group edge
    ; Use assigned-sector to ensure dispersion
    let edge-angle assigned-sector + (dog-id * 45)  ; Reduced from 60 to 45 degrees
    set pos-x group-x + ahead-distance * cos(edge-angle)
    set pos-y group-y + ahead-distance * sin(edge-angle)
  ]

  ; Add additional position offset to ensure no overlap - reduce offset
  let extra-offset-angle dog-id * 60  ; Reduced from 90 to 60 degrees
  let extra-offset-dist 1.0  ; Reduced from 3 to 1.0
  set pos-x pos-x + extra-offset-dist * cos(extra-offset-angle)
  set pos-y pos-y + extra-offset-dist * sin(extra-offset-angle)

  move-to-position pos-x pos-y (dog-base-speed * 0.6)  ; Slow threatening speed
end

; === 3. DRIVING: Push entire group forward ===
to driving-behavior [group-x group-y goal-x goal-y]
  ; Z-pattern sweeping push strategy: perform Z-pattern movement behind sheep group, ensure group integrity
  ; Core concept: sweeping push + wait for response, prevent edge sheep from being left behind

  let sheep-outside sheep with [not in-pen?]
  if count sheep-outside = 0 [
    stop  ; No sheep outside pen
  ]

  ; === Step 1: Check if waiting for sheep group response ===
  if waiting-for-response [
    ; In waiting state, check if can continue moving
    let wait-time ticks - response-check-start
    let max-wait-time 25  ; Shorten wait time for smoother sweeping

    ; Detect if sheep group is moving toward pen
    let current-group-center-x mean [xcor] of sheep-outside
    let current-group-center-y mean [ycor] of sheep-outside

    ; Calculate sheep group movement vector
    let group-movement-dx current-group-center-x - target-group-center-x
    let group-movement-dy current-group-center-y - target-group-center-y

    ; torus correction for movement vector
    if abs(group-movement-dx) > torus-world-width / 2 [
      ifelse group-movement-dx > 0 [ set group-movement-dx group-movement-dx - torus-world-width ]
      [ set group-movement-dx group-movement-dx + torus-world-width ]
    ]
    if abs(group-movement-dy) > torus-world-height / 2 [
      ifelse group-movement-dy > 0 [ set group-movement-dy group-movement-dy - torus-world-height ]
      [ set group-movement-dy group-movement-dy + torus-world-height ]
    ]

    ; Calculate ideal direction from sheep group to pen
    let ideal-dx goal-x - target-group-center-x
    let ideal-dy goal-y - target-group-center-y

    ; torus correction for ideal direction
    if abs(ideal-dx) > torus-world-width / 2 [
      ifelse ideal-dx > 0 [ set ideal-dx ideal-dx - torus-world-width ]
      [ set ideal-dx ideal-dx + torus-world-width ]
    ]
    if abs(ideal-dy) > torus-world-height / 2 [
      ifelse ideal-dy > 0 [ set ideal-dy ideal-dy - torus-world-height ]
      [ set ideal-dy ideal-dy + torus-world-height ]
    ]

    ; Calculate consistency between actual sheep movement and ideal direction
    let movement-magnitude sqrt(group-movement-dx ^ 2 + group-movement-dy ^ 2)
    let ideal-magnitude sqrt(ideal-dx ^ 2 + ideal-dy ^ 2)
    let response-detected false

    if movement-magnitude > 0.2 and ideal-magnitude > 0.01 [  ; Lower detection threshold
      ; Calculate directional consistency (dot product)
      let dot-product (group-movement-dx * ideal-dx + group-movement-dy * ideal-dy) / (movement-magnitude * ideal-magnitude)

      ; If sheep group moving in correct direction (consistency > 0.25), consider response detected
      if dot-product > 0.25 [
        set response-detected true
      ]
    ]

    ; Decide whether to continue waiting
    let should-continue-waiting false
    if wait-time < max-wait-time and not response-detected [
      set should-continue-waiting true
    ]

    ; Debug info
    if dog-id = 0 and ticks mod 15 = 0 [
    ]

    ; If need to continue waiting, stay in current position
    ifelse should-continue-waiting [
      stop  ; Continue waiting, don't move
    ] [
      ; Waiting ended, can proceed to next sweep
      set waiting-for-response false
      set last-move-time ticks

      ; Remove conditional print statements
    ]
  ]

  ; === Step 2: Calculate Z-pattern sweep path ===

  ; Identify target group (prioritize nearest group)
  let sheep-clusters identify-sheep-clusters sheep-outside

  if length sheep-clusters = 0 [
    let all-sheep []
    ask sheep-outside [
      set all-sheep lput self all-sheep
    ]
    set sheep-clusters (list all-sheep)
  ]

  ; Select target group (simplified to nearest group)
  let target-group-x group-x
  let target-group-y group-y
  let target-group-size count sheep-outside

  if length sheep-clusters > 0 [
    let cluster-distances []
    foreach sheep-clusters [ cluster ->
      if length cluster > 0 [
        let cluster-sheep turtle-set cluster
        let cluster-center-x mean [xcor] of cluster-sheep
        let cluster-center-y mean [ycor] of cluster-sheep
        let dist-to-goal torus-distance cluster-center-x cluster-center-y goal-x goal-y

        let cluster-info (list dist-to-goal cluster-center-x cluster-center-y (count cluster-sheep))
        set cluster-distances lput cluster-info cluster-distances
      ]
    ]

    if length cluster-distances > 0 [
      set cluster-distances sort-by [ [a b] -> item 0 a < item 0 b ] cluster-distances
      let target-cluster-info first cluster-distances
      set target-group-x item 1 target-cluster-info
      set target-group-y item 2 target-cluster-info
      set target-group-size item 3 target-cluster-info
    ]
  ]

  ; === Step 3: Calculate sweep parameters ===

  ; Calculate direction from group to pen
  let group-to-goal-dx goal-x - target-group-x
  let group-to-goal-dy goal-y - target-group-y

  ; torus correction
  if abs(group-to-goal-dx) > torus-world-width / 2 [
    ifelse group-to-goal-dx > 0 [ set group-to-goal-dx group-to-goal-dx - torus-world-width ]
    [ set group-to-goal-dx group-to-goal-dx + torus-world-width ]
  ]
  if abs(group-to-goal-dy) > torus-world-height / 2 [
    ifelse group-to-goal-dy > 0 [ set group-to-goal-dy group-to-goal-dy - torus-world-height ]
    [ set group-to-goal-dy group-to-goal-dy + torus-world-height ]
  ]

  ; Normalize direction vector
  let direction-magnitude sqrt(group-to-goal-dx ^ 2 + group-to-goal-dy ^ 2)
  ifelse direction-magnitude > 0.01 [
    set group-to-goal-dx group-to-goal-dx / direction-magnitude
    set group-to-goal-dy group-to-goal-dy / direction-magnitude
  ] [
    set group-to-goal-dx 1
    set group-to-goal-dy 0
  ]

  ; Calculate sweep center line (behind group)
  let behind-group-dx (- group-to-goal-dx)
  let behind-group-dy (- group-to-goal-dy)

  let push-distance 4.5  ; Sweep distance
  set current-sweep-center-x target-group-x + behind-group-dx * push-distance
  set current-sweep-center-y target-group-y + behind-group-dy * push-distance

  ; Calculate sweep width (based on group size)
  let base-sweep-width 6.0
  let size-factor min (list (target-group-size * 0.08) 4.0)
  set sweep-width base-sweep-width + size-factor

  ; Calculate sweep vector perpendicular to push direction
  let sweep-perp-dx (- behind-group-dy)  ; Perpendicular vector
  let sweep-perp-dy behind-group-dx

  ; === Step 4: Z-pattern sweep logic ===

  ; Z-pattern sweep mode: center(0) → left(-1) → center(0) → right(1) → center(0) → left(-1) ...
  ; sweep-step: 0=center, 1=left, 2=center, 3=right, 4=center, 5=left...

  let sweep-positions (list 0 -1 0 1 0)  ; Z-pattern sweep sequence
  let current-sweep-offset 0

  ifelse sweep-step < length sweep-positions [
    set current-sweep-offset item sweep-step sweep-positions
  ] [
    ; 循环扫荡：重新开始
    set sweep-step 0
    set current-sweep-offset 0
  ]

  ; 计算当前扫荡位置
  let sweep-offset-x sweep-perp-dx * current-sweep-offset * (sweep-width / 2)
  let sweep-offset-y sweep-perp-dy * current-sweep-offset * (sweep-width / 2)

  ; 为每只犬添加不同偏移，避免重叠
  let dog-spacing 2.0
  let dog-offset-angle (dog-id * 15)  ; 每只犬不同角度
  let dog-offset-x dog-spacing * cos(dog-offset-angle)
  let dog-offset-y dog-spacing * sin(dog-offset-angle)

  let new-target-pos-x current-sweep-center-x + sweep-offset-x + dog-offset-x
  let new-target-pos-y current-sweep-center-y + sweep-offset-y + dog-offset-y

  ; 安全检查：避免进入羊圈
  let pos-to-goal-dist torus-distance new-target-pos-x new-target-pos-y goal-x goal-y
  if pos-to-goal-dist <= goal-radius + 2 [
    let safe-angle atan (new-target-pos-x - goal-x) (new-target-pos-y - goal-y)
    set new-target-pos-x goal-x + (goal-radius + 4) * cos(safe-angle)
    set new-target-pos-y goal-y + (goal-radius + 4) * sin(safe-angle)
  ]

  ; === 步骤5：移动逻辑 ===
  let current-distance-to-target torus-distance xcor ycor new-target-pos-x new-target-pos-y
  let minimum-move-threshold 2.0  ; 降低移动阈值，让扫荡更细致

  ; 控制移动频率
  let time-since-last-move ticks - last-move-time
  let minimum-move-interval 15  ; 缩短移动间隔，让扫荡更流畅

  if current-distance-to-target > minimum-move-threshold and time-since-last-move >= minimum-move-interval [
    ; 开始移动到新的扫荡位置
    move-to-position new-target-pos-x new-target-pos-y (dog-base-speed * 1.0)  ; 适中的移动速度

    ; 到达目标位置后，进入等待状态
    if current-distance-to-target <= minimum-move-threshold + 0.3 [
      set waiting-for-response true
      set target-group-center-x target-group-x
      set target-group-center-y target-group-y
      set response-check-start ticks

      ; 进入下一个扫荡步骤
      set sweep-step sweep-step + 1

      if dog-id = 0 [
        let step-name "中心"
        if current-sweep-offset = -1 [ set step-name "左侧" ]
        if current-sweep-offset = 1 [ set step-name "右侧" ]
      ]
    ]

    set last-move-time ticks
  ]

  ; 更新breed变量
  set target-x new-target-pos-x
  set target-y new-target-pos-y

  ; 调试信息
  if dog-id = 0 and ticks mod 40 = 0 and not waiting-for-response [
    let step-desc "中心"
    if current-sweep-offset = -1 [ set step-desc "左侧" ]
    if current-sweep-offset = 1 [ set step-desc "右侧" ]
  ]
end

; === 4. FLANKING: Direction control ===
to flanking-behavior [sheep-group group-x group-y goal-x goal-y]
  ; Flanking maneuver, fine-tune sheep group movement direction toward target
  ; Key: position at peripheral flanking position outside sheep group, not inserting into group interior

  ; Calculate ideal direction (group to target)
  let ideal-dx goal-x - group-x
  let ideal-dy goal-y - group-y

  ; torus correction
  if abs(ideal-dx) > torus-world-width / 2 [
    ifelse ideal-dx > 0 [ set ideal-dx ideal-dx - torus-world-width ]
    [ set ideal-dx ideal-dx + torus-world-width ]
  ]
  if abs(ideal-dy) > torus-world-height / 2 [
    ifelse ideal-dy > 0 [ set ideal-dy ideal-dy - torus-world-height ]
    [ set ideal-dy ideal-dy + torus-world-height ]
  ]

  ; Calculate current group movement direction
  let current-vx mean [vx] of sheep-group
  let current-vy mean [vy] of sheep-group

  ; Calculate directional deviation (cross product determines left/right deviation)
  let cross-product (current-vx * ideal-dy - current-vy * ideal-dx)

  ; Choose flanking position based on deviation and dog-id
  let base-flank-angle 90  ; Base flanking angle
  if cross-product < 0 [ set base-flank-angle -90 ]  ; Adjust direction

  ; Each dog has different flanking angle - ensure at periphery
  let flank-angle base-flank-angle + (dog-id * 30)  ; Larger angle dispersion
  let flank-distance 4.5 + (dog-id mod 2) * 1.0  ; Increase distance to ensure at periphery
  let flank-rad (flank-angle * pi / 180)
  let pos-x group-x + flank-distance * cos(flank-rad)
  let pos-y group-y + flank-distance * sin(flank-rad)

  ; Z-pattern fine adjustment movement (characteristic behavior found in research) - but gentler
  let flank-zigzag-amplitude 0.6  ; Reduce amplitude to avoid excessive interference
  let flank-zigzag-frequency 12 + dog-id * 3  ; Higher frequency fine adjustment
  if ticks mod (25 + dog-id * 3) < (12 + dog-id) [
    let zigzag-offset sin(ticks * flank-zigzag-frequency) * flank-zigzag-amplitude
    set pos-x pos-x + zigzag-offset
    set pos-y pos-y + zigzag-offset * 0.5  ; Fine adjustment in different direction
  ]

  move-to-position pos-x pos-y (dog-base-speed * 0.9)

  ; Debug info
  if dog-id = 0 and ticks mod 80 = 0 [
  ]
end

; === 5. BALANCING: Dynamic position and angle adjustment ===
to balancing-behavior [sheep-group group-x group-y goal-x goal-y]
  ; Fine position adjustment, maintain position in opposite direction of "target-sheep group" line
  ; Used for final guidance stage

  ; Calculate "target-sheep group" line direction
  let goal-to-group-dx goal-x - group-x
  let goal-to-group-dy goal-y - group-y

  ; torus correction
  if abs(goal-to-group-dx) > torus-world-width / 2 [
    ifelse goal-to-group-dx > 0 [ set goal-to-group-dx goal-to-group-dx - torus-world-width ]
    [ set goal-to-group-dx goal-to-group-dx + torus-world-width ]
  ]
  if abs(goal-to-group-dy) > torus-world-height / 2 [
    ifelse goal-to-group-dy > 0 [ set goal-to-group-dy goal-to-group-dy - torus-world-height ]
    [ set goal-to-group-dy goal-to-group-dy + torus-world-height ]
  ]

  let dir-dist sqrt(goal-to-group-dx ^ 2 + goal-to-group-dy ^ 2)
  if dir-dist > 0.01 [  ; Fix division by zero error: add stricter check
    set goal-to-group-dx goal-to-group-dx / dir-dist
    set goal-to-group-dy goal-to-group-dy / dir-dist
  ]

  ; Balance position: on line extension, dynamically adjust distance
  ; Greatly reduce distance to ensure within perception radius
  let balance-distance 1.5 + (dog-id mod 3) * 0.3 + 0.5 * sin(ticks * (5 + dog-id))  ; Reduced from 5+1.5 to 1.5+0.3
  let pos-x group-x - goal-to-group-dx * balance-distance
  let pos-y group-y - goal-to-group-dy * balance-distance

  ; Reduce angular offset to avoid excessive dispersion
  let angle-offset (dog-id * 15 - 7.5)  ; Reduced from 25 to 15 degrees
  let offset-rad (angle-offset * pi / 180)
  let offset-x goal-to-group-dx * cos(offset-rad) - goal-to-group-dy * sin(offset-rad)
  let offset-y goal-to-group-dx * sin(offset-rad) + goal-to-group-dy * cos(offset-rad)

  set pos-x pos-x + offset-x * (1 + dog-id * 0.2)  ; Reduced from 3+dog-id to 1+0.2*dog-id
  set pos-y pos-y + offset-y * (1 + dog-id * 0.2)

  move-to-position pos-x pos-y (dog-base-speed * 0.7)  ; Gentle adjustment
end

; === 6. FINAL-PUSH: Individual hunting strategy for last few sheep ===
to final-push-behavior [remaining-sheep]
  ; Redesigned: real hunting strategy, targeting individual sheep for flanking

  let goal-x [pxcor] of goal-location
  let goal-y [pycor] of goal-location
  let sheep-count count remaining-sheep

  ; === Anti-deadlock mechanism: if very few sheep remain and it's been a long time, use super aggressive push ===
  if sheep-count <= 3 and ticks > 5000 [
    if any? remaining-sheep [
      let desperate-target one-of remaining-sheep
      let sheep-pos-x [xcor] of desperate-target
      let sheep-pos-y [ycor] of desperate-target

      ; All dogs rush directly behind this sheep to push it
      let direct-push-x sheep-pos-x + (goal-x - sheep-pos-x) * -0.5
      let direct-push-y sheep-pos-y + (goal-y - sheep-pos-y) * -0.5

      ; Slight individualized offset to avoid overlap
      set direct-push-x direct-push-x + (dog-id * 1.5 - 0.75)
      set direct-push-y direct-push-y + (dog-id * 1.0 - 0.5)

      move-to-position direct-push-x direct-push-y (dog-base-speed * 3.5)
      stop
    ]
  ]

  ; === Core hunting strategy: assign tasks based on sheep-dog ratio ===
  if sheep-count > 0 [
    ; Sort remaining sheep by distance to pen (farthest first)
    let sheep-list []
    ask remaining-sheep [
      let dist-to-goal torus-distance xcor ycor goal-x goal-y
      set sheep-list lput (list self dist-to-goal) sheep-list
    ]
    set sheep-list sort-by [ [a b] -> item 1 a > item 1 b ] sheep-list  ; Sort by distance descending

    ; Choose strategy based on dog-sheep ratio
    let dogs-per-sheep (num-dogs / sheep-count)

    ifelse dogs-per-sheep >= 2 [
      ; === Strategy A: Multi-dog surround single sheep ===
      multi-dog-surround-strategy sheep-list
    ] [
      ifelse dogs-per-sheep >= 1 [
        ; === Strategy B: One-to-one assignment ===
        one-to-one-assignment-strategy sheep-list
      ] [
        ; === Strategy C: Priority hunting ===
        priority-hunting-strategy sheep-list
      ]
    ]
  ]
end

; === Strategy A: Multi-dog surround single sheep ===
to multi-dog-surround-strategy [sheep-list]
  ; Multiple dogs hunt the farthest sheep, form semicircle flanking
  let target-sheep-info first sheep-list
  let target-sheep-agent item 0 target-sheep-info
  let sheep-x [xcor] of target-sheep-agent
  let sheep-y [ycor] of target-sheep-agent
  let goal-x [pxcor] of goal-location
  let goal-y [pycor] of goal-location

  ; Calculate direction vector from sheep to pen
  let sheep-to-goal-dx goal-x - sheep-x
  let sheep-to-goal-dy goal-y - sheep-y

  ; torus correction
  if abs(sheep-to-goal-dx) > torus-world-width / 2 [
    ifelse sheep-to-goal-dx > 0 [ set sheep-to-goal-dx sheep-to-goal-dx - torus-world-width ]
    [ set sheep-to-goal-dx sheep-to-goal-dx + torus-world-width ]
  ]
  if abs(sheep-to-goal-dy) > torus-world-height / 2 [
    ifelse sheep-to-goal-dy > 0 [ set sheep-to-goal-dy sheep-to-goal-dy - torus-world-height ]
    [ set sheep-to-goal-dy sheep-to-goal-dy + torus-world-height ]
  ]

  ; Normalize direction vector
  let direction-magnitude sqrt(sheep-to-goal-dx ^ 2 + sheep-to-goal-dy ^ 2)
  if direction-magnitude > 0.01 [
    set sheep-to-goal-dx sheep-to-goal-dx / direction-magnitude
    set sheep-to-goal-dy sheep-to-goal-dy / direction-magnitude
  ]

  ; Form semicircle flanking formation: distribute within 180 degrees behind sheep
  let surround-radius 3.0
  let angle-range 180  ; Semicircle flanking
  let base-angle atan (- sheep-to-goal-dx) (- sheep-to-goal-dy)  ; Face opposite direction to pen

  ; Calculate angle position for each dog
  let angle-step 0
  if num-dogs > 1 [
    set angle-step angle-range / (num-dogs - 1)
  ]

  let my-angle base-angle - (angle-range / 2) + (dog-id * angle-step)
  let pos-x sheep-x + surround-radius * cos(my-angle)
  let pos-y sheep-y + surround-radius * sin(my-angle)

  ; Add slight advancing pressure
  let pressure-factor 0.1 * sin(ticks * 8)
  set pos-x pos-x - pressure-factor * cos(my-angle)
  set pos-y pos-y - pressure-factor * sin(my-angle)

  move-to-position pos-x pos-y (dog-base-speed * 2.0)
end

; === Strategy B: One-to-one assignment ===
to one-to-one-assignment-strategy [sheep-list]
  ; Each dog responsible for one sheep, extra dogs assist with farthest sheep
  let my-target-index (dog-id mod length sheep-list)
  let target-sheep-info item my-target-index sheep-list
  let target-sheep-agent item 0 target-sheep-info

  ; Directly push behind target sheep
  individual-sheep-push target-sheep-agent
end

; === Strategy C: Priority hunting ===
to priority-hunting-strategy [sheep-list]
  ; When insufficient dogs, prioritize hunting farthest few sheep
  let priority-count min (list num-dogs length sheep-list)
  let my-target-index (dog-id mod priority-count)

  if my-target-index < length sheep-list [
    let target-sheep-info item my-target-index sheep-list
    let target-sheep-agent item 0 target-sheep-info
    individual-sheep-push target-sheep-agent
  ]
end

; === Individual sheep push function ===
to individual-sheep-push [sheep-agent]
  let sheep-x [xcor] of sheep-agent
  let sheep-y [ycor] of sheep-agent
  let goal-x [pxcor] of goal-location
  let goal-y [pycor] of goal-location

  ; Calculate push direction (opposite to sheep-to-pen direction)
  let push-dx goal-x - sheep-x
  let push-dy goal-y - sheep-y

  ; torus correction
  if abs(push-dx) > torus-world-width / 2 [
    ifelse push-dx > 0 [ set push-dx push-dx - torus-world-width ]
    [ set push-dx push-dx + torus-world-width ]
  ]
  if abs(push-dy) > torus-world-height / 2 [
    ifelse push-dy > 0 [ set push-dy push-dy - torus-world-height ]
    [ set push-dy push-dy + torus-world-height ]
  ]

  ; Normalize
  let push-magnitude sqrt(push-dx ^ 2 + push-dy ^ 2)
  if push-magnitude > 0.01 [
    set push-dx push-dx / push-magnitude
    set push-dy push-dy / push-magnitude
  ]

  ; Position behind sheep (opposite direction to pen)
  let push-distance 2.0
  let pos-x sheep-x - push-dx * push-distance
  let pos-y sheep-y - push-dy * push-distance

  ; Add individualized offset to avoid overlap
  let side-offset (dog-id - (num-dogs / 2)) * 0.8
  set pos-x pos-x + push-dy * side-offset  ; Offset perpendicular to push direction
  set pos-y pos-y - push-dx * side-offset

  ; Add micro-movement to increase pressure
  let micro-movement sin(ticks * 12 + dog-id * 30) * 0.3
  set pos-x pos-x + micro-movement
  set pos-y pos-y + micro-movement * 0.5

  move-to-position pos-x pos-y (dog-base-speed * 2.5)
end

; === Universal movement function ===
to move-to-position [pos-x pos-y move-speed]
  ; Torus-aware smooth movement - fix division by zero error
  let move-dx pos-x - xcor
  let move-dy pos-y - ycor

  ; Torus correction for movement vector
  if abs(move-dx) > torus-world-width / 2 [
    ifelse move-dx > 0 [ set move-dx move-dx - torus-world-width ]
    [ set move-dx move-dx + torus-world-width ]
  ]
  if abs(move-dy) > torus-world-height / 2 [
    ifelse move-dy > 0 [ set move-dy move-dy - torus-world-height ]
    [ set move-dy move-dy + torus-world-height ]
  ]

  let move-dist sqrt(move-dx ^ 2 + move-dy ^ 2)
  ; Fix division by zero error: add stricter distance check
  if move-dist > 0.01 [  ; Changed from 0.1 to 0.01 for stricter check
    ; Normalize and apply speed
    set move-dx (move-dx / move-dist) * move-speed
    set move-dy (move-dy / move-dist) * move-speed
    setxy (xcor + move-dx) (ycor + move-dy)
    set heading atan move-dx move-dy
  ]
  ; If distance too small (< 0.01), don't move to avoid division by zero error
end

; === Patrol function ===
to patrol-around-pen
  ; Patrol around pen, each dog on different orbit
  let base-patrol-radius (goal-radius + 5)
  let patrol-radius base-patrol-radius + (dog-id * 3)  ; Different patrol radius for each dog
  let patrol-speed (dog-base-speed * 0.5)

  ; Each dog has different patrol speed to avoid clustering - fix division by zero error
  let patrol-speed-multiplier (1 + dog-id * 0.1)  ; Different speed multipliers

  ; Fix division by zero error: ensure num-dogs > 0
  let angle-increment 0
  if num-dogs > 0 [
    set angle-increment (360 / num-dogs / 20) * patrol-speed-multiplier  ; Different rotation speeds
  ]

  set patrol-angle patrol-angle + angle-increment
  if patrol-angle >= 360 [ set patrol-angle patrol-angle - 360 ]

  let goal-x [pxcor] of goal-location
  let goal-y [pycor] of goal-location
  let patrol-x goal-x + patrol-radius * cos(patrol-angle)
  let patrol-y goal-y + patrol-radius * sin(patrol-angle)

  move-to-position patrol-x patrol-y patrol-speed
end

; === Research Analysis Functions ===

to calculate-metrics
  ; Calculate group behavior metrics for research paper
  ; Fix division by zero error: add strict count check
  if count sheep = 0 [
    set current-polarization 0
    set current-elongation 0
    set current-cohesion 0
    set barycenter-speed 0
    stop
  ]

  ; Basic metrics calculation - herd-center already calculated in move-sheep
  ; No need to repeat: set herd-center-x mean [xcor] of sheep
  ; No need to repeat: set herd-center-y mean [ycor] of sheep

  ; === 1. Polarization: measure directional alignment ===
  let total-vx sum [vx] of sheep
  let total-vy sum [vy] of sheep
  let avg-vel-mag sqrt(total-vx ^ 2 + total-vy ^ 2) / count sheep
  let individual-speeds sum [sqrt(vx ^ 2 + vy ^ 2)] of sheep / count sheep

  ; Fix division by zero error: check individual-speeds
  ifelse individual-speeds > 0.001 [  ; Add stricter check
    set current-polarization avg-vel-mag / individual-speeds
  ] [
    set current-polarization 0
  ]

  ; === 2. Cohesion: measure group compactness ===
  let avg-dist mean [torus-distance xcor ycor herd-center-x herd-center-y] of sheep
  ifelse avg-dist > 0.001 [  ; Add stricter check
    set current-cohesion 1 / avg-dist
  ] [
    set current-cohesion 1
  ]

  ; === 3. Barycenter speed: group movement velocity ===
  set barycenter-speed sqrt(total-vx ^ 2 + total-vy ^ 2) / count sheep

  ; === 4. Elongation: shape deformation analysis ===
  let sheep-positions []
  ask sheep [
    set sheep-positions lput (list xcor ycor) sheep-positions
  ]

  ; Simple elongation calculation: coefficient of variation of distances from center
  let distances-from-center []
  foreach sheep-positions [ pos ->
    let x item 0 pos
    let y item 1 pos
    let dist torus-distance x y herd-center-x herd-center-y
    set distances-from-center lput dist distances-from-center
  ]

  ; Calculate elongation as coefficient of variation - fix division by zero error
  ifelse length distances-from-center > 1 [
    let mean-dist mean distances-from-center
    let variance-dist 0
    foreach distances-from-center [ d ->
      set variance-dist variance-dist + (d - mean-dist) ^ 2
    ]
    set variance-dist variance-dist / (length distances-from-center - 1)
    let std-dev-dist sqrt variance-dist

    ; Fix division by zero error: check mean-dist
    ifelse mean-dist > 0.001 [  ; Add stricter check
      set current-elongation std-dev-dist / mean-dist
    ] [
      set current-elongation 0
    ]
  ] [
    set current-elongation 0
  ]
end

to record-data
  ; Record time series data for research analysis
  set polarization-history lput current-polarization polarization-history
  set elongation-history lput current-elongation elongation-history
  set cohesion-history lput current-cohesion cohesion-history
  set speed-history lput barycenter-speed speed-history

  ; Keep only recent 1000 data points to prevent memory issues
  if length polarization-history > 1000 [
    set polarization-history but-first polarization-history
    set elongation-history but-first elongation-history
    set cohesion-history but-first cohesion-history
    set speed-history but-first speed-history
  ]
end

to update-pdfs
  ; Generate probability density functions for paper figures
  if length speed-history < 50 [ stop ]

  ; === Speed PDF ===
  let min-speed 0
  let max-speed 1
  let speed-bin-width (max-speed - min-speed) / pdf-bin-count

  set-current-plot "Speed PDF"
  clear-plot

  let speed-bins n-values pdf-bin-count [0]
  foreach speed-history [ speed-value ->
    let bin-index floor((speed-value - min-speed) / speed-bin-width)
    if bin-index >= 0 and bin-index < pdf-bin-count [
      set speed-bins replace-item bin-index speed-bins (item bin-index speed-bins + 1)
    ]
  ]

  let total-speed-samples length speed-history
  let speed-x min-speed
  foreach speed-bins [ bin-count ->
    let pdf-value (bin-count / total-speed-samples) / speed-bin-width
    plotxy speed-x pdf-value
    set speed-x speed-x + speed-bin-width
  ]

  ; === Polarization PDF ===
  let min-polarization 0
  let max-polarization 2
  let pol-bin-width (max-polarization - min-polarization) / pdf-bin-count

  set-current-plot "Polarization PDF"
  clear-plot

  let pol-bins n-values pdf-bin-count [0]
  foreach polarization-history [ pol-value ->
    let bin-index floor((pol-value - min-polarization) / pol-bin-width)
    if bin-index >= 0 and bin-index < pdf-bin-count [
      set pol-bins replace-item bin-index pol-bins (item bin-index pol-bins + 1)
    ]
  ]

  let total-pol-samples length polarization-history
  let pol-x min-polarization
  foreach pol-bins [ bin-count ->
    let pdf-value (bin-count / total-pol-samples) / pol-bin-width
    plotxy pol-x pdf-value
    set pol-x pol-x + pol-bin-width
  ]

  ; === Elongation PDF ===
  let min-elongation 0
  let max-elongation 2
  let elong-bin-width (max-elongation - min-elongation) / pdf-bin-count

  set-current-plot "Elongation PDF"
  clear-plot

  let elong-bins n-values pdf-bin-count [0]
  foreach elongation-history [ elong-value ->
    let bin-index floor((elong-value - min-elongation) / elong-bin-width)
    if bin-index >= 0 and bin-index < pdf-bin-count [
      set elong-bins replace-item bin-index elong-bins (item bin-index elong-bins + 1)
    ]
  ]

  let total-elong-samples length elongation-history
  let elong-x min-elongation
  foreach elong-bins [ bin-count ->
    let pdf-value (bin-count / total-elong-samples) / elong-bin-width
    plotxy elong-x pdf-value
    set elong-x elong-x + elong-bin-width
  ]

  ; === Cohesion PDF ===
  let min-cohesion 0
  let max-cohesion 0.5
  let coh-bin-width (max-cohesion - min-cohesion) / pdf-bin-count

  set-current-plot "Cohesion PDF"
  clear-plot

  let coh-bins n-values pdf-bin-count [0]
  foreach cohesion-history [ coh-value ->
    let bin-index floor((coh-value - min-cohesion) / coh-bin-width)
    if bin-index >= 0 and bin-index < pdf-bin-count [
      set coh-bins replace-item bin-index coh-bins (item bin-index coh-bins + 1)
    ]
  ]

  let total-coh-samples length cohesion-history
  let coh-x min-cohesion
  foreach coh-bins [ bin-count ->
    let pdf-value (bin-count / total-coh-samples) / coh-bin-width
    plotxy coh-x pdf-value
    set coh-x coh-x + coh-bin-width
  ]
end

; Torus world distance calculation function
to-report torus-distance [x1 y1 x2 y2]
  ; Calculate true shortest distance between two points in torus world
  let diff-x x2 - x1
  let diff-y y2 - y1

  ; Correct distance vector in torus world (choose shortest path)
  if abs(diff-x) > torus-world-width / 2 [
    ifelse diff-x > 0 [
      set diff-x diff-x - torus-world-width
    ] [
      set diff-x diff-x + torus-world-width
    ]
  ]

  if abs(diff-y) > torus-world-height / 2 [
    ifelse diff-y > 0 [
      set diff-y diff-y - torus-world-height
    ] [
      set diff-y diff-y + torus-world-height
    ]
  ]

  report sqrt(diff-x ^ 2 + diff-y ^ 2)
end

; Report function: task completion time
to-report task-completion-time
  ifelse completion-time > 0 [
    report completion-time
  ] [
    report 0
  ]
end

; Interface monitor report functions for research data
to-report current-polarization-value
  report precision current-polarization 3
end

to-report current-elongation-value
  report precision current-elongation 3
end

to-report current-cohesion-value
  report precision current-cohesion 3
end

to-report current-speed-value
  report precision barycenter-speed 3
end

to-report sheep-in-pen-count
  let pen-radius goal-radius
  let pen-detection-radius pen-radius * 1.08
  report count sheep with [torus-distance xcor ycor ([pxcor] of goal-location) ([pycor] of goal-location) <= pen-detection-radius]
end

to-report completion-percentage
  ifelse count sheep > 0 [
    let sheep-in-pen sheep-in-pen-count
    report precision (sheep-in-pen / count sheep * 100) 1
  ] [
    report 0
  ]
end

; Report sheep group threat level for research analysis
to-report group-threat-level
  let threat 0
  ask sheep [
    let nearby-dogs dogs in-radius sheep-dog-perception-radius
    if any? nearby-dogs [
      let min-dog-dist min [torus-distance xcor ycor ([xcor] of myself) ([ycor] of myself)] of nearby-dogs
      set threat threat + (sheep-dog-perception-radius - min-dog-dist) / sheep-dog-perception-radius
    ]
  ]
  if count sheep > 0 [ set threat threat / count sheep ]
  report precision threat 3
end
@#$#@#$#@
GRAPHICS-WINDOW
246
-1
735
489
-1
-1
10.7
1
8
1
1
1
0
1
1
1
-22
22
-22
22
0
0
1
ticks
20.0

BUTTON
5
25
71
58
setup
setup
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
82
25
145
58
go
go
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

SLIDER
4
64
176
97
num-sheep
num-sheep
10
300
123.0
1
1
NIL
HORIZONTAL

SLIDER
4
100
176
133
num-dogs
num-dogs
3
9
7.0
1
1
NIL
HORIZONTAL

SLIDER
4
137
176
170
sheep-base-speed
sheep-base-speed
2
4
2.5
0.5
1
NIL
HORIZONTAL

SLIDER
5
175
177
208
dog-base-speed
dog-base-speed
2
6
3.0
1
1
NIL
HORIZONTAL

SLIDER
5
249
208
282
sheep-cohesion-radius
sheep-cohesion-radius
3
25
12.5
0.5
1
NIL
HORIZONTAL

SLIDER
5
213
249
246
sheep-dog-perception-radius
sheep-dog-perception-radius
3
20
10.5
0.5
1
NIL
HORIZONTAL

SLIDER
5
285
177
318
avoidance-strength
avoidance-strength
1.0
5.0
2.0
0.5
1
NIL
HORIZONTAL

SLIDER
5
322
177
355
collection-threshold
collection-threshold
4
20
10.0
1
1
NIL
HORIZONTAL

SLIDER
5
359
177
392
driving-distance
driving-distance
8
60
12.0
1
1
NIL
HORIZONTAL

MONITOR
9
409
101
454
Sheep in pen
sheep-in-pen-count
17
1
11

MONITOR
112
409
208
454
Completion %
completion-percentage
17
1
11

MONITOR
9
460
95
505
Polarization
current-polarization-value
17
1
11

MONITOR
109
461
265
506
Completion time (ticks)
task-completion-time
17
1
11

MONITOR
10
511
82
556
Cohesion
current-cohesion-value
17
1
11

MONITOR
109
512
188
557
Elongation
current-elongation-value
17
1
11

PLOT
4
646
204
796
Speed PDF
NIL
PDF
0.0
1.0
0.0
20.0
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" ""

PLOT
207
646
407
796
Polarization PDF
NIL
PDF
0.0
2.0
0.0
10.0
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" ""

PLOT
309
494
509
644
Elongation PDF
NIL
PDF
0.0
2.0
0.0
20.0
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" ""

PLOT
406
646
606
796
Cohesion PDF
NIL
PDF
0.0
0.5
0.0
40.0
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" ""

@#$#@#$#@
## WHAT IS IT?

(a general understanding of what the model is trying to show or explain)

## HOW IT WORKS

(what rules the agents use to create the overall behavior of the model)

## HOW TO USE IT

(how to use the model, including a description of each of the items in the Interface tab)

## THINGS TO NOTICE

(suggested things for the user to notice while running the model)

## THINGS TO TRY

(suggested things for the user to try to do (move sliders, switches, etc.) with the model)

## EXTENDING THE MODEL

(suggested things to add or change in the Code tab to make the model more complicated, detailed, accurate, etc.)

## NETLOGO FEATURES

(interesting or unusual features of NetLogo that the model uses, particularly in the Code tab; or where workarounds were needed for missing features)

## RELATED MODELS

(models in the NetLogo Models Library and elsewhere which are of related interest)

## CREDITS AND REFERENCES

(a reference to the model's URL on the web if it has one, as well as any other necessary credits, citations, and links)
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

car
false
0
Polygon -7500403 true true 300 180 279 164 261 144 240 135 226 132 213 106 203 84 185 63 159 50 135 50 75 60 0 150 0 165 0 225 300 225 300 180
Circle -16777216 true false 180 180 90
Circle -16777216 true false 30 180 90
Polygon -16777216 true false 162 80 132 78 134 135 209 135 194 105 189 96 180 89
Circle -7500403 true true 47 195 58
Circle -7500403 true true 195 195 58

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dot
false
0
Circle -7500403 true true 90 90 120

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

sheep
false
15
Circle -1 true true 203 65 88
Circle -1 true true 70 65 162
Circle -1 true true 150 105 120
Polygon -7500403 true false 218 120 240 165 255 165 278 120
Circle -7500403 true false 214 72 67
Rectangle -1 true true 164 223 179 298
Polygon -1 true true 45 285 30 285 30 240 15 195 45 210
Circle -1 true true 3 83 150
Rectangle -1 true true 65 221 80 296
Polygon -1 true true 195 285 210 285 210 240 240 210 195 210
Polygon -7500403 true false 276 85 285 105 302 99 294 83
Polygon -7500403 true false 219 85 210 105 193 99 201 83

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

wolf
false
0
Polygon -16777216 true false 253 133 245 131 245 133
Polygon -7500403 true true 2 194 13 197 30 191 38 193 38 205 20 226 20 257 27 265 38 266 40 260 31 253 31 230 60 206 68 198 75 209 66 228 65 243 82 261 84 268 100 267 103 261 77 239 79 231 100 207 98 196 119 201 143 202 160 195 166 210 172 213 173 238 167 251 160 248 154 265 169 264 178 247 186 240 198 260 200 271 217 271 219 262 207 258 195 230 192 198 210 184 227 164 242 144 259 145 284 151 277 141 293 140 299 134 297 127 273 119 270 105
Polygon -7500403 true true -1 195 14 180 36 166 40 153 53 140 82 131 134 133 159 126 188 115 227 108 236 102 238 98 268 86 269 92 281 87 269 103 269 113

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270
@#$#@#$#@
NetLogo 6.4.0
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180
@#$#@#$#@
0
@#$#@#$#@
