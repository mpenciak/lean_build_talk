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
| `lake build` | `defaultTargets = ["example"]` |
| `lake build @Example` | Package `Example`'s default targets |
| `lake build Example` | Library `Example` |
| `lake build example` | Executable `example` (root module `Main`) |
| `lake build +Example.Basic` | Module `Example.Basic` |
| `lake build Example/Basic.lean` | Module `Example.Basic` |

- A package contains configured targets; a library selects Lean modules.
- `@package/target` qualifies a target; `+` explicitly selects a module.
- Lake builds the selected target and everything it needs.

---

# 6. Facets: which result do we want?

```sh
lake build @Example/+Example.Basic:olean
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
lake query +Example.Basic:olean
lake query --json +Main:imports +Main:transImports
```

| Facet | Result |
| --- | --- |
| `+Main:imports` | Direct workspace imports: `["Example"]` |
| `+Main:transImports` | Transitive workspace imports: `["Example.Basic", "Example"]` |
| `Example:modules` | Modules selected by the library |
| `@Example:deps` | Direct package dependencies |

- Results go to stdout; build progress goes to stderr.
- Import queries read headers without compiling the modules.
- `lake build +Main:deps` builds its dependencies, leaving `Main` unbuilt.

---

# 8. Lake rebuilds what depends on a change

```text
Base ──→ Middle ──┐
  └────→ Other ───┴──→ Example2
```

| Change | Modules rebuilt |
| --- | --- |
| Nothing | None |
| `Middle.lean` | `Example2.Middle`, `Example2` |
| `Base.lean` | All four |

- Lake records hashes of sources and dependencies in build traces.
- Importers must be checked against the changed definitions.
