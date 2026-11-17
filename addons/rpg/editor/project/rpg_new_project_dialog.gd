@tool
extends ConfirmationDialog

const NewProject := preload("res://addons/rpg/editor/project/rpg_new_project.gd")

signal project_created(folder: String, open_editor: bool)

var name_edit: LineEdit
var folder_edit: LineEdit
var style_pick: OptionButton
var open_check: CheckBox
var message: Label
var folder_picker: FileDialog


func _init() -> void:
	title = "New RPG project"
	ok_button_text = "Create project"
	dialog_hide_on_ok = false
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 540
	add_child(box)
	var info := Label.new()
	info.custom_minimum_size.x = 540
	info.text = "Create a separate Godot project with RPG Kit, a starter database and a first map."
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(info)
	_label(box, "Game name")
	name_edit = LineEdit.new()
	name_edit.text = "My Game"
	box.add_child(name_edit)
	_label(box, "Project folder (new or empty)")
	var row := HBoxContainer.new()
	box.add_child(row)
	folder_edit = LineEdit.new()
	folder_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	folder_edit.text = ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir().path_join("my_game")
	row.add_child(folder_edit)
	var browse := Button.new()
	browse.text = "Browse..."
	row.add_child(browse)
	folder_picker = FileDialog.new()
	folder_picker.title = "Choose an empty project folder"
	folder_picker.access = FileDialog.ACCESS_FILESYSTEM
	folder_picker.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	add_child(folder_picker)
	browse.pressed.connect(func():
		folder_picker.current_dir = folder_edit.text.get_base_dir()
		folder_picker.popup_centered_ratio(0.7))
	folder_picker.dir_selected.connect(func(path): folder_edit.text = path; _validate())
	_label(box, "Style")
	style_pick = OptionButton.new()
	for key in RPGProjectTemplate.STYLES:
		var style: Dictionary = RPGProjectTemplate.STYLES[key]
		style_pick.add_item("%s (%d×%d)" % [style.name, style.screen.x, style.screen.y])
		style_pick.set_item_metadata(style_pick.item_count - 1, key)
	box.add_child(style_pick)
	open_check = CheckBox.new()
	open_check.text = "Open the new project in another editor window"
	open_check.button_pressed = true
	box.add_child(open_check)
	message = Label.new()
	message.custom_minimum_size.x = 540
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(message)
	name_edit.text_changed.connect(func(_text): _validate())
	folder_edit.text_changed.connect(func(_text): _validate())
	confirmed.connect(_create)
	canceled.connect(queue_free)
	_validate()


func _label(box: VBoxContainer, text: String) -> void:
	var label := Label.new()
	label.text = text
	box.add_child(label)


func _validate() -> void:
	message.text = NewProject.destination_error(folder_edit.text, name_edit.text)
	get_ok_button().disabled = message.text != ""


func _create() -> void:
	_validate()
	if get_ok_button().disabled:
		return
	get_ok_button().disabled = true
	var result := NewProject.create(folder_edit.text, name_edit.text, str(style_pick.get_selected_metadata()))
	if result.error != OK:
		message.text = "\n".join(PackedStringArray(result.messages))
		get_ok_button().disabled = false
		return
	project_created.emit(result.folder, open_check.button_pressed)
	hide()
	queue_free()
