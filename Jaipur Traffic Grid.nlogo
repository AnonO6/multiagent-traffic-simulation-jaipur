
globals
[
  grid-x-inc               
  grid-y-inc               
  acceleration             
  phase                    
  num-cars-stopped         
  current-light            
  total-wait-time          ;; tracks total waiting time for all vehicles
  emergency-vehicle-present? ;; tracks presence of emergency vehicles
  
  ;; patch agentsets
  intersections 
  roads         
]

;; Extended turtle properties for intelligent agents
turtles-own
[
  speed         
  up-car?       
  wait-time     
  patience      ;; tolerance for waiting
  local-knowledge ;; knowledge of alternate routes
  vehicle-type    ;; car, bike, auto-rickshaw, bus
  route-preference ;; preferred path based on historical data
  has-emergency?  ;; whether this is an emergency vehicle
]

patches-own
[
  intersection?   
  green-light-up?
  my-row         
  my-column      
  my-phase       
  auto?          
  congestion-level 
  historical-data  
  location-name    ;; Added for Jaipur locations
]


;; Setup Procedures

to setup-patches
  ask patches [
    set intersection? false
    set auto? false
    set green-light-up? true
    set my-row -1
    set my-column -1
    set my-phase -1
    set pcolor brown + 3
    set congestion-level 0
    set historical-data []
    set location-name ""  ;; Initialize location name
  ]

  set roads patches with [
    (floor((pxcor + max-pxcor - floor(grid-x-inc - 1)) mod grid-x-inc) = 0) or
    (floor((pycor + max-pycor) mod grid-y-inc) = 0)
  ]
  
  set intersections roads with [
    (floor((pxcor + max-pxcor - floor(grid-x-inc - 1)) mod grid-x-inc) = 0) and
    (floor((pycor + max-pycor) mod grid-y-inc) = 0)
  ]

  ask roads [ set pcolor white ]
  setup-intersections
  setup-jaipur-labels
end

;; New procedure to setup Jaipur location labels
to setup-jaipur-labels
  ask intersections [
    let loc-x floor((pxcor + max-pxcor) / grid-x-inc)
    let loc-y floor((pycor + max-pycor) / grid-y-inc)
    
    ;; Assign major Jaipur intersection names based on location
    (ifelse
      loc-x = 0 and loc-y = 0 [ set location-name "Ajmeri Gate" ]
      loc-x = 1 and loc-y = 0 [ set location-name "MI Road" ]
      loc-x = 2 and loc-y = 0 [ set location-name "Tonk Road" ]
      loc-x = 0 and loc-y = 1 [ set location-name "Pink Square" ]
      loc-x = 1 and loc-y = 1 [ set location-name "Chomu Circle" ]
      loc-x = 2 and loc-y = 1 [ set location-name "C-Scheme" ]
      loc-x = 0 and loc-y = 2 [ set location-name "Bani Park" ]
      loc-x = 1 and loc-y = 2 [ set location-name "Civil Lines" ]
      loc-x = 2 and loc-y = 2 [ set location-name "JLN Marg" ]
      [ set location-name "Junction" ])
    
    ;; Display location names
    set plabel location-name
    set plabel-color black
  ]
end
;; Make a patch the current intersection being monitored
to make-current [light]
  set current-light light
  set current-phase [my-phase] of current-light
  set current-auto? [auto?] of current-light
end

;; Label the current intersection being monitored
to label-current
  ask current-light [
    ask patch-at -1 1 [
      set plabel-color black
      set plabel "current"
    ]
  ]
end

;; Set up initial car properties and position
to setup-cars
  set speed 0
  set wait-time 0
  put-on-empty-road
  ifelse intersection? [
    ifelse random 2 = 0
    [ set up-car? true ]
    [ set up-car? false ]
  ]
  [
    ifelse (floor((pxcor + max-pxcor - floor(grid-x-inc - 1)) mod grid-x-inc) = 0)
    [ set up-car? true ]
    [ set up-car? false ]
  ]
  ifelse up-car?
  [ set heading 180 ]
  [ set heading 90 ]
end

