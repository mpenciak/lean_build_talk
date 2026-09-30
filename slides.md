# 1. What does Lean build?

```text
Foo.lean → parse + elaborate → kernel-check declarations
                                  ↓
                              Environment
                                  ↓  lean -o …
                              Foo.olean
```

- Elaboration turns terms and tactics into declarations and proof terms.
- An `.olean` stores module data for later imports.

---

# 2. Inside an `.olean`: `ModuleData`

```lean
structure ModuleData where
  isModule        : Bool
  imports         : Array Import
  constNames      : Array Name
  constants       : Array ConstantInfo
  extraConstNames : Array Name
  entries         : Array (Name × Array EnvExtensionEntry)
```

- Declarations include types, definition bodies, and proof terms.
- Persistent extensions export data such as notation and simp registrations.
- Stores this module's contributions; imports refer to other modules.

---

# 3. Imports require built dependencies

```text
Foo.lean  ← imports —  Bar.lean
   ↓                     ↓
Foo.olean             Bar.olean
```

- If `Foo` imports `Bar`, then we need to build `Bar` before `Foo`
- An import restores declarations and persistent extension data.
- Basically we `mmap` (with offsets) the content of the `olean`

---

# 4. Module names are paths

```text
import Baz.Basic
        ↓
$LEAN_PATH entry / Baz / Basic.olean
```

- `lean -R` sets the source root used to calculate the current module's name.
- `LEAN_PATH` supplies roots for finding imported artifacts.

---

# 5. What does `lake build` build?

| Command | Selection in this project |
| --- | --- |
| `lake build` | `defaultTargets = ["targets"]` |
| `lake build @LakeTargets` | Package `LakeTargets`'s default targets |
| `lake build LakeTargets` | Library `LakeTargets` |
| `lake build targets` | Executable `targets` (root module `Main`) |
| `lake build +LakeTargets.Basic` | Module `LakeTargets.Basic` |
| `lake build LakeTargets/Basic.lean` | Module `LakeTargets.Basic` |

- A package contains configured targets; a library selects Lean modules.
- `@package/target` qualifies a target; `+` explicitly selects a module.
- Lake builds the selected target and everything it needs.

---

# 6. Facets: which result do we want?

```sh
lake build @LakeTargets/+LakeTargets.Basic:olean
```

| Facet | Result |
| --- | --- |
| `:leanArts` | `.olean`, `.ilean`, `.c` (module/library default) |
| `:olean` / `:ilean` | Import data / editor metadata |
| `:c` / `:o` | Generated C / native object code |
| `:static` / `:shared` | Library archive / shared library |

```text
.lake/build/lib/lean/   .olean, .ilean
.lake/build/ir/         .c, native objects
.lake/build/bin/        executables
.lake/packages/        fetched dependency packages
```

Selecting `:olean` can also produce `.ilean` and `.c`: they share a build step.

---

# 7. `lake query`: build and print the result

```sh
lake query +LakeTargets.Basic:olean
lake query --json +Main:imports +Main:transImports
```

| Facet | Result |
| --- | --- |
| `+Main:imports` | Direct workspace imports: `["LakeTargets"]` |
| `+Main:transImports` | Transitive workspace imports: `["LakeTargets.Basic", "LakeTargets"]` |
| `LakeTargets:modules` | Modules selected by the library |
| `@LakeTargets:deps` | Direct package dependencies |

- Results go to stdout; build progress goes to stderr.
- Import queries read headers without compiling the modules.
- `lake build +Main:deps` builds its dependencies, leaving `Main` unbuilt.

---

# 8. Lake rebuilds what depends on a change

```text
Base ──→ Middle ──┐
  └────→ Other ───┴──→ LakeRebuild
```

| Change | Modules rebuilt |
| --- | --- |
| Nothing | None |
| `Middle.lean` | `LakeRebuild.Middle`, `LakeRebuild` |
| `Base.lean` | All four |

- Lake records hashes of sources and dependencies in build traces.
- Importers must be checked against the changed definitions.

---

# 9. The module system hides implementation details

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

- `public` makes the name and type available; the body is hidden by default.
- Change `10` to `20`: only `ModuleSystem.Number` rebuilds.
- Its public `.olean` stays the same, so the importer is reused.

---

# 10. `lake pack`: distribute a prebuilt library

```sh
lake build
lake pack
```

- `lake pack` archives the existing build directory; it does not build or upload.
- Aeneas CI uploads that archive to a GitHub release for the same commit.
- Downstream projects download and unpack it to reuse Aeneas's build artifacts.

```lean
package «aeneas» where
  preferReleaseBuild := true
  buildArchive := s!"lean-build-aeneas-{System.Platform.target}.tar.gz"
```

[Aeneas lakefile, lines 8–10](https://github.com/AeneasVerif/aeneas/blob/6e167c9b63a4dafd66d0e0edd9d94669f957ff7b/backends/lean/lakefile.lean#L8-L10)

```sh
lake build --no-ansi
```

---

# 11. Local cache: reuse a previously built version

```toml
# lakefile.toml
enableArtifactCache = true
restoreAllArtifacts = true
```

| Edit `LocalCache/Value.lean`, then build | Result |
| --- | --- |
| `value := 10` | Both modules built and cached |
| `value := 20` | Both modules built and cached |
| Back to `value := 10` | Both modules reused from cache |

- Matching inputs reuse earlier artifacts, even after `lake clean`.
- `.lake/cache` stores the artifacts and JSON mappings for earlier builds.
- `lake cache clean` clears the cache; `lake clean` clears build outputs.

---

# 12. Remote cache: share build results between runners

```text
Runner A ── lake cache put ──▶ S3-compatible cache
Runner B ◀─ lake cache get ─── S3-compatible cache
```

- Store build artifacts and mappings from input hashes to outputs.
- `get` looks for the current commit, then earlier commits if needed.
- `build` reuses matching artifacts and rebuilds anything affected by changes.
- A fresh runner can reuse results from a previous runner.

---

# 13. VeriLib: download → build → upload

Configure every runner to use the same remote cache, with artifact caching enabled.

The runner's secret configuration supplies upload credentials as an environment variable:

```sh
export LAKE_CACHE_KEY="ACCESS_KEY:SECRET_KEY"
```

```sh
lake cache get --repo OWNER/PROJECT
lake build --no-ansi -o outputs.jsonl
lake cache put outputs.jsonl --repo OWNER/PROJECT
```

- `-o` exports the mappings that `put` needs to upload.
- `--repo` scopes the cache by repository, with toolchain/platform information.
- Cache miss? Build normally. Upload after a successful build.
- Keep Git history so later requests can find cached earlier commits.
