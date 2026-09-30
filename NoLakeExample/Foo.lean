import Lean

open Lean

def fooNat : Nat := 5

initialize fooExt : MapDeclarationExtension Nat ← mkMapDeclarationExtension

#eval fooNat
