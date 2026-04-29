#!/bin/sh
# Compile all Limbo sources to .dis files, ready to run under emu.
#
# Inferno's mk build system expects to operate on its own source tree, so we
# bypass it: we invoke the limbo compiler directly with the right -I path,
# install the .dis files into $INFERNO/dis, and place the module
# declaration where any future build can find it.
set -eu

: "${INFERNO:=/inferno}"
HERE=$(cd "$(dirname "$0")/.." && pwd)

# install module declaration so other Limbo code can include "llama.m"
install -m 0644 "$HERE/module/llama.m" "$INFERNO/module/llama.m"

LIMBO="limbo -gw -I$INFERNO/module"

mkdir -p "$INFERNO/dis/lib" "$INFERNO/dis/llamatests"

echo "compiling library: appl/lib/llama.b"
( cd "$INFERNO/dis/lib" && $LIMBO "$HERE/appl/lib/llama.b" )

echo "compiling cmd: appl/cmd/run.b"
( cd "$INFERNO/dis" && $LIMBO "$HERE/appl/cmd/run.b" )

for t in test_rmsnorm test_softmax test_matmul test_rng test_model_loading; do
        echo "compiling test: $t"
        ( cd "$INFERNO/dis/llamatests" && $LIMBO "$HERE/appl/cmd/llamatests/$t.b" )
done

echo "build complete:"
ls -1 "$INFERNO/dis/lib"/llama.dis "$INFERNO/dis"/run.dis "$INFERNO/dis/llamatests"/*.dis
