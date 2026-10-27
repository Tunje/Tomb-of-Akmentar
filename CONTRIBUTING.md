# Before you commit

Simon plays straight from this folder, so a script that doesn't parse breaks his game the
moment it's saved. Run the parse check before every commit (it takes a few seconds):

```
godot --headless --path . res://tests/parse_all.tscn -- --ci
```

It loads every `.gd` and every `.tscn` in the project and prints one `RESULT parse_all FAIL <path>`
line per broken file, then `RESULT parse_all failures=N`. It exits with 1 if anything failed.
Fix your own failures before committing, and tell the owner about anyone else's.

A new `class_name` (yours or someone else's) isn't known until the class cache is refreshed. Until
then, every file that uses it fails with "Identifier ... not declared". So after adding one, or when
failures name a class you can see in the tree, refresh first:

```
godot --headless --path . --import
```

To check that every save resumes (Continue's path), run `tests/resume_test.tscn` once per place.
To check that every set piece can be lost and retried (death, Enter, the same start twice), run
`tests/retry_test.tscn` once per piece (`-- --list` prints each piece's args). Both loops are in
those files' headers. Give each run its own `--save-slot=<name>` so another session's test can't
load or overwrite its save, and delete only your own `<name>.json`, never the shared `test.json`.
If you add a set piece with a death, add it to retry_test's PIECES.

A few habits that keep it green:

- Save edits in an order that compiles at every step: add a new function before its first caller.
- Type loop variables over literal arrays (`for x: float in [1.0, 2.0]:`). An untyped one fed into
  a `:=` declaration is a parse error in this project.
- Run at most one Godot process at a time. Check `tasklist | grep -i godot` first and wait if 5 or
  more are running. Simon's PC takes 6 in all, his game included.
- Always pass at least one argument after `--` to a test scene (`-- --ci` will do), so it saves and
  writes settings to the test slot, never over Simon's own.
- Commit only your own lines. If a file you touched also holds someone else's uncommitted edits,
  stage HEAD plus your changes, not the whole file.
