implement TestHello;

include "sys.m";
	sys: Sys;

include "draw.m";

TestHello: module
{
	init: fn(ctxt: ref Draw->Context, argv: list of string);
};

init(nil: ref Draw->Context, argv: list of string)
{
	argv = nil;
	sys = load Sys Sys->PATH;
	if(sys == nil)
		return;
	sys->print("hello from limbo\n");
}
