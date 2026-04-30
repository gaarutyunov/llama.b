implement TestLoadLlama;

include "sys.m";
	sys: Sys;

include "draw.m";

include "llama.m";
	llama: Llama;

TestLoadLlama: module
{
	init: fn(ctxt: ref Draw->Context, argv: list of string);
};

init(nil: ref Draw->Context, argv: list of string)
{
	argv = nil;
	sys = load Sys Sys->PATH;
	stderr := sys->fildes(2);
	sys->fprint(stderr, "step 1: sys loaded\n");
	llama = load Llama Llama->PATH;
	if(llama == nil){
		sys->fprint(stderr, "step 2: llama load failed: %r\n");
		raise "fail:load";
	}
	sys->fprint(stderr, "step 2: llama loaded\n");
	if(llama->init() < 0){
		sys->fprint(stderr, "step 3: llama init failed\n");
		raise "fail:init";
	}
	sys->fprint(stderr, "step 3: llama init ok\n");
	sys->print("ok\n");
}