;; Set car color based on speed and type
to set-car-color
  let base-color blue
  if vehicle-type = "two-wheeler" [ set base-color green ]
  if vehicle-type = "auto-rickshaw" [ set base-color yellow ]
  if vehicle-type = "bus" [ set base-color red ]
  
  ifelse speed < (speed-limit / 2)
  [ set color base-color ]
  [ set color base-color - 2 ]
  
  if has-emergency? [ set color red ]
end

;; Setup the intersections with traffic lights
to setup-intersections
  ask intersections [
    set intersection? true
    set green-light-up? true
    set my-phase 0
    set auto? true
    set my-row floor((pycor + max-pycor) / grid-y-inc)
    set my-column floor((pxcor + max-pxcor) / grid-x-inc)
    ;; Initialize historical data storage
    set historical-data []
    set-signal-colors
  ]
end

;; Place car on an empty road patch
to put-on-empty-road
  let target-patch one-of roads with [not any? turtles-on self]
  ;; If regular roads are full, try finding space near intersections
  if target-patch = nobody [
    set target-patch one-of roads with [
      not any? turtles-on self and
      any? neighbors with [intersection?]
    ]
  ]
  if target-patch != nobody [
    move-to target-patch
  ]
end

;; Increase speed of vehicle
to speed-up
  ifelse speed > speed-limit
  [ 
    set speed speed-limit 
    ;; Adjust speed limit based on vehicle type
    if vehicle-type = "two-wheeler" [ set speed speed * 1.2 ]
    if vehicle-type = "bus" [ set speed speed * 0.8 ]
    if vehicle-type = "auto-rickshaw" [ set speed speed * 0.9 ]
  ]
  [ set speed speed + acceleration ]
end

;; Control traffic signal changes based on phase and conditions
to set-signals
  ask intersections with [auto? and phase = floor ((my-phase * ticks-per-cycle) / 100)] [
    ;; Check for emergency vehicles before changing signals
    let emergency-approaching? any? turtles in-radius 5 with [has-emergency?]
    
    ;; If there's an emergency vehicle, prioritize its direction
    ifelse emergency-approaching? [
      let emergency-vehicle one-of turtles in-radius 5 with [has-emergency?]
      ifelse [up-car?] of emergency-vehicle [
        set green-light-up? true
      ] [
        set green-light-up? false
      ]
    ] [
      ;; Normal signal change if no emergency
      set green-light-up? (not green-light-up?)
      
      ;; Adjust timing based on congestion
      let vertical-congestion count turtles in-radius 3 with [up-car?]
      let horizontal-congestion count turtles in-radius 3 with [not up-car?]
      
      ;; If significant congestion difference, favor the more congested direction
      if abs (vertical-congestion - horizontal-congestion) > 3 [
        set green-light-up? (vertical-congestion > horizontal-congestion)
      ]
    ]
    
    ;; Apply the signal color changes
    set-signal-colors
  ]
end

;; Set colors for traffic signals
to set-signal-colors  ;; intersection (patch) procedure
  ifelse power? [
    ifelse green-light-up? [
      ask patch-at -1 0 [ set pcolor red ]
      ask patch-at 0 1 [ set pcolor green ]
      ;; Add yellow light warning when signal is about to change
      if phase >= ticks-per-cycle - 10 [
        ifelse green-light-up? [
          ask patch-at 0 1 [ set pcolor yellow ]
        ] [
          ask patch-at -1 0 [ set pcolor yellow ]
        ]
      ]
    ] [
      ask patch-at -1 0 [ set pcolor green ]
      ask patch-at 0 1 [ set pcolor red ]
    ]
  ] [
    ask patch-at -1 0 [ set pcolor white ]
    ask patch-at 0 1 [ set pcolor white ]
  ]
end

;; Decrease speed of vehicle
to slow-down
  ifelse speed <= 0 [
    set speed 0
  ] [
    ;; Different deceleration rates based on vehicle type
    let decel-rate acceleration
    if vehicle-type = "bus" [ set decel-rate acceleration * 0.8 ]  ;; buses slow down more gradually
    if vehicle-type = "two-wheeler" [ set decel-rate acceleration * 1.2 ]  ;; two-wheelers can brake faster
    set speed speed - decel-rate
  ]
