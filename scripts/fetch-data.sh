#!/bin/sh
# Fetch test fixtures: tokenizer, the smallest tinystories checkpoint, and
# karpathy's reference run.c so we can diff full-generation output.
set -eu

HERE=$(cd "$(dirname "$0")/.." && pwd)
DATA="$HERE/data"
REF="$HERE/tests/reference"

mkdir -p "$DATA" "$REF"

if [ ! -f "$DATA/tokenizer.bin" ]; then
        echo "fetching tokenizer.bin"
        wget -q -O "$DATA/tokenizer.bin" \
                https://github.com/karpathy/llama2.c/raw/master/tokenizer.bin
fi

if [ ! -f "$DATA/stories15M.bin" ]; then
        echo "fetching stories15M.bin (~60MB)"
        wget -q -O "$DATA/stories15M.bin" \
                https://huggingface.co/karpathy/tinyllamas/resolve/main/stories15M.bin
fi

if [ ! -f "$REF/karpathy_run.c" ]; then
        echo "fetching karpathy run.c"
        wget -q -O "$REF/karpathy_run.c" \
                https://raw.githubusercontent.com/karpathy/llama2.c/master/run.c
fi

if [ ! -x "$REF/karpathy_run" ]; then
        echo "building karpathy_run reference"
        cc -O2 -o "$REF/karpathy_run" "$REF/karpathy_run.c" -lm
fi
