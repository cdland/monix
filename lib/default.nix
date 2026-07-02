# Extends nixpkgs' lib with the helpers defined in this directory. The overlay
# must return a literal attrset and must not call lib functions to compute its
# attribute names: nixpkgs' lib submodules dereference the fixpoint while they
# are forced, so a computed overlay (listFilesRecursive + foldl' recursiveUpdate)
# is infinite recursion. Add new helper files here explicitly.
lib:
lib.extend (
  final: prev: {
    systems = prev.systems // (import ./systems.nix { self = final; }).systems;
  }
)
