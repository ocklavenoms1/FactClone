# Stewardship — code conventions

Short rules to keep the codebase consistent as it grows. Update this file when a new convention sticks.

## Naming

### Methods on `class_name`'d types — never use bare reserved names

GDScript classes that extend `RefCounted` or `Node` inherit a long list of method names from `Object`. Defining a static or instance method that shadows one of these causes parse errors that read like "Could not resolve external class member" — confusing and only caught at use-site.

**Forbidden as bare method names:**

```
get   set   has   notification   free   queue_free   connect   disconnect
emit_signal   call   call_deferred   get_class   is_class   to_string
property_get_revert   property_can_revert   property_list   tr   tr_n
duplicate   ready   process   physics_process   input
```

**Always use a domain-prefixed verb instead.** Pattern: `<verb>_<noun>` or `<noun>_<verb>`.

| ❌ | ✅ |
|---|---|
| `Recipes.get(id)` | `Recipes.get_recipe(id)` |
| `Recipes.has(id)` | `Recipes.has_recipe(id)` |
| `Inventory.add(...)` | OK — `add` is not a reserved name on `RefCounted` (it's only on certain Container types). Verify before use. |
| `Belt.connect(a, b)` | `Belt.connect_belts(a, b)` |

When in doubt: prefix. The method-name budget is infinite; debugging time isn't.

### File names match `class_name`

Every file declaring `class_name Foo` must be named `foo.gd` (snake_case). Godot's class registry indexes by `class_name`, but tools, search, and humans index by file path.

### snake_case for everything

GDScript convention: snake_case for variables, functions, file names. PascalCase for classes (`class_name`) and enums. SCREAMING_SNAKE_CASE for constants.

## File layout

```
scripts/
  main.gd                       # entry point, scene root
  player.gd                     # player character
  systems/                      # cross-cutting services (autoloads + helpers)
    tick_system.gd              # autoload: 20Hz simulation tick
    save_system.gd              # static: save/load
  world/                        # simulation domain — buildings, items, world state
    building.gd                 # data struct
    buildings.gd                # registry + dispatch tables
    <name>.gd                   # one file per building type (planter, mill, ...)
    items.gd, item_stack.gd, inventory.gd
    recipes.gd                  # recipe registry
    processor.gd                # generic recipe-driven machine logic
    grid_world.gd               # the world container (terrain + buildings)
    terrain.gd, tile.gd
  ui/                           # HUD elements
    hotbar.gd, inventory_panel.gd, info_panel.gd
  tests/                        # headless tests (added in Session B prep)
    test_runner.gd
    test_<name>.gd
scenes/
  main.tscn                     # main scene
  test_runner.tscn              # headless test harness scene
assets/                         # sprites, audio, fonts (mostly unused while graphics deferred)
```

## Buildings

A new building type takes 9-10 mechanical edits — see the checklist comment at the top of `scripts/world/buildings.gd`. Future processor-class machines (Oven, Press, etc.) reuse `Processor.tick` and shrink to ~30 lines: `make()`, `draw()`, a `Recipes.DATA` entry.

## State storage

Building state is a `Dictionary` round-tripped through JSON via `Building.to_dict / from_dict`. Therefore:

- Store **flat data** only: ints, floats, strings, bools, arrays of those, dicts of those.
- **Never** store an `Inventory`, `Building`, `Node`, or other RefCounted/Object — it silently degrades to a plain Dictionary on load. Use `[[type, count], ...]` arrays for inventory-like data inside building state. Rehydrate to `Inventory` only when slot semantics matter (currently: player inventory only).
- Don't reassign `b.state["key"]` to a new array if other code holds a reference — mutate in place.

### JSON canonicalizes numeric types to float on save

Godot's `JSON.stringify` / `parse_string` has only one number type (float). All ints round-trip as floats: `42` saved → `42.0` loaded. Therefore:

- **Reads with integer semantics MUST use `int(...)`** — e.g. `int(b.state.get("progress", 0))`, not `b.state["progress"]`.
- **Test comparisons must be semantic, not `str()`-based.** `str({"x": 0})` and `str({"x": 0.0})` differ; values are equal. Use a deep-equals helper that coerces numerics.
- Same applies to floats inside arrays/dicts read out of save data.

This is enforced in practice via the existing pattern of `int(b.state.get(...))` reads. Don't break it.

### Forward compatibility within a save version

When adding a new field to an existing building's state, **always read with `.get(key, default)`** so saves predating the field still load cleanly. Direct `b.state["key"]` reads are acceptable only for fields that the building's `make()` always writes — never for fields that may not exist in older saves of the same version.

If you find yourself mixing direct reads and `.get()` reads on the same dict, lean toward `.get()` everywhere — the cost is one extra word; the upside is no surprise crashes when an older save lacks a field your new code expects.

## Save schema

`SAVE_VERSION` is bumped in lockstep with any change to the data shape that load can't decode. Each schema bump must ship with a forward-migration step so existing saves keep working across game updates.

### Schema-bump protocol

When changing the save format:

1. **Bump `SAVE_VERSION`** in `save_system.gd`.
2. **Add a migration log entry** at the top of `save_system.gd` (existing comment block — short paragraph describing the diff).
3. **Write `_migrate_v<N>_to_v<N+1>(data: Dictionary) -> Dictionary`** as a static method on SaveSystem. Add new fields with sensible defaults, transform/restructure as needed, **bump `data["version"]` to N+1 as the last step**.
4. **Register in `MIGRATIONS`** Dict: `MIGRATIONS[N] = "_migrate_v<N>_to_v<N+1>"`.
5. **Add a match-case** in `_dispatch_migration(method_name, data)` that routes to the new function. (GDScript static-method dispatch via `Object.call(name)` doesn't work — match-statement is the foolproof pattern.)
6. **Add at least one test** in `test_save_migration.gd` exercising the new migration's happy path. End-to-end test (write a v(N) save file, call `load_game`, assert state) is high-value.
7. **PROJECT_LOG entry** documenting the schema diff.

### Migration robustness

Migrations run on player-authored data that may have been hand-edited, partially corrupted, or produced by a slightly different game build. Defensive coding pays off:

- **Use `data.get(key, default)`** when reading fields that didn't exist in the prior version. Direct `data[key]` will crash on a hand-truncated save; `.get()` returns the default.
- **Validate types before coercing.** A field that was `Array` in v(N) but `Dict` in v(N+1) is a real migration shape — check `typeof(data[key]) == TYPE_ARRAY` before iterating.
- **Floats round-trip through JSON as floats** (`60.0`, not `60`). When migrating int fields to float (or vice versa), explicit `int()` / `float()` coercion is non-negotiable.
- **Keep migrations small** (≤80 lines each typical). Bigger migrations are usually a smell that the schema change wants to be split into multiple bumps.
- **Migrations are PURE** — no game state mutation, no file I/O, no `print()` (use `push_warning` if needed). Input dict in, mutated/new dict out.

### Failure handling

- Migration returns `null` (or a dict with an unexpected version field) → `_try_migrate` aborts the chain → `load_game` returns `success = false` with a descriptive `error_message`.
- `main.gd`'s post-3.5 hotfix catches this and falls through to fresh-world generation. Player isn't stranded; their save data is genuinely lost in this case.
- Forward incompatibility (save version > SAVE_VERSION, e.g., older binary against newer save) hard-fails with a clear "update the game" message. Backward migration is out of scope.

### Breaking-change reset point: v17

Saves before v17 are NOT preserved. The v14/v15/v16 schema versions exist only as schema-history reference; no production saves at those versions ever existed (the soil arc reversed v15 → v16 region-scoped data, etc.). A v<17 save reaching `_try_migrate` returns `null` (no `MIGRATIONS[14]` etc.), which hard-fails into the fresh-world fallthrough.

If real production players ever exist before further breaks, the cutoff would need to advance. Document explicitly in the migration log.

### Worldgen version is a separate axis

`worldgen_version` (in `world_generator.gd`) is checked AFTER schema migration and stays as hard-fail. Procgen output changing for the same seed cannot be migrated — applying old building positions onto new terrain produces silent corruption (planters on water, etc.). Better to surface the failure and let the post-3.5 hotfix regenerate fresh.

## Tick determinism

- Iterate `grid_world.buildings` directly when ticking — Dictionary iteration in Godot 4 is insertion-ordered, which is the determinism we rely on.
- No unseeded randomness in simulation logic. If we need RNG later, seed it explicitly and store the seed in the save.
- Two-pass tick (Belt) lives in `Buildings.tick_one` / `post_tick_one`. Don't add hidden cross-building reads inside Pass 1.

## Session log discipline

`PROJECT_LOG.md` is a high-level narrative of feature deliveries, one entry per session. Git is the audit trail; the log is a reading aid.

**Scoped sub-sessions and groundwork commits roll up into the parent session's log entry when the parent session ships.** A scoped slice (e.g. "tighten test thresholds before Session E proper") gets its own commit and commit message — that's enough record. The PROJECT_LOG entry for Session E names the groundwork commit hash in its "What shipped" list when it's written, so future readers see the full arc.

Reasoning: tiny per-commit log entries dilute the narrative. A reader scanning PROJECT_LOG should see the shape of each session's feature work, not a per-commit changelog. Solo project; the log is for me, not auditors.

**When in doubt:** if the work is part of a planned session, roll it up. If the work is a one-off cleanup that won't be followed by a session entry, give it its own log entry.
