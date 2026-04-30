implement TestRmsnorm;

include "sys.m";
	sys: Sys;

include "draw.m";

include "llama.m";
	llama: Llama;

TestRmsnorm: module
{
	init: fn(ctxt: ref Draw->Context, argv: list of string);
};

init(nil: ref Draw->Context, argv: list of string)
{
	argv = nil;
	sys = load Sys Sys->PATH;
	if(sys == nil)
		return;
	stderr := sys->fildes(2);
	sys->fprint(stderr, "rmsnorm: 1 sys\n");

	llama = load Llama Llama->PATH;
	if(llama == nil){
		sys->fprint(stderr, "rmsnorm: load Llama failed: %r\n");
		raise "fail:load";
	}
	sys->fprint(stderr, "rmsnorm: 2 llama loaded\n");

	if(llama->init() < 0){
		sys->fprint(stderr, "rmsnorm: llama->init failed\n");
		raise "fail:init";
	}
	sys->fprint(stderr, "rmsnorm: 3 llama init\n");

	x := array[4] of real;
	x[0] = 1.0; x[1] = 2.0; x[2] = 3.0; x[3] = 4.0;
	w := array[4] of real;
	w[0] = 0.5; w[1] = 0.5; w[2] = 0.5; w[3] = 0.5;
	o := array[4] of real;
	sys->fprint(stderr, "rmsnorm: 4 about to call rmsnorm\n");
	llama->rmsnorm(o, x, w, 4);
	sys->fprint(stderr, "rmsnorm: 5 rmsnorm returned\n");
	for(i := 0; i < 4; i++)
		sys->print("%.6f\n", o[i]);
	sys->fprint(stderr, "rmsnorm: 6 done\n");
}