end

;; Update the current intersection being monitored
to update-current
  ask current-light [
    set my-phase current-phase
    set auto? current-auto?
    ;; Update historical data
    let current-congestion count turtles in-radius 3
    set historical-data lput current-congestion historical-data
    if length historical-data > 100 [
      set historical-data but-first historical-data  ;; keep last 100 readings
    ]
  ]
end

;; Advance to next phase of traffic signal cycle
to next-phase
  ;; The phase cycles from 0 to ticks-per-cycle, then starts over
  set phase phase + 1
  if phase mod ticks-per-cycle = 0 [
    set phase 0
  ]
end

;; Set speed based on surrounding traffic
to set-speed [ delta-x delta-y ]
  let turtles-ahead turtles-at delta-x delta-y
  
  ifelse any? turtles-ahead [
    ifelse any? (turtles-ahead with [ up-car? != [up-car?] of myself ]) [
      set speed 0
    ]
    [
      set speed [speed] of one-of turtles-ahead
      slow-down
    ]
  ]
  [ speed-up ]
  
  ;; Adjust speed based on vehicle type
  if vehicle-type = "two-wheeler" [ set speed speed * 1.2 ]
  if vehicle-type = "bus" [ set speed speed * 0.8 ]
  if vehicle-type = "auto-rickshaw" [ set speed speed * 0.9 ]
end

to change-current
  let candidate one-of [neighbors4] of current-light
  if candidate != nobody [
    make-current candidate
  ]
end

to choose-current
  if mouse-down? [
    let candidate patch mouse-xcor mouse-ycor
    if [intersection?] of candidate [
      make-current candidate
    ]
  ]
end


to setup
  clear-all
  setup-globals
  setup-patches
  make-current one-of intersections
  label-current
  
  set-default-shape turtles "car"
  
  if (num-cars > count roads)
  [
    user-message (word "Too many vehicles for the available roads. "
                      "Please adjust grid size or reduce number of vehicles.")
    stop
  ]
  
  create-turtles num-cars
  [
    setup-cars
    initialize-agent-properties
    set-car-color
    record-data
  ]
  
  ask turtles [ set-car-speed ]
  reset-ticks
end

;; Initialize agent-specific properties
to initialize-agent-properties  ;; turtle procedure
  set patience random-normal 50 10  ;; normal distribution of patience
  set local-knowledge random 100    ;; knowledge level 0-100
  set vehicle-type assign-vehicle-type
  set route-preference random 3     ;; initial route preference
  set has-emergency? random 100 < 2 ;; 2% chance of being emergency vehicle
end

;; Assign vehicle types based on Jaipur traffic composition
to-report assign-vehicle-type
  let random-num random 100
  if random-num < 40 [ report "two-wheeler" ]    ;; 40% two-wheelers
  if random-num < 70 [ report "car" ]            ;; 30% cars
  if random-num < 85 [ report "auto-rickshaw" ]  ;; 15% auto-rickshaws
  report "bus"                                   ;; 15% buses
end

;; Modified setup-globals with Jaipur-specific initializations
to setup-globals
  set current-light nobody
  set phase 0
  set num-cars-stopped 0
  set grid-x-inc world-width / grid-size-x
  set grid-y-inc world-height / grid-size-y
  set acceleration 0.099
  
  ;; Initialize Jaipur-specific variables
  set emergency-vehicle-present? false
end

;; Enhanced car movement procedure with intelligent behavior
to set-car-speed  ;; turtle procedure
  ifelse pcolor = red
  [
    set speed 0
    adapt-to-wait
  ]
  [
    ifelse up-car?
    [ set-speed 0 -1 ]
    [ set-speed 1 0 ]
  ]
  
  ;; Emergency vehicle behavior
  if has-emergency? [
    handle-emergency-vehicle
  ]
end

;; New procedure for emergency vehicle handling
to handle-emergency-vehicle
  set emergency-vehicle-present? true
  set speed speed-limit
  ask other turtles-here [
    move-to one-of neighbors with [pcolor = white]
  ]
end

