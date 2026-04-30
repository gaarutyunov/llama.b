implement TestMatmul;

include "sys.m";
	sys: Sys;

include "draw.m";

include "llama.m";
	llama: Llama;

TestMatmul: module
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

	# w (3x4) @ x (4) = out (3)
	w := array[12] of real;
	for(i := 0; i < 12; i++)
		w[i] = real (i + 1);
	x := array[4] of real;
	for(i = 0; i < 4; i++)
		x[i] = real (i + 1);
	o := array[3] of real;
	llama->matmul(o, x, w, 0, 4, 3);
	for(i = 0; i < 3; i++)
		sys->print("%.6f\n", o[i]);
}
