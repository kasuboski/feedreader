# Status

## Current Goal
Fix deeply nested code in the real codebase, then distill the learnings into the `gleam` skill.

## Steps & Progress
- [x] Survey the codebase for nesting depth (max-indent scan across all `src/**/*.gleam`)
- [x] Identify concrete pyramids of doom: `router.gleam` import_opml_handler (11 levels), `fetcher.gleam` do_process (8 levels), `date.gleam` parse_date (7 levels)
- [x] Verify stdlib APIs against Gleam 1.16.0: `bool.guard`, `bool.lazy_guard`, `result.try`, `result.try_recover`, `option.from_result`, `option.to_result`, `option.then`, `list.find_map` (returns `Result(b, Nil)`)
- [x] Compile-test the refactoring idioms in a scratch project — all confirmed working
- [x] **Fix `date.gleam::parse_date`**: 4-deep "try parsers in order" chain → flat list + `list.find_map` pipeline (14→4 spaces max indent)
- [x] **Fix `fetcher.gleam::do_process`**: 3-deep nested case → flat `use <- result.try` chain + single error handler (16→10 spaces)
- [x] **Fix `router.gleam::import_opml_handler`**: 4-deep nested case → flat `result.try` chain, `let _ = list.map` → `list.each` (22→12 spaces)
- [x] Full test suite passes: **82 tests, 0 failures** (behavior preserved)
- [x] Write "Flattening nested code" section (#8) into `SKILL.md` with 4 before/after patterns
- [x] Add nesting-related items to the pre-flight checklist
- [x] Verify skill has no session-specific references (grep clean)

## Unknowns
- (none)

## Discovered Issues
- **Error-type unification is the gotcha with `use <- result.try` chains.** Each step must share the same error type. `simplifile.read` returns `Result(String, FileError)` — it won't chain with `Result(_, String)` unless wrapped in `result.map_error`. This was the main hurdle during the router refactor.
- **`list.find_map` returns `Result(b, Nil)`, not `Option`**, in current Gleam — pipe through `option.from_result` if you need Option. This differs from older versions.
- **`let _ = list.map(xs, fn(x) { side_effect(x) })`** is a recurring anti-pattern — it constructs and discards a list. `list.each` is the correct idiom.
- `db.gleam::toggle_read`/`toggle_starred` still have mild duplication (`Ok(Some(_))` pattern + identical inner block) but aren't deeply nested — left alone to avoid scope creep.
- `wisp.FormData` is the form type (not `wisp.Form`); `option.to_result` is the Option→Result bridge (not `result.from_option`, which doesn't exist).