;; New procedure for adapting to long waits
to adapt-to-wait  ;; turtle procedure
  if wait-time > patience [
    consider-alternate-route
  ]
end

;; New procedure for finding alternate routes
to consider-alternate-route  ;; turtle procedure
  if local-knowledge > 50 [
    let alternative-path one-of neighbors with [
      pcolor = white and
      not any? turtles-here
    ]
    if alternative-path != nobody [
      move-to alternative-path
    ]
  ]
end

;; Modified go procedure with intelligent traffic management
to go
  update-current
  manage-traffic-flow
  set-signals
  set num-cars-stopped 0
  
  ask turtles [
    set-car-speed
    fd speed
    record-data
    set-car-color
  ]
  
  update-statistics
  next-phase
  tick
end



;; New procedure for dynamic traffic flow management
to manage-traffic-flow
  ask intersections [
    set congestion-level count turtles in-radius 3
    if congestion-level > 5 [
      optimize-signal-timing
    ]
  ]
end

;; New procedure for optimizing signal timing
to optimize-signal-timing  ;; intersection procedure
  if auto? [
    let approaching-emergency any? turtles in-radius 5 with [has-emergency?]
    if approaching-emergency [
      set green-light-up? not green-light-up?
      set-signal-colors
    ]
  ]
end


;; Enhanced data recording
to record-data  ;; turtle procedure
  ifelse speed = 0
  [
    set num-cars-stopped num-cars-stopped + 1
    set wait-time wait-time + 1
    set total-wait-time total-wait-time + 1
  ]
  [ set wait-time 0 ]
end

to update-statistics
  let avg-wait-time 0
  if any? turtles [
    set avg-wait-time total-wait-time / count turtles
  ]
end

;; Copyright 2003 Uri Wilensky (Modified for Jaipur Traffic Management 2024)


@#$#@#$#@
GRAPHICS-WINDOW
475
10
1149
685
-1
-1
18
1
12
1
1
1
0
1
1
1
-18
18
-18
18
1
1
1
ticks
30

PLOT
5
550
223
714
Average Wait Time of Cars
Time
Average Wait
0
100
0
5
true
false
"" ""
PENS
"default" 1 0 -16777216 true "" "plot mean [wait-time] of turtles"

PLOT
228
377
444
542
Average Speed of Cars
Time
Average Speed
0
100
0
1
true
false
"set-plot-y-range 0 speed-limit" ""
PENS
"default" 1 0 -16777216 true "" "plot mean [speed] of turtles"

SLIDER
108
35
205
68
grid-size-y
grid-size-y
1
9
5
1
1
NIL
HORIZONTAL

SLIDER
12
35
106
68
grid-size-x
grid-size-x
1
9
5
1
1
NIL
HORIZONTAL

SWITCH
12
107
107
140
power?
power?
0
1
-1000

SLIDER
12
71
293
104
num-cars
num-cars
1
400
200
1
1
NIL
HORIZONTAL

PLOT
5
376
219
540
Stopped Cars
Time
Stopped Cars
0
100
0
100
true
false
"set-plot-y-range 0 num-cars" ""
PENS
"default" 1 0 -16777216 true "" "plot num-cars-stopped"

BUTTON
221
184
285
217
Go
go
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
0

BUTTON
208
35
292
68
Setup
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

SLIDER
11
177
165
210
speed-limit
speed-limit
0.1
1
1
0.1
1
NIL
HORIZONTAL

MONITOR
205
132
310
177
Current Phase
phase
3
1
11

SLIDER
11
143
165
176
ticks-per-cycle
ticks-per-cycle
1
100
20
1
1
NIL
HORIZONTAL

SLIDER
146
256
302
289
current-phase
current-phase
0
99
0
1
1
%
HORIZONTAL

BUTTON
9
292
143
325
Change light
change-current
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
0

SWITCH
9
256
144
289
current-auto?
current-auto?
0
1
-1000

BUTTON
145
292
300
325
Select intersection
choose-current
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
0
@#$#@#$#@
## WHAT IS IT?

This is a model of traffic moving in a city grid. It allows you to control traffic lights and global variables, such as the speed limit and the number of cars, and explore traffic dynamics.

