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

`SAVE_VERSION` is bumped in lockstep with any change to the data shape that load can't decode. Old saves hard-fail with `OS.alert` — no migration code. Document the bump in the comment block at the top of `save_system.gd`.

## Tick determinism

- Iterate `grid_world.buildings` directly when ticking — Dictionary iteration in Godot 4 is insertion-ordered, which is the determinism we rely on.
- No unseeded randomness in simulation logic. If we need RNG later, seed it explicitly and store the seed in the save.
- Two-pass tick (Belt) lives in `Buildings.tick_one` / `post_tick_one`. Don't add hidden cross-building reads inside Pass 1.
