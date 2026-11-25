#!/usr/bin/env bash
# Analyse syntaxique (sans compilation) des fichiers de l'app SwiftUI sous Linux / WSL :
# détecte les erreurs de syntaxe avant la CI macOS. Ne vérifie ni les types ni les API iOS.
set -u
here="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="$HOME/swift/usr/bin:$PATH"
[ -d "$HOME/swiftdeps/usr" ] && export LD_LIBRARY_PATH="$HOME/swiftdeps/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
bad=0
for f in "$here"/App/*.swift; do
  out="$(swiftc -parse "$f" 2>&1 | grep -E 'error' | head -5)"
  if [ -n "$out" ]; then echo "== $(basename "$f")"; echo "$out"; bad=1; fi
done
[ "$bad" = 0 ] && echo "Syntaxe : aucun fichier en erreur."
exit "$bad"
