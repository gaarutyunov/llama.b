implement TestRng;

include "sys.m";
	sys: Sys;

include "draw.m";

include "llama.m";
	llama: Llama;

TestRng: module
{
	init: fn(ctxt: ref Draw->Context, argv: list of string);
};

init(nil: ref Draw->Context, nil: list of string)
{
	sys = load Sys Sys->PATH;
	llama = load Llama Llama->PATH;
	if(llama == nil){
		sys->fprint(sys->fildes(2), "cannot load Llama: %r\n");
		raise "fail:load";
	}
	if(llama->init() < 0)
		raise "fail:init";

	state := big 42;
	for(i := 0; i < 10; i++){
		(ns, v) := llama->random_u32(state);
		state = ns;
		# treat as unsigned 32-bit by masking
		uu := big v & ((big 1 << 32) - big 1);
		sys->print("%bd\n", uu);
	}
}