Try to develop strategies to improve traffic and to understand the different ways to measure the quality of traffic.

## HOW IT WORKS

Each time step, the cars attempt to move forward at their current speed.  If their current speed is less than the speed limit and there is no car directly in front of them, they accelerate.  If there is a slower car in front of them, they match the speed of the slower car and deccelerate.  If there is a red light or a stopped car in front of them, they stop.

There are two different ways the lights can change.  First, the user can change any light at any time by making the light current, and then clicking CHANGE LIGHT.  Second, lights can change automatically, once per cycle.  Initially, all lights will automatically change at the beginning of each cycle.

## HOW TO USE IT

Change the traffic grid (using the sliders GRID-SIZE-X and GRID-SIZE-Y) to make the desired number of lights.  Change any other of the settings that you would like to change.  Press the SETUP button.

At this time, you may configure the lights however you like, with any combination of auto/manual and any phase. Changes to the state of the current light are made using the CURRENT-AUTO?, CURRENT-PHASE and CHANGE LIGHT controls.  You may select the current intersection using the SELECT INTERSECTION control.  See below for details.

Start the simulation by pressing the GO button.  You may continue to make changes to the lights while the simulation is running.

### Buttons

SETUP - generates a new traffic grid based on the current GRID-SIZE-X and GRID-SIZE-Y and NUM-CARS number of cars.  This also clears all the plots. All lights are set to auto, and all phases are set to 0.
GO - runs the simulation indefinitely
CHANGE LIGHT - changes the direction traffic may flow through the current light. A light can be changed manually even if it is operating in auto mode.
SELECT INTERSECTION - allows you to select a new "current" light. When this button is depressed, click in the intersection which you would like to make current. When you've selected an intersection, the "current" label will move to the new intersection and this button will automatically pop up.

### Sliders

SPEED-LIMIT - sets the maximum speed for the cars
NUM-CARS - the number of cars in the simulation (you must press the SETUP button to see the change)
TICKS-PER-CYCLE - sets the number of ticks that will elapse for each cycle.  This has no effect on manual lights.  This allows you to increase or decrease the granularity with which lights can automatically change.
GRID-SIZE-X - sets the number of vertical roads there are (you must press the SETUP button to see the change)
GRID-SIZE-Y - sets the number of horizontal roads there are (you must press the SETUP button to see the change)
CURRENT-PHASE - controls when the current light changes, if it is in auto mode. The slider value represents the percentage of the way through each cycle at which the light should change. So, if the TICKS-PER-CYCLE is 20 and CURRENT-PHASE is 75%, the current light will switch at tick 15 of each cycle.

### Switches

POWER? - toggles the presence of traffic lights
CURRENT-AUTO? - toggles the current light between automatic mode, where it changes once per cycle (according to CURRENT-PHASE), and manual, in which you directly control it with CHANGE LIGHT.

### Plots

STOPPED CARS - displays the number of stopped cars over time
AVERAGE SPEED OF CARS - displays the average speed of cars over time
AVERAGE WAIT TIME OF CARS - displays the average time cars are stopped over time

## THINGS TO NOTICE

When cars have stopped at a traffic light, and then they start moving again, the traffic jam will move backwards even though the cars are moving forwards.  Why is this?

When POWER? is turned off and there are quite a few cars on the roads, "gridlock" usually occurs after a while.  In fact, gridlock can be so severe that traffic stops completely.  Why is it that no car can move forward and break the gridlock?  Could this happen in the real world?

Gridlock can occur when the power is turned on, as well.  What kinds of situations can lead to gridlock?

## THINGS TO TRY

Try changing the speed limit for the cars.  How does this affect the overall efficiency of the traffic flow?  Are fewer cars stopping for a shorter amount of time?  Is the average speed of the cars higher or lower than before?

Try changing the number of cars on the roads.  Does this affect the efficiency of the traffic flow?

How about changing the speed of the simulation?  Does this affect the efficiency of the traffic flow?

Try running this simulation with all lights automatic.  Is it harder to make the traffic move well using this scheme than controlling one light manually?  Why?

