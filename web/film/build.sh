#!/bin/zsh
# Renders the Whoosh demo film.
#   web/film/build.sh            -> web/film/out/whoosh-demo.mp4 (H.264, 1920x1080, 30 fps)
#   web/film/build.sh --stills 3,20,35   -> PNG stills in web/film/out/stills/
# Needs Node (for the TypeScript engine) and the Xcode command-line tools (swiftc).
set -euo pipefail
cd "${0:A:h}"
mkdir -p build out
node build-engine.mjs build/engine.js
swiftc -O render/*.swift -o build/whoosh-film
if [[ "${1:-}" == "--stills" ]]; then
  ./build/whoosh-film build/engine.js out/stills --stills "$2"
else
  ./build/whoosh-film build/engine.js out/whoosh-demo "$@"
fi
