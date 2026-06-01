class_name RunOverlay
extends CanvasLayer
##
## Container for every in-run overlay. Main.gd holds one reference here
## and reaches the individual panels through typed handles instead of
## six separate @onready vars.
##

@onready var boot: BootOverlay = $BootOverlay
@onready var game_over: GameOverOverlay = $GameOverOverlay
@onready var level_up: LevelUpPanel = $LevelUpPanel
@onready var hand_augment: HandAugmentPanel = $HandAugmentPanel
@onready var pause: PauseMenu = $PauseMenu
@onready var settings: SettingsMenu = $SettingsMenu
