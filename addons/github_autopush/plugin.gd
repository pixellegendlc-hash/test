@tool
extends EditorPlugin

const SETTINGS_PATH := "user://github_autopush.cfg"
const MENU_NAME := "GitHub AutoPush: Configura..."
const MENU_PUSH_NAME := "GitHub AutoPush: Carica adesso"

var repo_url := ""
var branch := "main"
var commit_message := "Auto-commit da Godot"
var ask_on_close := true

var _ask_dialog: ConfirmationDialog
var _settings_dialog: ConfirmationDialog
var _result_dialog: AcceptDialog
var _repo_edit: LineEdit
var _branch_edit: LineEdit
var _msg_edit: LineEdit
var _ask_check: CheckBox
var _closing_confirmed := false


func _enter_tree() -> void:
	_load_settings()
	_build_ask_dialog()
	_build_settings_dialog()
	_build_result_dialog()
	add_tool_menu_item(MENU_NAME, _open_settings)
	add_tool_menu_item(MENU_PUSH_NAME, _push_now_from_menu)
	get_tree().set_auto_accept_quit(false)
	var win := EditorInterface.get_base_control().get_window()
	if not win.close_requested.is_connected(_on_close_requested):
		win.close_requested.connect(_on_close_requested)
	print("[GitHub AutoPush] attivo, repo: ", repo_url if repo_url != "" else "(non configurato)")


func _exit_tree() -> void:
	var win := EditorInterface.get_base_control().get_window()
	if win.close_requested.is_connected(_on_close_requested):
		win.close_requested.disconnect(_on_close_requested)
	remove_tool_menu_item(MENU_NAME)
	remove_tool_menu_item(MENU_PUSH_NAME)
	get_tree().set_auto_accept_quit(true)
	for d in [_ask_dialog, _settings_dialog, _result_dialog]:
		if is_instance_valid(d):
			d.queue_free()


# ---------------------------------------------------------------- chiusura --

func _on_close_requested() -> void:
	print("[GitHub AutoPush] chiusura intercettata")
	if _closing_confirmed or not ask_on_close or repo_url.strip_edges() == "":
		_quit_now()
		return
	_ask_dialog.popup_centered()


func _quit_now() -> void:
	_closing_confirmed = true
	get_tree().set_auto_accept_quit(true)
	get_tree().quit()


func _on_ask_confirmed() -> void:
	var res := _do_push()
	if res.ok:
		_quit_now()
	else:
		# Push fallito: non chiudo in automatico, mostro l'errore
		_result_dialog.title = "Push fallito"
		_result_dialog.dialog_text = res.message + "\n\nL'editor NON e' stato chiuso. Riprova la chiusura per uscire comunque."
		_closing_confirmed = true  # alla prossima chiusura esce senza richiedere
		_result_dialog.popup_centered(Vector2i(600, 300))


func _on_ask_canceled() -> void:
	_quit_now()


# --------------------------------------------------------------------- git --

func _project_dir() -> String:
	return ProjectSettings.globalize_path("res://")


func _git(args: PackedStringArray) -> Dictionary:
	var out: Array = []
	var full_args := PackedStringArray(["-C", _project_dir()])
	full_args.append_array(args)
	var code := OS.execute("git", full_args, out, true)
	var text := ""
	for line in out:
		text += str(line)
	return {"code": code, "out": text.strip_edges()}


func _do_push() -> Dictionary:
	if repo_url.strip_edges() == "":
		return {"ok": false, "message": "Repository non configurato. Usa Progetto > Strumenti > GitHub AutoPush: Configura..."}

	var v := _git(PackedStringArray(["--version"]))
	if v.code != 0:
		return {"ok": false, "message": "Git non trovato. Installa git e assicurati che sia nel PATH."}

	# git init se serve
	var inside := _git(PackedStringArray(["rev-parse", "--is-inside-work-tree"]))
	if inside.code != 0 or inside.out != "true":
		var r := _git(PackedStringArray(["init"]))
		if r.code != 0:
			return {"ok": false, "message": "git init fallito:\n" + r.out}

	# assicura il branch
	_git(PackedStringArray(["checkout", "-B", branch]))

	# .gitignore base per Godot se manca
	var gi_path := "res://.gitignore"
	if not FileAccess.file_exists(gi_path):
		var f := FileAccess.open(gi_path, FileAccess.WRITE)
		if f:
			f.store_string(".godot/\n*.translation\n.import/\nexport.cfg\nexport_presets.cfg\n*.tmp\n.mono/\ndata_*/\n")
			f.close()

	# remote "origin"
	var remotes := _git(PackedStringArray(["remote"]))
	if "origin" in remotes.out.split("\n"):
		_git(PackedStringArray(["remote", "set-url", "origin", repo_url]))
	else:
		_git(PackedStringArray(["remote", "add", "origin", repo_url]))

	var add := _git(PackedStringArray(["add", "-A"]))
	if add.code != 0:
		return {"ok": false, "message": "git add fallito:\n" + add.out}

	var msg := commit_message
	if msg.strip_edges() == "":
		msg = "Auto-commit da Godot"
	msg += " (" + Time.get_datetime_string_from_system(false, true) + ")"

	var commit := _git(PackedStringArray(["commit", "-m", msg]))
	# code 1 con "nothing to commit" non e' un errore
	if commit.code != 0 and not ("nothing to commit" in commit.out or "nulla da committare" in commit.out):
		return {"ok": false, "message": "git commit fallito:\n" + commit.out}

	var push := _git(PackedStringArray(["push", "-u", "origin", branch]))
	if push.code != 0:
		return {"ok": false, "message": "git push fallito:\n" + push.out + "\n\nControlla URL del repo e credenziali (SSH key o credential manager)."}

	return {"ok": true, "message": "Push completato su " + repo_url + " (" + branch + ")"}


