---
options:
  end_slide_shorthand: true
  h1_slide_titles: true
  incremental_lists: false
theme:
  name: catppuccin-mocha
  override:
    default:
      margin:
        percent: 2
    slide_title:
      alignment: left
      padding_top: 0
      padding_bottom: 0
      font_size: 1
      bold: true
    code:
      alignment: left
      padding:
        horizontal: 1
        vertical: 0
    table:
      alignment: left
    footer:
      style: template
      left: "Understanding Lake"
      right: "{current_slide} / {total_slides}"
---

<!-- alignment: center -->

# Understanding Lake

(slides at https://github.com/mpenciak/lean_build_talk)

---

# 2. Outline

1. What Lean builds
2. Lake targets, facets, and queries
3. Rebuilding and the module system
4. Distributing artifacts with `lake pack`
5. Sharing artifacts with `lake cache`

Goal: reuse builds across VeriLib runners.

---

# 3. What does Lean build?

```text
Foo.lean
   │ parse + elaborate
   ▼
Declarations + proof terms
   │ kernel checks
   ▼
Environment
   │ lean -o Foo.olean
   ▼
Foo.olean
```

- Elaborate terms and tactics.
- Save module data for later imports.

---

# 4. Inside an `.olean`

```lean
structure ModuleData where
  isModule        : Bool
  imports         : Array Import
  constNames      : Array Name
  constants       : Array ConstantInfo
  extraConstNames : Array Name
  entries         :
    Array (Name × Array EnvExtensionEntry)
```

- Types, bodies, and proof terms.
- Extensions: notation, simp registrations.
- This module's contributions only.
- Imports refer to other modules.

---

# 5. Build dependencies first

```text
Bar.lean → Bar.olean
               │ import
               ▼
           Foo.lean
               │ lean
               ▼
           Foo.olean
```

- `Foo` imports `Bar`: build `Bar` first.
- Restore declarations and extension data.
- `mmap` loads `.olean` data by offset.

---

# 6. Module names are paths

```text
import Baz.Basic
       │ search LEAN_PATH
       ▼
<root>/Baz/Basic.olean
```

- `lean -R` sets the source root.
- Module names follow source paths.
- `LEAN_PATH` lists roots to search.

---

# 7. Choose a build target

Choose a target for `lake build`:

| Target | Builds |
| --- | --- |
| (none) | Default `targets` |
| `@LakeTargets` | Package defaults |
| `LakeTargets` | Library |
| `targets` | Executable (`Main`) |
| `+LakeTargets.Basic` | One module |
| `LakeTargets/Basic.lean` | One module |

- `@package/target` qualifies a target.
- `+` explicitly selects a module.
- Lake also builds everything it needs.

---

# 8. Facets and build artifacts

```sh
lake build +LakeTargets.Basic:olean
```

| Facet | Result |
| --- | --- |
| `:leanArts` | `.olean`, `.ilean`, `.c` |
| `:olean` / `:ilean` | Import / editor data |
| `:c` / `:o` | C / native object |
| `:static` / `:shared` | Archive / shared lib |

```text
.lake/
├─ build/
│  ├─ lib/lean/  .olean, .ilean
│  ├─ ir/        .c, .o
│  └─ bin/       executables
└─ packages/    dependencies
```

Default: `:leanArts`. One Lean step emits
`.olean`, `.ilean`, and `.c`.

---

# 9. Query build results

```sh
lake query +LakeTargets.Basic:olean
lake query --json \
  +Main:imports +Main:transImports
```

For `+Main`:

| Facet | Result |
| --- | --- |
| `:imports` | Direct workspace imports |
| `:transImports` | Transitive imports |
| `:deps` | Build dependencies |

- `LakeTargets:modules`: library modules.
- `@LakeTargets:deps`: package dependencies.
- Results: stdout. Build logs: stderr.
- Import queries only read headers.
- `+Main:deps` leaves `Main` unbuilt.

---

# 10. Rebuild what depends on a change

```text
Base ──▶ Middle ──┐
  └────▶ Other ───┴──▶ LakeRebuild
```

| Change | Rebuilt |
| --- | --- |
| Nothing | Nothing |
| `Middle.lean` | Middle + root |
| `Base.lean` | All four |

- Traces hash sources and dependencies.
- Recheck importers of changed definitions.

---

# 11. The module system

```lean
-- ModuleSystem/Number.lean
module
public def number : Nat := 10
```

```lean
-- ModuleSystem.lean
module
import ModuleSystem.Number
public def nextNumber : Nat := number + 1
```

- Public name/type; body hidden by default.
- `10` → `20`: only Number rebuilds.
- Public `.olean` unchanged: reuse importer.

---

# 12. Pack a prebuilt library

```sh
lake build
lake pack
```

- Archive existing outputs; no build/upload.
- Aeneas CI uploads to a GitHub release.

```lean
package «aeneas» where
  preferReleaseBuild := true
  buildArchive :=
    s!"lean-build-aeneas-" ++
    s!"{System.Platform.target}.tar.gz"
```

Aeneas: `backends/lean/lakefile.lean:8–10`

<!--
Aeneas lakefile source (archive expression wrapped):
https://github.com/AeneasVerif/aeneas/blob/6e167c9b63a4dafd66d0e0edd9d94669f957ff7b/backends/lean/lakefile.lean#L8-L10
-->

```sh
lake build --no-ansi
```

Download and unpack; reuse Aeneas's build.

---

# 13. Reuse a cached version

```toml
enableArtifactCache = true
restoreAllArtifacts = true
```

Edit `LocalCache/Value.lean`, then build:

| Value | Result |
| --- | --- |
| `10` | Build both modules |
| `20` | Build both modules |
| `10` again | Reuse both modules |

- Matching inputs reuse cached artifacts.
- `.lake/cache`: artifacts + JSON mappings.
- `lake clean` clears outputs, not the cache.
- `lake cache clean` clears the cache.

---

# 14. Share a remote cache

```text
Runner A
   │ lake cache put
   ▼
S3-compatible cache
   │ lake cache get
   ▼
Runner B
```

- Artifacts + input/output mappings.
- `get`: current or earlier commits.
- `build`: reuse matching artifacts.
- Rebuild anything affected by edits.

---

# 15. VeriLib: reuse previous builds

All runners share one remote cache,
with artifact caching enabled.

```sh
lake cache get --repo OWNER/PROJECT
lake build --no-ansi -o outputs.jsonl
lake cache put outputs.jsonl \
  --repo OWNER/PROJECT
```

Upload key from runner secrets:

```sh
export LAKE_CACHE_KEY="ACCESS_KEY:SECRET_KEY"
```

- `-o`: mappings for upload.
- `--repo`: repository/toolchain/platform.
- Miss? Build normally; upload on success.
- Keep Git history for earlier cache entries.
