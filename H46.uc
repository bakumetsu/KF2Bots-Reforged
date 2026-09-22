class H46 extends Object
    abstract;

var private byte H47[41];
var private array<byte> H48;

// NOTE: This class existed purely to overlay onto the engine's real
// UFunction so its compiled-bytecode array ("Script", exposed here as H48)
// could be overwritten by the hex-patched compiler/memory hack described in
// FunctionHooks.uc. Now that hooking mechanism has been removed, nothing in
// this project references H46 or H48 any more (it compiles cleanly, but is
// otherwise dead code) - it's left here only in case something outside the
// uploaded files still depends on it. It's safe to delete this file if you
// confirm nothing else in your project references H46.
