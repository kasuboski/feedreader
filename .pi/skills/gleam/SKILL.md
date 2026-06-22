---
name: gleam
description: Gleam essentials that prevent the highest-frequency compile errors when writing Gleam from Elixir/other-language intuition — Result vs Option, case guards, custom-type matching, type/function syntax, and the CLI. Use before writing or editing any .gleam file, or when gleam check/format fails.
---

# Gleam: The Errors You Will Make

Gleam's syntax and type rules differ from Elixir, ML, and other languages in a few
specific ways that produce repeating compile errors. Every ❌ below is a real compile
error. Apply these rules before running `gleam check`.

## 1. `Result`, not `Option` — the #1 time sink

Gleam has **no `Option` in the prelude.** `Option`/`Some`/`None` only exist after
`import gleam/option`, and the language convention is: *fallible functions return
`Result`; use `Nil` as the error when there is no detail.* So stdlib lookups return
**`Result(a, Nil)`**, never `Option`:

```gleam
// ❌ "Option is not defined or imported" / "Type mismatch"
fn child(node) -> Option(String) { ... }
let x = list.first(my_list)          // this is Result(a, Nil)
let y = list.first(my_list) |> result.unwrap(None)   // None is Option — mismatch

// ✅ Use Result(a, Nil) everywhere a value may be absent
fn child(node) -> Result(String, Nil) { ... }
let assert Ok(first) = list.first(my_list)           // or:
let first = list.first(my_list) |> result.unwrap("default")   // default is a String
```

- `list.first`, `list.find`, `list.key_find`, `dict.get`, `map.get` → all `Result(_, Nil)`.
- **`result.to_option` does not exist.** Don't mix `result.unwrap` with a `Some`/`None` default.
- `Option` is appropriate *only* for optional **function arguments** or **stored struct fields** — and then it must be `import gleam/option` → `option.Option`, `option.Some`, `option.None`.
- When unsure about any stdlib/deps signature, run `gleam-sig <module> <fn>` (see below) — don't guess.

## 2. No function calls in `case` guards — it's a syntax error

Guards only allow literals, comparisons (`== != < > <= >=`), `&&`, `||`, and `!`.
**Calling a function is a hard `error: Syntax error … Unsupported expression / Functions cannot be called in clause guards.`**

```gleam
// ❌ Syntax error
case path {
  s if string.ends_with(s, "/") -> "unread"
  _ -> "other"
}
case list {
  [first, ..rest] if is_day_name(first) -> string.join(rest, " ")
  _ -> "?"
}

// ✅ Do the check in the body, or bind a bool first
case path {
  s -> case string.ends_with(s, "/") {
    True -> "unread"
    False -> "other"
  }
}
// guards that ARE fine: only operators + literals
case n { x if x > 0 && x < 10 -> "small"  _ -> "big" }
```

## 3. Custom-type matching needs all fields — or labels

Pattern-matching a variant by a single field fails unless the variant was
**defined with labels**. Positional definitions must be matched positionally.

```gleam
// ❌ "Incorrect arity" / "Unexpected labelled argument"  (variant defined positionally)
pub type Node { Element(String, List(Attr), List(Node))  Text(String) }
case n { Element(children:) -> children  _ -> [] }

// ✅ Option A — label the definition, then partial label-match is allowed
pub type Node { Element(tag:, attrs:, children:)  Text(content:) }
case n { Element(children:) -> children  _ -> [] }
// ✅ Option B — keep positional, match positionally with _ for ignored fields
case n { Element(_, _, children) -> children  _ -> [] }
```

## 4. Type & identifier syntax — not Elixir, not Erlang

