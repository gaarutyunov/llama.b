CC      ?= cc
CFLAGS  ?= -O2 -Wall -Wextra
LDLIBS  := -lm

REFS    := ref_rmsnorm ref_softmax ref_matmul ref_rng ref_model_loading

all: $(REFS)

$(REFS): %: %.c
	$(CC) $(CFLAGS) $< -o $@ $(LDLIBS)

clean:
	rm -f $(REFS)

.PHONY: all clean
