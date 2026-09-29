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

