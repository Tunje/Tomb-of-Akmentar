class_name WeaponData
extends Resource
## Stats for one gun. Stand-in era guns are built in WeaponData.defaults().

@export var id := ""
@export var display_name := ""
@export var damage := 30.0
@export var pellets := 1
@export var mag_size := 6
@export var fire_interval := 0.35  # seconds between shots
@export var reload_time := 2.0
@export var spread_hip := 2.0  # degrees, standing still
@export var spread_aim := 0.3
@export var spread_move := 1.5  # added while moving
@export var recoil_pitch := 3.0  # degrees of camera kick per shot
@export var recoil_yaw := 0.8  # random +- yaw kick
@export var recoil_recover := 10.0  # how fast the kick settles
@export var shake := 0.25  # camera trauma per shot
@export var stagger := 1.0  # stagger points per hit
@export var knockback := 1.0
@export var range_m := 80.0
@export var bullet_speed := 250.0  # m/s; real rounds, not hitscan
@export var falloff_start := 30.0  # damage drops linearly to 50% at range_m
@export var aim_fov := 50.0
@export var sound_pitch := 1.0
@export var model_length := 0.35  # stand-in box length when there's no model
## image-to-3d GLB: barrel along -Z, origin at the grip, an empty named "muzzle".
@export var model_path := ""
## Where the left hand holds the gun, in the model's space (zero = one-handed / the clip's hold).
@export var foregrip := Vector3.ZERO


static func defaults() -> Array[WeaponData]:
	var revolver := WeaponData.new()
	revolver.id = "revolver"
	revolver.display_name = "Service Revolver"
	revolver.damage = 38.0
	revolver.mag_size = 6
	revolver.fire_interval = 0.32
	revolver.reload_time = 2.1
	revolver.spread_hip = 1.6
	revolver.spread_aim = 0.25
	revolver.recoil_pitch = 3.2
	revolver.recoil_yaw = 0.9
	revolver.shake = 0.28
	revolver.stagger = 1.0
	revolver.knockback = 1.2
	revolver.falloff_start = 20.0
	revolver.aim_fov = 52.0
	revolver.sound_pitch = 1.15
	revolver.model_length = 0.28
	revolver.bullet_speed = 220.0
	revolver.model_path = "res://assets/guns/revolver_cairo.glb"

	var rifle := WeaponData.new()
	rifle.id = "rifle"
	rifle.display_name = "Lever Rifle"
	rifle.damage = 70.0
	rifle.mag_size = 8
	rifle.fire_interval = 0.7  # lever cycle
	rifle.reload_time = 2.8
	rifle.spread_hip = 2.4
	rifle.spread_aim = 0.08
	rifle.spread_move = 2.5
	rifle.recoil_pitch = 5.0
	rifle.recoil_yaw = 0.6
	rifle.recoil_recover = 7.0
	rifle.shake = 0.38
	rifle.stagger = 2.2
	rifle.knockback = 2.0
	rifle.range_m = 120.0
	rifle.falloff_start = 60.0
	rifle.aim_fov = 38.0
	rifle.sound_pitch = 0.85
	rifle.model_length = 0.95
	rifle.bullet_speed = 560.0
	rifle.model_path = "res://assets/guns/rifle_lever.glb"
	rifle.foregrip = Vector3(0, -0.02, -0.42)

	var shotgun := WeaponData.new()
	shotgun.id = "shotgun"
	shotgun.display_name = "Double Shotgun"
	shotgun.damage = 13.0
	shotgun.pellets = 10
	shotgun.mag_size = 2
	shotgun.fire_interval = 0.28
	shotgun.reload_time = 2.3
	shotgun.spread_hip = 5.0
	shotgun.spread_aim = 3.6
	shotgun.spread_move = 1.0
	shotgun.recoil_pitch = 7.5
	shotgun.recoil_yaw = 1.6
	shotgun.recoil_recover = 6.0
	shotgun.shake = 0.6
	shotgun.stagger = 0.45  # per pellet
	shotgun.knockback = 0.5  # per pellet
	shotgun.range_m = 40.0
	shotgun.falloff_start = 8.0
	shotgun.aim_fov = 56.0
	shotgun.sound_pitch = 0.7
	shotgun.model_length = 0.85
	shotgun.bullet_speed = 380.0
	shotgun.model_path = "res://assets/guns/shotgun_tombsweeper.glb"
	shotgun.foregrip = Vector3(0, -0.03, -0.3)

	return [revolver, rifle, shotgun]
