implement TestModelLoading;

include "sys.m";
	sys: Sys;

include "draw.m";

include "llama.m";
	llama: Llama;

TestModelLoading: module
{
	init: fn(ctxt: ref Draw->Context, argv: list of string);
};

init(nil: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	llama = load Llama Llama->PATH;
	if(llama == nil){
		sys->fprint(sys->fildes(2), "cannot load Llama: %r\n");
		raise "fail:load";
	}
	if(llama->init() < 0)
		raise "fail:init";

	argv = tl argv;
	if(argv == nil){
		sys->fprint(sys->fildes(2), "usage: test_model_loading <checkpoint>\n");
		raise "fail:usage";
	}
	path := hd argv;
	(t, err) := llama->build_transformer(path);
	if(t == nil){
		sys->fprint(sys->fildes(2), "build: %s\n", err);
		raise "fail:build";
	}
	sys->print("dim=%d\n",         t.config.dim);
	sys->print("hidden_dim=%d\n",  t.config.hidden_dim);
	sys->print("n_layers=%d\n",    t.config.n_layers);
	sys->print("n_heads=%d\n",     t.config.n_heads);
	sys->print("n_kv_heads=%d\n",  t.config.n_kv_heads);
	sys->print("vocab_size=%d\n",  t.config.vocab_size);
	sys->print("seq_len=%d\n",     t.config.seq_len);
	# print first 10 token-embedding floats so we can verify byte ordering
	for(i := 0; i < 10; i++)
		sys->print("w%d=%.6f\n", i, t.w.token_embedding[i]);
}
