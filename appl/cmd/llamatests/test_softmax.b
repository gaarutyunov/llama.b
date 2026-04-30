implement TestSoftmax;

include "sys.m";
	sys: Sys;

include "draw.m";

include "llama.m";
	llama: Llama;

TestSoftmax: module
{
	init: fn(ctxt: ref Draw->Context, argv: list of string);
};

init(nil: ref Draw->Context, argv: list of string)
{
	argv = nil;
	sys = load Sys Sys->PATH;
	llama = load Llama Llama->PATH;
	if(llama == nil){
		sys->fprint(sys->fildes(2), "cannot load Llama: %r\n");
		raise "fail:load";
	}
	if(llama->init() < 0)
		raise "fail:init";

	x := array[5] of real;
	x[0] = 1.0; x[1] = 2.0; x[2] = 3.0; x[3] = 4.0; x[4] = 5.0;
	llama->softmax(x, 0, 5);
	for(i := 0; i < 5; i++)
		sys->print("%.6f\n", x[i]);
}