Try running this simulation with all lights automatic.  Try to find a way of setting the phases of the traffic lights so that the average speed of the cars is the highest.  Now try to minimize the number of stopped cars.  Now try to decrease the average wait time of the cars.  Is there any correlation between these different metrics?

## EXTENDING THE MODEL

Currently, the maximum speed limit (found in the SPEED-LIMIT slider) for the cars is 1.0.  This is due to the fact that the cars must look ahead the speed that they are traveling to see if there are cars ahead of them.  If there aren't, they speed up.  If there are, they slow down.  Looking ahead for a value greater than 1 is a little bit tricky.  Try implementing the correct behavior for speeds greater than 1.

When a car reaches the edge of the world, it reappears on the other side.  What if it disappeared, and if new cars entered the city at random locations and intervals?

## NETLOGO FEATURES

This model uses two forever buttons which may be active simultaneously, to allow the user to select a new current intersection while the model is running.

It also uses a chooser to allow the user to choose between several different possible plots, or to display all of them at once.

## RELATED MODELS

- "Traffic Basic": a simple model of the movement of cars on a highway.

- "Traffic Basic Utility": a version of "Traffic Basic" including a utility function for the cars.

- "Traffic Basic Adaptive": a version of "Traffic Basic" where cars adapt their acceleration to try and maintain a smooth flow of traffic.

- "Traffic Basic Adaptive Individuals": a version of "Traffic Basic Adaptive" where each car adapts individually, instead of all cars adapting in unison.

- "Traffic 2 Lanes": a more sophisticated two-lane version of the "Traffic Basic" model.

- "Traffic Intersection": a model of cars traveling through a single intersection.

- "Traffic Grid Goal": a version of "Traffic Grid" where the cars have goals, namely to drive to and from work.

- "Gridlock HubNet": a version of "Traffic Grid" where students control traffic lights in real-time.

- "Gridlock Alternate HubNet": a version of "Gridlock HubNet" where students can enter NetLogo code to plot custom metrics.

## HOW TO CITE

If you mention this model or the NetLogo software in a publication, we ask that you include the citations below.

For the model itself:

* Wilensky, U. (2003).  NetLogo Traffic Grid model.  http://ccl.northwestern.edu/netlogo/models/TrafficGrid.  Center for Connected Learning and Computer-Based Modeling, Northwestern University, Evanston, IL.

Please cite the NetLogo software as:

* Wilensky, U. (1999). NetLogo. http://ccl.northwestern.edu/netlogo/. Center for Connected Learning and Computer-Based Modeling, Northwestern University, Evanston, IL.

## COPYRIGHT AND LICENSE

Copyright 2003 Uri Wilensky.

![CC BY-NC-SA 3.0](http://ccl.northwestern.edu/images/creativecommons/byncsa.png)

This work is licensed under the Creative Commons Attribution-NonCommercial-ShareAlike 3.0 License.  To view a copy of this license, visit https://creativecommons.org/licenses/by-nc-sa/3.0/ or send a letter to Creative Commons, 559 Nathan Abbott Way, Stanford, California 94305, USA.

Commercial licenses are also available. To inquire about commercial licenses, please contact Uri Wilensky at uri@northwestern.edu.

This model was created as part of the projects: PARTICIPATORY SIMULATIONS: NETWORK-BASED DESIGN FOR SYSTEMS LEARNING IN CLASSROOMS and/or INTEGRATED SIMULATION AND MODELING ENVIRONMENT. The project gratefully acknowledges the support of the National Science Foundation (REPP & ROLE programs) -- grant numbers REC #9814682 and REC-0126227.

<!-- 2003 -->
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
true
0
Polygon -7500403 true true 180 15 164 21 144 39 135 60 132 74 106 87 84 97 63 115 50 141 50 165 60 225 150 285 165 285 225 285 225 15 180 15
Circle -16777216 true false 180 30 90
Circle -16777216 true false 180 180 90
Polygon -16777216 true false 80 138 78 168 135 166 135 91 105 106 96 111 89 120
Circle -7500403 true true 195 195 58
Circle -7500403 true true 195 47 58

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
0
-0.2 0 0 1
0 1 1 0
0.2 0 0 1
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180
@#$#@#$#@

@#$#@#$#@