func _push_now_from_menu() -> void:
	var res := _do_push()
	_result_dialog.title = "GitHub AutoPush"
	_result_dialog.dialog_text = res.message
	_result_dialog.popup_centered(Vector2i(600, 300))


# ---------------------------------------------------------------------- UI --

func _build_ask_dialog() -> void:
	_ask_dialog = ConfirmationDialog.new()
	_ask_dialog.title = "GitHub AutoPush"
	_ask_dialog.dialog_text = "Vuoi caricare il progetto su GitHub prima di chiudere?"
	_ask_dialog.ok_button_text = "Si, carica"
	_ask_dialog.cancel_button_text = "No, chiudi"
	_ask_dialog.confirmed.connect(_on_ask_confirmed)
	_ask_dialog.canceled.connect(_on_ask_canceled)
	EditorInterface.get_base_control().add_child(_ask_dialog)


func _build_result_dialog() -> void:
	_result_dialog = AcceptDialog.new()
	_result_dialog.title = "GitHub AutoPush"
	EditorInterface.get_base_control().add_child(_result_dialog)


func _build_settings_dialog() -> void:
	_settings_dialog = ConfirmationDialog.new()
	_settings_dialog.title = "GitHub AutoPush - Configurazione"
	_settings_dialog.ok_button_text = "Salva"
	_settings_dialog.confirmed.connect(_on_settings_saved)

	var vb := VBoxContainer.new()
	vb.custom_minimum_size = Vector2(480, 0)

	vb.add_child(_label("URL repository (https://github.com/utente/repo.git oppure git@github.com:utente/repo.git)"))
	_repo_edit = LineEdit.new()
	_repo_edit.placeholder_text = "https://github.com/utente/repo.git"
	vb.add_child(_repo_edit)

	vb.add_child(_label("Branch"))
	_branch_edit = LineEdit.new()
	vb.add_child(_branch_edit)

	vb.add_child(_label("Messaggio di commit"))
	_msg_edit = LineEdit.new()
	vb.add_child(_msg_edit)

	_ask_check = CheckBox.new()
	_ask_check.text = "Chiedi di caricare quando chiudo l'editor"
	vb.add_child(_ask_check)

	_settings_dialog.add_child(vb)
	EditorInterface.get_base_control().add_child(_settings_dialog)


func _label(t: String) -> Label:
	var l := Label.new()
	l.text = t
	return l


func _open_settings() -> void:
	_repo_edit.text = repo_url
	_branch_edit.text = branch
	_msg_edit.text = commit_message
	_ask_check.button_pressed = ask_on_close
	_settings_dialog.popup_centered()


func _on_settings_saved() -> void:
	repo_url = _repo_edit.text.strip_edges()
	branch = _branch_edit.text.strip_edges()
	if branch == "":
		branch = "main"
	commit_message = _msg_edit.text
	ask_on_close = _ask_check.button_pressed
	_save_settings()


# ---------------------------------------------------------------- settings --

func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		repo_url = cfg.get_value("github", "repo_url", "")
		branch = cfg.get_value("github", "branch", "main")
		commit_message = cfg.get_value("github", "commit_message", "Auto-commit da Godot")
		ask_on_close = cfg.get_value("github", "ask_on_close", true)


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("github", "repo_url", repo_url)
	cfg.set_value("github", "branch", branch)
	cfg.set_value("github", "commit_message", commit_message)
	cfg.set_value("github", "ask_on_close", ask_on_close)
	cfg.save(SETTINGS_PATH)
