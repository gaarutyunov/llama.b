implement Run;

include "sys.m";
	sys: Sys;

include "draw.m";

include "llama.m";
	llama: Llama;
	Transformer, Tokenizer, Sampler: import Llama;

Run: module
{
	init: fn(ctxt: ref Draw->Context, argv: list of string);
};

stderr: ref Sys->FD;

usage()
{
	sys->fprint(stderr, "Usage: run <checkpoint> [options]\n");
	sys->fprint(stderr, "Example: run model.bin -n 256 -i \"Once upon a time\"\n");
	sys->fprint(stderr, "Options:\n");
	sys->fprint(stderr, "  -t <float>  temperature in [0,inf], default 1.0\n");
	sys->fprint(stderr, "  -p <float>  top-p (nucleus) sampling in [0,1], default 0.9\n");
	sys->fprint(stderr, "  -s <int>    random seed, default 0 (= now)\n");
	sys->fprint(stderr, "  -n <int>    number of steps, default 256\n");
	sys->fprint(stderr, "  -i <string> input prompt\n");
	sys->fprint(stderr, "  -z <string> path to tokenizer (default tokenizer.bin)\n");
	raise "fail:usage";
}

init(nil: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);

	llama = load Llama Llama->PATH;
	if(llama == nil){
		sys->fprint(stderr, "cannot load %s: %r\n", Llama->PATH);
		raise "fail:load";
	}
	if(llama->init() < 0){
		sys->fprint(stderr, "llama init failed\n");
		raise "fail:init";
	}

	checkpoint := "";
	tokenizer_path := "tokenizer.bin";
	temperature := 1.0;
	topp := 0.9;
	steps := 256;
	prompt := "";
	rng_seed := big 0;

	argv = tl argv;
	if(argv == nil)
		usage();
	checkpoint = hd argv;
	argv = tl argv;
	while(argv != nil){
		flag := hd argv;
		argv = tl argv;
		if(argv == nil)
			usage();
		val := hd argv;
		argv = tl argv;
		case flag {
			"-t" =>	temperature = real val;
			"-p" =>	topp = real val;
			"-s" =>	rng_seed = big val;
			"-n" =>	steps = int val;
			"-i" =>	prompt = val;
			"-z" =>	tokenizer_path = val;
			* =>	usage();
		}
	}
	if(rng_seed == big 0)
		rng_seed = big sys->millisec();
	if(temperature < 0.0)
		temperature = 0.0;
	if(topp < 0.0 || topp > 1.0)
		topp = 0.9;

	(t, terr) := llama->build_transformer(checkpoint);
	if(t == nil){
		sys->fprint(stderr, "build_transformer: %s\n", terr);
		raise "fail:checkpoint";
	}
	if(steps <= 0 || steps > t.config.seq_len)
		steps = t.config.seq_len;

	(tk, tkerr) := llama->build_tokenizer(tokenizer_path, t.config.vocab_size);
	if(tk == nil){
		sys->fprint(stderr, "build_tokenizer: %s\n", tkerr);
		raise "fail:tokenizer";
	}

	sa := llama->build_sampler(t.config.vocab_size, temperature, topp, rng_seed);

	llama->generate(t, tk, sa, prompt, steps);
}
