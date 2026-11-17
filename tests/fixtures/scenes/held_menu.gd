extends Control
## Test menu scene: opens like the real menu and stays open until `closed` is emitted from
## outside (the real menu closes on player input, which tests do not have).

signal closed

var rpg: Node
