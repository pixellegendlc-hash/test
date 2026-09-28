@tool
extends EditorPlugin

const SETTINGS_PATH := "user://github_autopush.cfg"
const MENU_NAME := "GitHub AutoPush: Configura..."
const MENU_PUSH_NAME := "GitHub AutoPush: Carica adesso"
const BUTTON_TEXT := "Push e chiudi"

var repo_url := ""
var branch := "main"
var commit_message := "Auto-commit da Godot"

var _push_button: Button
var _settings_dialog: ConfirmationDialog
var _result_dialog: AcceptDialog
var _repo_edit: LineEdit
var _branch_edit: LineEdit
var _msg_edit: LineEdit


func _enter_tree() -> void:
	_load_settings()
	_build_settings_dialog()
	_build_result_dialog()
	_build_push_button()
	add_tool_menu_item(MENU_NAME, _open_settings)
	add_tool_menu_item(MENU_PUSH_NAME, _push_now_from_menu)
	print("[GitHub AutoPush] attivo, repo: ", repo_url if repo_url != "" else "(non configurato)")


func _exit_tree() -> void:
	if is_instance_valid(_push_button):
		_push_button.get_parent().remove_child(_push_button)
		_push_button.queue_free()
	remove_tool_menu_item(MENU_NAME)
	remove_tool_menu_item(MENU_PUSH_NAME)
	for d in [_settings_dialog, _result_dialog]:
		if is_instance_valid(d):
			d.queue_free()


# ---------------------------------------------------------------- chiusura --

func _quit_now() -> void:
	get_tree().quit()


func _on_push_and_close_pressed() -> void:
	if repo_url.strip_edges() == "":
		_result_dialog.title = "GitHub AutoPush"
		_result_dialog.dialog_text = "Repository non configurato.\nUsa Progetto > Strumenti > GitHub AutoPush: Configura..."
		_result_dialog.popup_centered(Vector2i(600, 250))
		return
	_push_button.disabled = true
	_push_button.text = "Push in corso..."
	# lascio un frame per aggiornare il testo del pulsante
	await get_tree().process_frame
	var res := _do_push()
	_push_button.disabled = false
	_push_button.text = BUTTON_TEXT
	if res.ok:
		_quit_now()
	else:
		_result_dialog.title = "Push fallito - l'editor NON e' stato chiuso"
		_result_dialog.dialog_text = res.message
		_result_dialog.popup_centered(Vector2i(650, 350))


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

	# se il remoto ha gia' commit (es. README iniziale) li unisco prima del push
	var fetch := _git(PackedStringArray(["fetch", "origin", branch]))
	if fetch.code == 0:
		var pull := _git(PackedStringArray(["pull", "origin", branch, "--allow-unrelated-histories", "--no-edit", "--no-rebase"]))
		if pull.code != 0:
			return {"ok": false, "message": "git pull fallito (probabile conflitto):\n" + pull.out + "\n\nRisolvi il conflitto da terminale nella cartella del progetto, poi riprova."}

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

func _build_push_button() -> void:
	_push_button = Button.new()
	_push_button.text = BUTTON_TEXT
	_push_button.tooltip_text = "Carica il progetto su GitHub (add, commit, push) e poi chiude Godot"
	_push_button.flat = false
	_push_button.pressed.connect(_on_push_and_close_pressed)
	# lo metto nella barra in alto dell editor, accanto ai pulsanti Play/Pausa
	
	add_control_to_container(CONTAINER_TOOLBAR, _push_button)


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
	_settings_dialog.popup_centered()


func _on_settings_saved() -> void:
	repo_url = _repo_edit.text.strip_edges()
	branch = _branch_edit.text.strip_edges()
	if branch == "":
		branch = "main"
	commit_message = _msg_edit.text
	_save_settings()


# ---------------------------------------------------------------- settings --

func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		repo_url = cfg.get_value("github", "repo_url", "")
		branch = cfg.get_value("github", "branch", "main")
		commit_message = cfg.get_value("github", "commit_message", "Auto-commit da Godot")


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("github", "repo_url", repo_url)
	cfg.set_value("github", "branch", branch)
	cfg.set_value("github", "commit_message", commit_message)
	cfg.save(SETTINGS_PATH)
