# llama.b — Llama-2 inference in Limbo

A minimal port of [karpathy/llama2.c](https://github.com/karpathy/llama2.c) to
[Inferno](https://github.com/inferno-os/inferno-os) and the Limbo language.
Companion port to [9ml](https://github.com/gaarutyunov/9ml) (Plan 9 / C); this
repo follows the same module decomposition but skips the SIMD/quantisation
work for now.

## What's in here

```
module/llama.m              # public Limbo module interface
appl/lib/llama.b            # implementation: math primitives, transformer,
                            # tokenizer, sampler, generate()
appl/cmd/run.b              # CLI front-end (mirrors run.c options)
appl/cmd/llamatests/        # one Limbo test per component
tests/reference/            # tiny C reference programs whose output is
                            # diffed against the Limbo output
scripts/build.sh            # invoke `limbo` directly to compile every .b
scripts/run-tests.sh        # boot emu, run each test, diff outputs
scripts/fetch-data.sh       # download tokenizer.bin + stories15M.bin
Dockerfile                  # build Inferno from source (i386 only)
.github/workflows/test.yml  # CI: build the docker image and run tests
```

## Building

The Limbo compiler (`limbo`) and the Inferno emulator (`emu`) ship together;
the easiest way to get them is via the included Dockerfile:

```sh
docker build --platform linux/386 -t llama-inferno .
docker run --rm --platform linux/386 -v "$PWD:/work" -w /work llama-inferno \
    sh -c './scripts/build.sh && ./scripts/run-tests.sh'
```

`scripts/build.sh` calls `limbo` directly with `-I /inferno/module` and
installs the resulting `.dis` files under `/inferno/dis/{,lib,llamatests}/`,
ready to be invoked via `emu -r/inferno`.

## Running a model

```sh
./scripts/fetch-data.sh                 # downloads tokenizer.bin + stories15M.bin
docker run --rm --platform linux/386 -v "$PWD:/work" -w /work llama-inferno \
    sh -c '
        ./scripts/build.sh
        ln -sf /work/data/* /inferno/data/
        emu -r/inferno run /data/stories15M.bin -z /data/tokenizer.bin \
            -i "Once upon a time" -t 0.0 -s 42 -n 64
    '
```

## Testing strategy

We replicate the 9ml approach: every numerical primitive (`rmsnorm`,
`softmax`, `matmul`, RNG) has a Limbo test that prints values and a tiny C
reference that prints the same values; `scripts/run-tests.sh` diffs the
two byte-for-byte. A `model_loading` test verifies the binary checkpoint
parser reads the same fields the C reference does. Finally a full
end-to-end `generation` test runs both the Limbo `run` and karpathy's
original `run.c` with `-t 0.0 -s 42 -n 20` and asserts they emit the same
20 tokens.

If `data/` is empty, only the four primitive tests run; the model-dependent
ones are skipped with a note.

## Notes on the port

* Limbo's `real` is 64-bit IEEE 754. The checkpoint stores 32-bit floats,
  so `read_floats` widens on load using `math->bits32real`.
* There is no native unsigned 64-bit integer; the xorshift64\* RNG is
  emulated on top of Limbo's signed `big` with a logical-shift helper.
* No mmap. The full weights file is read into memory once and unpacked
  into per-tensor `array of real` slices to keep the rest of the code
  free of byte-arithmetic.
* `qsort` and the BPE merge loop are inlined as small recursive
  quicksorts because we don't want to depend on the generic `Sort` module
  which would require extra ADT plumbing.