| ❌ | ✅ | Why |
|---|---|---|
| `fn int.to_string(n) { }` | `fn int_to_string(n) { }` | No `.` in a function name (and don't shadow stdlib names) |
| `e: my_error()` | `e: my_error` | Parens after a type = a function type. Custom types have no parens |
| `-> my/dir/mod.Type` | `import my/dir/mod` → `mod.Type` | Never write a full module path inline; import then alias |
| `fn _unused() { }` | `fn unused() { }` | Top-level fn names can't start with `_` |
| `%% a comment` | `// a comment` | `%%` is Elixir/Erlang; Gleam is `//` |

## 5. The CLI — what actually exists (Gleam 1.x)

```text
gleam new NAME --template {erlang|javascript}   # NOT 'lib'. Default = erlang
gleam add PKG              gleam add --dev PKG
gleam check                # type-check only — FAST, use this in the loop
gleam build                # full build (slower)
gleam format               # idempotent; run it, it won't break working code
gleam test                 # no --verbose flag exists
gleam run  /  gleam run -m my_mod
gleam fix                  # rewrites deprecated code automatically — try it first
gleam deps / deps tree     # NOT 'deps versions', 'search', 'fetch', or 'list'
```

- **Project names can't start with `_`** (`gleam new _x` → "Please try again with a different project name").
- To find a package's real exported API, read its source under `build/packages/<pkg>/src/` — or use `gleam-sig`.

## 6. Tight edit→check loop

Don't write a whole module then iterate one error at a time.

1. After **each** file write/edit, run `gleam check` (fast, no artefacts).
2. Read **all** reported errors at once; fix them in one edit pass; re-check.
3. Run `gleam format` separately when done — it's cosmetic and idempotent.
4. `gleam fix` first when porting old code; it handles deprecations for you.

## 7. Don't guess at library APIs (version drift burns the most)

Package APIs change across versions and many are easy to misremember. Common
examples of things that look plausible but aren't in the installed version:

| Looks plausible (❌) | Reality | How to confirm |
|---|---|---|
| `result.to_option` | does not exist | `gleam-sig gleam/result` |
| `decode.first` / `decode.field(0, str)` (2 args) | `decode.field` takes 3; no `first` | `gleam-sig gleam/dynamic/decode field` |
| `sqlight.decode_string` | does not exist | `gleam-sig sqlight` |
| `simplifile.bits_to_string` / `.UTF8` | renamed/removed | `gleam-sig simplifile` |
| `mist.start_http` | it's `mist.serve` / `start` | `gleam-sig mist` |
| `io.debug` | not present on every version | `gleam-sig gleam/io` |

### `gleam-sig` helper (this skill's `scripts/gleam-sig`)

Prints the **real** signatures from the Gleam source actually installed in
`build/packages/` (falls back to any stdlib on disk). Put it on `PATH`.

```bash
gleam-sig gleam/list first        # -> pub fn first(list) -> Result(a, Nil)
gleam-sig gleam/dict get
gleam-sig gleam/option            # see exactly what Option API exists
gleam-sig sqlight                 # a dependency module
gleam-sig gleam/dynamic/decode field
```

Rule of thumb: **before calling any function you didn't write in the last 5 minutes,
`gleam-sig` it.** It costs one command and removes a whole class of "Unknown module
value / Incorrect arity" round-trips.

## 8. Flatten nested code — `use`, `result.try`, `list.find_map`

Nested `case` on `Result` produces a pyramid that gets one indent wider per step.
Gleam's `use` keyword lets you write each fallible step at the **same** indent level,
like an early return. This is the single biggest readability win in the language.

### Result chain → `use <- result.try`

```gleam
// ❌ Pyramid: 3 nested case arms, one indent level per step
fn process(url) {
  case fetch(url) {
    Ok(body) -> case parse(body) {
      Ok(data) -> case store(data) {
        Ok(_) -> Ok("done")
        Error(e) -> Error(e)
      }
      Error(e) -> Error(e)
    }
    Error(e) -> Error(e)
  }
}

// ✅ Flat: each step is one line, errors short-circuit automatically
fn process(url) {
  use body <- result.try(fetch(url))
  use data <- result.try(parse(body))
  use _ <- result.try(store(data))
  Ok("done")
}
```

**The error type must unify across the whole chain.** If step 1 returns
`Result(String, String)` but step 2 returns `Result(String, FileError)`, the
chain won't type-check. Wrap each step with `result.map_error` to normalize:

```gleam
use content <- result.try(
  simplifile.read(path)
  |> result.map_error(fn(_) { "Failed to read file" }),
)
```

To convert `Option` into `Result` for a `use` chain, use `option.to_result`;
to convert the chain's final `Result` back to `Option`, use `option.from_result`.

### "Try parsers in order" → `list.find_map`

When you have a sequence of fallback attempts (parse ISO → parse RFC → parse
custom), don't nest 3+ `case` levels. Put the parsers in a list and let
`find_map` short-circuit on the first success:

```gleam
// ❌ 3-deep nested case, each arm repeating the same Ok/Error mapping
fn parse(raw) {
  case parser_a(raw) {
    Ok(v) -> Some(format(v))
    Error(_) -> case parser_b(raw) {
      Ok(v) -> Some(format(v))
      Error(_) -> case parser_c(raw) {
        Ok(v) -> Some(format(v))
        Error(_) -> None
      }
    }
  }
}

// ✅ Flat pipeline: list of parsers, find_map short-circuits
fn parse(raw) {
  [parser_a, parser_b, parser_c]
  |> list.find_map(fn(p) { p(raw) })
  |> result.map(format)
  |> option.from_result
}
```

`list.find_map` returns `Result(b, Nil)` (not `Option`) in current Gleam — pipe
through `option.from_result` if you need an `Option`.

### Early-return on a precondition → `bool.guard`

```gleam
// ❌ Wraps the entire happy path in a case
fn handle(input) {
  case input == "" {
    True -> "error"
    False -> { /* ...the real logic, indented... */ }
  }
}

// ✅ Guard clause: bail early, keep the happy path at base indent
fn handle(input) {
  use <- bool.guard(when: input == "", return: "error")
  /* ...the real logic, flat... */
}
```

`bool.lazy_guard` is the same but takes a `fn()` for the return value (use when
the return expression is expensive to compute).

### `let _ = list.map(...)` is a code smell

```gleam
// ❌ Constructs a list of results, then throws it away. Misleading intent.
let _ = list.map(items, fn(item) { side_effect(item) })

// ✅ Explicitly says "run for side effects, discard results"
list.each(items, fn(item) { side_effect(item) })
```

If you see `let _ = list.map(...)` and the function's return value isn't used,
replace it with `list.each`.

---

## Quick pre-flight checklist before `gleam check`

- [ ] No bare `Option`/`Some`/`None` without `import gleam/option` (prefer `Result(_, Nil)`)
- [ ] No function calls in `case` guards
- [ ] Custom-type patterns match all fields (positional `_` or labeled definition)
- [ ] No `.` in fn names, no `()` after type names, no inline `dir/module.Type`
- [ ] Comments are `//`, not `%%` or `#`
- [ ] Ran `gleam-sig` on any stdlib/deps function whose signature you're unsure of
- [ ] No `case`-on-`Result` pyramids — use `use <- result.try` to flatten
- [ ] No `let _ = list.map(...)` — use `list.each` for side effects
