Llama: module
{
	PATH:	con "/dis/lib/llama.dis";

	# initialise the module: must load Sys, Math.
	init:	fn(): int;

	# ------------------------------------------------------------------
	# data layout
	# ------------------------------------------------------------------
	Config: adt {
		dim:		int;
		hidden_dim:	int;
		n_layers:	int;
		n_heads:	int;
		n_kv_heads:	int;
		vocab_size:	int;
		seq_len:	int;
	};

	Weights: adt {
		# pointers (offsets) into the flat weights buffer
		token_embedding:	array of real;
		rms_att_weight:		array of real;
		rms_ffn_weight:		array of real;
		wq:			array of real;
		wk:			array of real;
		wv:			array of real;
		wo:			array of real;
		w1:			array of real;
		w2:			array of real;
		w3:			array of real;
		rms_final_weight:	array of real;
		wcls:			array of real;
	};

	State: adt {
		x:		array of real;
		xb:		array of real;
		xb2:		array of real;
		hb:		array of real;
		hb2:		array of real;
		q:		array of real;
		att:		array of real;
		logits:		array of real;
		key_cache:	array of real;
		value_cache:	array of real;
	};

	Transformer: adt {
		config:	Config;
		w:	Weights;
		s:	State;

		forward:	fn(t: self ref Transformer, token, pos: int): array of real;
	};

	# load a karpathy-format llama2.c checkpoint
	build_transformer:	fn(path: string): (ref Transformer, string);

	# ------------------------------------------------------------------
	# tokenizer
	#
	# vocab entries are stored as raw `array of byte` rather than Limbo
	# `string` because the llama tokenizer contains byte-fallback entries
	# that aren't valid UTF-8 (e.g. lone 0xC0).  Converting those bytes
	# through string would collapse them all to U+FFFD and break lookup.
	# ------------------------------------------------------------------
	TokenIndex: adt {
		s:	array of byte;
		id:	int;
	};

	Tokenizer: adt {
		vocab:			array of array of byte;
		vocab_scores:		array of real;
		sorted_vocab:		array of TokenIndex;
		vocab_size:		int;
		max_token_length:	int;

		encode:	fn(t: self ref Tokenizer, text: string, bos, eos: int): array of int;
		decode:	fn(t: self ref Tokenizer, prev_token, token: int): array of byte;
	};

	build_tokenizer:	fn(path: string, vocab_size: int): (ref Tokenizer, string);

	# ------------------------------------------------------------------
	# sampler
	# ------------------------------------------------------------------
	ProbIndex: adt {
		prob:	real;
		index:	int;
	};

	Sampler: adt {
		vocab_size:	int;
		probindex:	array of ProbIndex;
		temperature:	real;
		topp:		real;
		rng_state:	big;

		sample:	fn(s: self ref Sampler, logits: array of real): int;
	};

	build_sampler:	fn(vocab_size: int, temperature, topp: real, rng_seed: big): ref Sampler;

	# ------------------------------------------------------------------
	# math primitives (exposed for component tests)
	# ------------------------------------------------------------------
	rmsnorm:	fn(o, x, weight: array of real, size: int);
	softmax:	fn(x: array of real, off, size: int);
	matmul:		fn(xout, x, w: array of real, woff, n, d: int);

	# RNG: pure-functional xorshift64*; both functions return the new state
	# alongside the produced value.
	random_u32:	fn(state: big): (big, int);
	random_f32:	fn(state: big): (big, real);

	sample_argmax:	fn(p: array of real, n: int): int;
	sample_mult:	fn(p: array of real, n: int, coin: real): int;

	# ------------------------------------------------------------------
	# generation driver
	# ------------------------------------------------------------------
	generate:	fn(t: ref Transformer, tk: ref Tokenizer, sa: ref Sampler,
				prompt: string, steps: int);
};
