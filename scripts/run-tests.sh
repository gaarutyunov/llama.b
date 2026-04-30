#!/bin/sh
# Run every Limbo unit test under emu and diff its output against a C
# reference implementation.  Exits non-zero on the first mismatch.
#
# Assumes scripts/build.sh has already been run.  Tests requiring
# checkpoint data are skipped if data/ is empty.
set -eu

: "${INFERNO:=/inferno}"
HERE=$(cd "$(dirname "$0")/.." && pwd)
DATA="$HERE/data"
OUT="$HERE/build/tests"
mkdir -p "$OUT"

PASS=0
FAIL=0
SKIP=0

note(){ printf '%s\n' "$*" >&2; }

# --- build the C reference programs --------------------------------------
note "building C reference programs"
make -s -C "$HERE/tests/reference" all

# Make data files visible inside emu by symlinking them under /inferno/data,
# which lives in the namespace the emu process boots into.
mkdir -p "$INFERNO/data"
if [ -d "$DATA" ]; then
        for f in "$DATA"/*; do
                [ -e "$f" ] || continue
                ln -sf "$f" "$INFERNO/data/$(basename "$f")"
        done
fi

emurun(){
        # default heap pool max is 32 MiB, far too small for stories15M
        # (needs ~250 MiB after widening f32 to limbo's f64 reals).
        # Bump it; the small unit tests don't care but the harness uses
        # one helper to keep behaviour uniform.
        emu -r"$INFERNO" -p heap=1024m -p main=1024m "$@"
}

# component test: limbo dis prints values, C reference prints expected
# values, diff -u catches any mismatch.  Always echo emu's stderr so
# diagnostic prints from the .b are visible regardless of pass/fail.
component(){
        name=$1; dis=$2; ref=$3; shift 3
        expected="$OUT/$name.expected"
        actual="$OUT/$name.actual"
        rc=0
        emurun "$dis" "$@" > "$actual" 2>"$OUT/$name.err" || rc=$?
        if [ -s "$OUT/$name.err" ]; then
                note "--- $name stderr ---"
                cat "$OUT/$name.err" >&2
                note "--- end $name stderr ---"
        fi
        if [ $rc -ne 0 ]; then
                note "FAIL $name (emu exit $rc)"
                FAIL=$((FAIL + 1))
                return
        fi
        if [ -n "$ref" ]; then
                "$ref" "$@" > "$expected"
                if diff -u "$expected" "$actual" > "$OUT/$name.diff"; then
                        note "PASS $name"
                        PASS=$((PASS + 1))
                else
                        note "FAIL $name"
                        cat "$OUT/$name.diff" >&2
                        FAIL=$((FAIL + 1))
                fi
        else
                # no reference: just check there is some stdout
                if [ -s "$actual" ]; then
                        note "PASS $name"
                        PASS=$((PASS + 1))
                else
                        note "FAIL $name (no output)"
                        FAIL=$((FAIL + 1))
                fi
        fi
}

# --- diagnostic / progress tests ----------------------------------------
component hello       /dis/llamatests/test_hello.dis       ""
component load_llama  /dis/llamatests/test_load_llama.dis  ""

# --- pure component tests ------------------------------------------------
component rmsnorm /dis/llamatests/test_rmsnorm.dis "$HERE/tests/reference/ref_rmsnorm"
component softmax /dis/llamatests/test_softmax.dis "$HERE/tests/reference/ref_softmax"
component matmul  /dis/llamatests/test_matmul.dis  "$HERE/tests/reference/ref_matmul"
component rng     /dis/llamatests/test_rng.dis     "$HERE/tests/reference/ref_rng"

# --- model-loading test (needs the checkpoint) ---------------------------
if [ -f "$INFERNO/data/stories15M.bin" ]; then
        # Limbo test takes the inferno-namespace path /data/stories15M.bin;
        # the C reference takes the host filesystem path.
        emurun /dis/llamatests/test_model_loading.dis /data/stories15M.bin \
                > "$OUT/model_loading.actual" 2>"$OUT/model_loading.err" || true
        "$HERE/tests/reference/ref_model_loading" \
                "$INFERNO/data/stories15M.bin" > "$OUT/model_loading.expected"
        if diff -u "$OUT/model_loading.expected" "$OUT/model_loading.actual" \
                > "$OUT/model_loading.diff"; then
                note "PASS model_loading"
                PASS=$((PASS + 1))
        else
                note "FAIL model_loading"
                cat "$OUT/model_loading.diff" >&2
                FAIL=$((FAIL + 1))
        fi
else
        note "SKIP model_loading (no $INFERNO/data/stories15M.bin)"
        SKIP=$((SKIP + 1))
fi

# --- end-to-end generation test ------------------------------------------
# Greedy sampling (-t 0.0) is deterministic; karpathy's run.c with the same
# inputs must produce the same first 20 tokens.
if [ -f "$INFERNO/data/stories15M.bin" ] \
   && [ -f "$INFERNO/data/tokenizer.bin" ] \
   && [ -x "$HERE/tests/reference/karpathy_run" ]; then
        emurun /dis/run.dis /data/stories15M.bin -z /data/tokenizer.bin \
                -t 0.0 -s 42 -n 20 > "$OUT/generation.actual.raw" 2>/dev/null \
                || { note "FAIL generation (emu)"; FAIL=$((FAIL + 1)); }
        "$HERE/tests/reference/karpathy_run" "$INFERNO/data/stories15M.bin" \
                -z "$INFERNO/data/tokenizer.bin" -t 0.0 -s 42 -n 20 \
                > "$OUT/generation.expected.raw" 2>/dev/null
        # strip the trailing "achieved tok/s" line which varies; keep only
        # the generated text on the first line.
        head -n 1 "$OUT/generation.actual.raw"   > "$OUT/generation.actual"
        head -n 1 "$OUT/generation.expected.raw" > "$OUT/generation.expected"
        if diff -u "$OUT/generation.expected" "$OUT/generation.actual"; then
                note "PASS generation"
                PASS=$((PASS + 1))
        else
                note "FAIL generation"
                FAIL=$((FAIL + 1))
        fi
else
        note "SKIP generation (need stories15M.bin, tokenizer.bin and karpathy_run)"
        SKIP=$((SKIP + 1))
fi

note ""
note "summary: $PASS passed, $FAIL failed, $SKIP skipped"
[ $FAIL -eq 0 ]
