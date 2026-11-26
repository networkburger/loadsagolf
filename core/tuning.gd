class_name Tuning
extends Resource
## Every "feel" constant in one place, so playtest tweaks never touch code.
## Units: logical px (1024x768 design space) and seconds.

enum GrabMode {
	BRAKE,        ## grab any time; speed is cut by brake_fraction once on grab
	FULL_STOP,    ## grab any time; ball stops dead
	RAMP,         ## grab any time; ball keeps braking the longer you hold
	RESTING_ONLY, ## classic: can only grab a stopped ball
}

@export_group("Shot")
@export var dead_zone := 24.0            ## drag shorter than this = cancel
@export var max_drag := 240.0            ## drag length that gives full power
@export var max_shot_speed := 1500.0
@export var power_curve := 1.35          ## >1 = finer control at low power

@export_group("Grab")
@export var grab_mode := GrabMode.BRAKE
@export_range(0.0, 1.0) var brake_fraction := 0.8
@export var ramp_brake_per_sec := 4.0    ## RAMP: exponential decay rate while held
@export var add_leftover_speed := true   ## shot adds to leftover speed (vs replaces it)
@export var grab_radius_2p := 64.0

@export_group("Ball")
@export var ball_radius := 12.0
@export var rolling_decel := 260.0       ## constant deceleration (px/s^2) on grass
@export var drag_coeff := 0.6            ## speed-proportional drag (1/s)
@export var stop_speed := 18.0           ## below this an unheld ball snaps to rest
@export var wall_restitution := 0.72
@export var ball_restitution := 0.9
@export var bumper_restitution := 1.25   ## >1: bumpers add energy
@export var bumper_min_speed := 380.0    ## bumpers always kick at least this hard

@export_group("Hole")
@export var hole_radius := 20.0
@export var capture_speed := 520.0       ## slower than this over the hole = in
@export var hole_pull := 900.0           ## gentle suction near the hole (px/s^2)
@export var hole_pull_range := 2.2       ## pull starts at hole_radius * this
