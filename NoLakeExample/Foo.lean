import Lean

open Lean

def fooNat : Nat := 5

initialize fakeExt : MapDeclarationExtension Nat ← mkMapDeclarationExtension

#eval fooNat
