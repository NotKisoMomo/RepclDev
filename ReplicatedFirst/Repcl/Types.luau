--!strict
local Types = {}

export type OutputKind = "print" | "warn" | "error" | "notify" | "reply"

export type OutputEntry = {
	kind: OutputKind,
	text: string,
}

export type FlagDef = {
	Name:     string,
	Type:     string,
	Default:  any?,
	Aliases:  {string}?,
}

export type ArgDef = {
	Name:     string,
	Type:     string,
	Optional: boolean?,
	Default:  any?,
	Variadic: boolean?,
}

export type CommandDef = {
	Name:        string,
	Aliases:     {string}?,
	Description: string?,
	Args:        {ArgDef}?,
	Flags:       {FlagDef}?,
	Bridge:      boolean?,
	Client:      ((ctx: RepclCtx) -> ())?,
	Server:      ((ctx: RepclCtx) -> ())?,
	Permission:  string?,
}

export type ParseResult = {
	args:  { [string]: any },
	flags: { [string]: any },
	raw:   string,
}

export type RepclCtx = {
	Args:     { [string]: any },
	Flags:    { [string]: any },
	Player:   Player,
	IsServer: boolean,

	Print:   (msg: string) -> (),
	Warn:    (msg: string) -> (),
	Err:     (msg: string) -> (),
	Error:   (msg: string) -> (),
	Notify:  (msg: string) -> (),
	Reply:   (msg: string) -> (),
	Abort:   (reason: string?) -> (),
	Commit:  (payload: any) -> (),

	_getOutput: () -> {OutputEntry},
	_getCommit: () -> any,
}

export type BuilderDef = {
	name:        string,
	description: string?,
	aliases:     {string}?,
	permission:  string?,
	args:        {ArgDef}?,
	flags:       {FlagDef}?,
	bridge:      boolean?,
	client:      ((ctx: RepclCtx) -> ())?,
	server:      ((ctx: RepclCtx) -> ())?,
}

return Types