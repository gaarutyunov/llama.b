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

init(nil: ref Draw->Context, nil: list of string)
{
	sys = load Sys Sys->PATH;
	llama = load Llama Llama->PATH;
	if(llama == nil){
		sys->fprint(sys->fildes(2), "cannot load Llama: %r\n");
		raise "fail:load";
	}
	if(llama->init() < 0){
		sys->fprint(sys->fildes(2), "llama->init failed\n");
		raise "fail:init";
	}

	x := array[4] of real;
	x[0] = 1.0; x[1] = 2.0; x[2] = 3.0; x[3] = 4.0;
	w := array[4] of real;
	w[0] = 0.5; w[1] = 0.5; w[2] = 0.5; w[3] = 0.5;
	o := array[4] of real;
	llama->rmsnorm(o, x, w, 4);
	for(i := 0; i < 4; i++)
		sys->print("%.6f\n", o[i]);
}
