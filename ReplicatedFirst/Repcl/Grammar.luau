local Grammar = {}

export type CompletionKind = "keyword" | "builtin" | "global" | "method" | "property" | "type" | "snippet" | "repcl"
export type Completion = {
	label: string,
	kind: CompletionKind,
	detail: string?,
	documentation: string?,
	insertText: string?,
}
export type MemberMap = { [string]: Completion }
export type GrammarEntry = {
	label: string,
	kind: CompletionKind,
	detail: string?,
	documentation: string?,
	members: MemberMap?,
	insertText: string?,
}

local function kw(label: string): GrammarEntry
	return { label = label, kind = "keyword" }
end

local function bi(label: string, detail: string?, doc: string?): GrammarEntry
	return { label = label, kind = "builtin", detail = detail, documentation = doc }
end

local function gl(label: string, detail: string?, members: MemberMap?): GrammarEntry
	return { label = label, kind = "global", detail = detail, members = members }
end

local function sn(label: string, insert: string, detail: string?): GrammarEntry
	return { label = label, kind = "snippet", insertText = insert, detail = detail }
end

local function prop(label: string, detail: string?): Completion
	return { label = label, kind = "property", detail = detail }
end

local function meth(label: string, detail: string?): Completion
	return { label = label, kind = "method", detail = detail }
end

Grammar.Keywords = {
	kw("and"), kw("break"), kw("continue"), kw("do"),
	kw("else"), kw("elseif"), kw("end"), kw("false"),
	kw("for"), kw("function"), kw("if"), kw("in"),
	kw("local"), kw("nil"), kw("not"), kw("or"),
	kw("repeat"), kw("return"), kw("then"), kw("true"),
	kw("until"), kw("while"),
	kw("export"), kw("type"),
}

Grammar.Types = {
	kw("any"), kw("boolean"), kw("number"), kw("string"),
	kw("nil"), kw("never"), kw("unknown"),
	kw("thread"), kw("buffer"),
}

Grammar.Operators = {
	"+", "-", "*", "/", "//", "%", "^",
	"==", "~=", "<", "<=", ">", ">=",
	"and", "or", "not",
	"#", "..", "->", ":",
	"=", "+=", "-=", "*=", "/=", "%=", "//=", "..=",
}

Grammar.Globals = {
	bi("print",    "(...)"),
	bi("warn",     "(...)"),
	bi("error",    "(msg: string, level: number?)"),
	bi("assert",   "(v: any, msg: string?): any"),
	bi("pcall",    "(f: (...any) -> ...any, ...): (boolean, ...any)"),
	bi("xpcall",   "(f: () -> (), handler: (string) -> ()): boolean"),
	bi("ipairs",   "(t: {any}): iterator"),
	bi("pairs",    "(t: {}): iterator"),
	bi("next",     "(t: {}, k: any?): (any, any)"),
	bi("select",   "(index: number | '#', ...): ...any"),
	bi("tonumber", "(v: any, base: number?): number?"),
	bi("tostring", "(v: any): string"),
	bi("type",     "(v: any): string"),
	bi("typeof",   "(v: any): string"),
	bi("unpack",   "(t: {any}, i: number?, j: number?): ...any"),
	bi("rawget",   "(t: {}, k: any): any"),
	bi("rawset",   "(t: {}, k: any, v: any): {}"),
	bi("rawequal", "(a: any, b: any): boolean"),
	bi("rawlen",   "(v: {} | string): number"),
	bi("setmetatable", "(t: {}, mt: {}?): {}"),
	bi("getmetatable",  "(t: {}): {}?"),
	bi("require",   "(module: ModuleScript): any"),
	bi("collectgarbage", "('count'): number"),
	bi("loadstring", "(src: string): (() -> ())?"),
	bi("newproxy",  "(mt: boolean?): userdata"),
	bi("tick",      "(): number", "Seconds since Unix epoch (Roblox-specific)"),
	bi("time",      "(): number", "Elapsed seconds since server start"),
	bi("os.clock",  "(): number"),
	bi("delay",     "(t: number, f: () -> ())"),
	bi("spawn",     "(f: () -> ())"),
	bi("wait",      "(t: number?): (number, number)"),
	bi("_G",        "{}"),
	bi("_VERSION",  "string"),
	bi("game",      "DataModel"),
	bi("workspace", "Workspace"),
	bi("script",    "LuaSourceContainer"),
	bi("plugin",    "Plugin?"),
}

local tableMethods: MemberMap = {
	insert  = meth("insert",  "(t, [pos,] v)"),
	remove  = meth("remove",  "(t, [pos])"),
	concat  = meth("concat",  "(t, sep?, i?, j?): string"),
	sort    = meth("sort",    "(t, comp?)"),
	move    = meth("move",    "(a1, f, e, t, [a2])"),
	unpack  = meth("unpack",  "(t, i?, j?): ...any"),
	find    = meth("find",    "(t, v, init?): number?"),
	clear   = meth("clear",   "(t)"),
	freeze  = meth("freeze",  "(t): {}"),
	isfrozen = meth("isfrozen","(t): boolean"),
	create  = meth("create",  "(n, v?): {any}"),
	getn    = meth("getn",    "(t): number"),
}

local stringMethods: MemberMap = {
	len     = meth("len",     "(): number"),
	sub     = meth("sub",     "(i, j?): string"),
	rep     = meth("rep",     "(n, sep?): string"),
	reverse = meth("reverse", "(): string"),
	upper   = meth("upper",   "(): string"),
	lower   = meth("lower",   "(): string"),
	byte    = meth("byte",    "(i?, j?): ...number"),
	char    = meth("char",    "(...number): string"),
	find    = meth("find",    "(pat, init?, plain?): (number?, number?, ...string)"),
	match   = meth("match",   "(pat, init?): string?"),
	gmatch  = meth("gmatch",  "(pat): iterator"),
	gsub    = meth("gsub",    "(pat, repl, n?): (string, number)"),
	format  = meth("format",  "(fmt, ...): string"),
	split   = meth("split",   "(sep): {string}"),
	pack    = meth("pack",    "(fmt, ...): string"),
	unpack  = meth("unpack",  "(fmt, s, pos?): ...any"),
	packsize = meth("packsize","(fmt): number"),
}

local mathMethods: MemberMap = {
	abs   = meth("abs",   "(n): number"),
	ceil  = meth("ceil",  "(n): number"),
	floor = meth("floor", "(n): number"),
	round = meth("round", "(n): number"),
	sqrt  = meth("sqrt",  "(n): number"),
	sin   = meth("sin",   "(n): number"),
	cos   = meth("cos",   "(n): number"),
	tan   = meth("tan",   "(n): number"),
	asin  = meth("asin",  "(n): number"),
	acos  = meth("acos",  "(n): number"),
	atan  = meth("atan",  "(y, x?): number"),
	exp   = meth("exp",   "(n): number"),
	log   = meth("log",   "(n, base?): number"),
	pow   = meth("pow",   "(x, y): number"),
	max   = meth("max",   "(...number): number"),
	min   = meth("min",   "(...number): number"),
	fmod  = meth("fmod",  "(x, y): number"),
	modf  = meth("modf",  "(n): (number, number)"),
	huge  = prop("huge",  "number -- math.huge (inf)"),
	pi    = prop("pi",    "number -- 3.14159..."),
	random     = meth("random",     "(m?, n?): number"),
	randomseed = meth("randomseed", "(n)"),
	clamp = meth("clamp", "(n, min, max): number"),
	sign  = meth("sign",  "(n): number"),
	noise = meth("noise", "(x, y?, z?): number"),
	map   = meth("map",   "(n, min, max, newMin, newMax): number"),
}

local taskMethods: MemberMap = {
	spawn  = meth("spawn",  "(f: () -> (), ...): thread"),
	defer  = meth("defer",  "(f: () -> (), ...): thread"),
	delay  = meth("delay",  "(t: number, f: () -> (), ...): thread"),
	wait   = meth("wait",   "(t: number?): number"),
	cancel = meth("cancel", "(thread: thread)"),
	desynchronize = meth("desynchronize", "()"),
	synchronize   = meth("synchronize",   "()"),
}

local bit32Methods: MemberMap = {
	band     = meth("band",     "(...number): number"),
	bor      = meth("bor",      "(...number): number"),
	bxor     = meth("bxor",     "(...number): number"),
	bnot     = meth("bnot",     "(n): number"),
	lshift   = meth("lshift",   "(n, disp): number"),
	rshift   = meth("rshift",   "(n, disp): number"),
	arshift  = meth("arshift",  "(n, disp): number"),
	lrotate  = meth("lrotate",  "(n, disp): number"),
	rrotate  = meth("rrotate",  "(n, disp): number"),
	extract  = meth("extract",  "(n, f, w?): number"),
	replace  = meth("replace",  "(n, v, f, w?): number"),
	countlz  = meth("countlz",  "(n): number"),
	countrz  = meth("countrz",  "(n): number"),
	byteswap = meth("byteswap", "(n): number"),
}

local osMethods: MemberMap = {
	time   = meth("time",   "(): number"),
	clock  = meth("clock",  "(): number"),
	date   = meth("date",   "(fmt?, t?): string | {}"),
	difftime = meth("difftime","(t2, t1): number"),
}

local bufferMethods: MemberMap = {
	create   = meth("create",   "(size: number): buffer"),
	fromstring = meth("fromstring","(s: string): buffer"),
	tostring  = meth("tostring", "(b: buffer): string"),
	len       = meth("len",      "(b: buffer): number"),
	copy      = meth("copy",     "(dst, dstOffset, src, srcOffset?, count?)"),
	fill      = meth("fill",     "(b, offset, value, count?)"),
	readi8    = meth("readi8",   "(b, offset): number"),
	readu8    = meth("readu8",   "(b, offset): number"),
	readi16   = meth("readi16",  "(b, offset): number"),
	readu16   = meth("readu16",  "(b, offset): number"),
	readi32   = meth("readi32",  "(b, offset): number"),
	readu32   = meth("readu32",  "(b, offset): number"),
	readf32   = meth("readf32",  "(b, offset): number"),
	readf64   = meth("readf64",  "(b, offset): number"),
	writei8   = meth("writei8",  "(b, offset, v)"),
	writeu8   = meth("writeu8",  "(b, offset, v)"),
	writei16  = meth("writei16", "(b, offset, v)"),
	writeu16  = meth("writeu16", "(b, offset, v)"),
	writei32  = meth("writei32", "(b, offset, v)"),
	writeu32  = meth("writeu32", "(b, offset, v)"),
	writef32  = meth("writef32", "(b, offset, v)"),
	writef64  = meth("writef64", "(b, offset, v)"),
	readstring  = meth("readstring",  "(b, offset, count): string"),
	writestring = meth("writestring", "(b, offset, s, count?)"),
}

Grammar.Libs = {
	gl("table",  "table library",  tableMethods),
	gl("string", "string library", stringMethods),
	gl("math",   "math library",   mathMethods),
	gl("task",   "task library",   taskMethods),
	gl("bit32",  "bit32 library",  bit32Methods),
	gl("os",     "os library",     osMethods),
	gl("buffer", "buffer library", bufferMethods),
	gl("coroutine", "coroutine library", {
		create  = meth("create",  "(f: () -> ()): thread"),
		resume  = meth("resume",  "(co: thread, ...): (boolean, ...any)"),
		yield   = meth("yield",   "(...): ...any"),
		wrap    = meth("wrap",    "(f: () -> ()): (() -> ...any)"),
		status  = meth("status",  "(co: thread): string"),
		running = meth("running", "(): thread?"),
		isyieldable = meth("isyieldable","(): boolean"),
		close   = meth("close",   "(co: thread): boolean"),
	}),
}

local instanceMembers: MemberMap = {
	Name            = prop("Name",             "string"),
	Parent          = prop("Parent",           "Instance?"),
	ClassName       = prop("ClassName",        "string"),
	Archivable      = prop("Archivable",       "boolean"),
	FindFirstChild  = meth("FindFirstChild",   "(name: string, recursive?: boolean): Instance?"),
	FindFirstChildWhichIsA = meth("FindFirstChildWhichIsA","(className: string): Instance?"),
	FindFirstAncestorWhichIsA = meth("FindFirstAncestorWhichIsA","(className: string): Instance?"),
	WaitForChild    = meth("WaitForChild",     "(name: string, timeout?: number): Instance"),
	IsA             = meth("IsA",              "(className: string): boolean"),
	IsAncestorOf    = meth("IsAncestorOf",     "(desc: Instance): boolean"),
	IsDescendantOf  = meth("IsDescendantOf",   "(anc: Instance): boolean"),
	GetChildren     = meth("GetChildren",      "(): {Instance}"),
	GetDescendants  = meth("GetDescendants",   "(): {Instance}"),
	GetFullName     = meth("GetFullName",      "(): string"),
	GetAttribute    = meth("GetAttribute",     "(name: string): any"),
	SetAttribute    = meth("SetAttribute",     "(name: string, value: any)"),
	GetAttributeChangedSignal = meth("GetAttributeChangedSignal","(name: string): RBXScriptSignal"),
	GetPropertyChangedSignal = meth("GetPropertyChangedSignal","(prop: string): RBXScriptSignal"),
	Clone           = meth("Clone",            "(): Instance"),
	Destroy         = meth("Destroy",          "()"),
	Remove          = meth("Remove",           "()"),
	ClearAllChildren = meth("ClearAllChildren","()"),
	Changed         = prop("Changed",          "RBXScriptSignal"),
	ChildAdded      = prop("ChildAdded",       "RBXScriptSignal"),
	ChildRemoved    = prop("ChildRemoved",     "RBXScriptSignal"),
	DescendantAdded = prop("DescendantAdded",  "RBXScriptSignal"),
	AncestryChanged = prop("AncestryChanged",  "RBXScriptSignal"),
	AttributeChanged = prop("AttributeChanged","RBXScriptSignal"),
	AddTag          = meth("AddTag",           "(tag: string)"),
	RemoveTag       = meth("RemoveTag",        "(tag: string)"),
	HasTag          = meth("HasTag",           "(tag: string): boolean"),
	GetTags         = meth("GetTags",          "(): {string}"),
}

local basePartMembers: MemberMap = table.clone(instanceMembers) :: MemberMap
do
	local bp: MemberMap = {
		Size         = prop("Size",         "Vector3"),
		Position     = prop("Position",     "Vector3"),
		CFrame       = prop("CFrame",       "CFrame"),
		Orientation  = prop("Orientation",  "Vector3"),
		Anchored     = prop("Anchored",     "boolean"),
		CanCollide   = prop("CanCollide",   "boolean"),
		CanTouch     = prop("CanTouch",     "boolean"),
		CanQuery     = prop("CanQuery",     "boolean"),
		Massless     = prop("Massless",     "boolean"),
		Material     = prop("Material",     "Enum.Material"),
		Color        = prop("Color",        "Color3"),
		Transparency = prop("Transparency", "number"),
		Reflectance  = prop("Reflectance",  "number"),
		CastShadow   = prop("CastShadow",   "boolean"),
		AssemblyLinearVelocity  = prop("AssemblyLinearVelocity",  "Vector3"),
		AssemblyAngularVelocity = prop("AssemblyAngularVelocity", "Vector3"),
		AssemblyRootPart        = prop("AssemblyRootPart",        "BasePart"),
		GetMass           = meth("GetMass",           "(): number"),
		ApplyImpulse      = meth("ApplyImpulse",      "(impulse: Vector3)"),
		ApplyAngularImpulse = meth("ApplyAngularImpulse","(impulse: Vector3)"),
		GetVelocityAtPosition = meth("GetVelocityAtPosition","(pos: Vector3): Vector3"),
		GetNetworkOwner   = meth("GetNetworkOwner",   "(): Player?"),
		SetNetworkOwner   = meth("SetNetworkOwner",   "(player: Player?)"),
		IsGrounded        = meth("IsGrounded",        "(): boolean"),
		Touched           = prop("Touched",           "RBXScriptSignal"),
		TouchEnded        = prop("TouchEnded",        "RBXScriptSignal"),
	}
	for k, v in bp do
		basePartMembers[k] = v
	end
end

local humanoidMembers: MemberMap = table.clone(instanceMembers) :: MemberMap
do
	local hm: MemberMap = {
		Health          = prop("Health",          "number"),
		MaxHealth       = prop("MaxHealth",       "number"),
		WalkSpeed       = prop("WalkSpeed",       "number"),
		JumpPower       = prop("JumpPower",       "number"),
		JumpHeight      = prop("JumpHeight",      "number"),
		AutoRotate      = prop("AutoRotate",      "boolean"),
		AutoJumpEnabled = prop("AutoJumpEnabled", "boolean"),
		HipHeight       = prop("HipHeight",       "number"),
		RootPart        = prop("RootPart",        "BasePart?"),
		RigType         = prop("RigType",         "Enum.HumanoidRigType"),
		DisplayName     = prop("DisplayName",     "string"),
		NameDisplayDistance    = prop("NameDisplayDistance",    "number"),
		HealthDisplayDistance  = prop("HealthDisplayDistance",  "number"),
		TakeDamage      = meth("TakeDamage",      "(amount: number)"),
		AddAccessory    = meth("AddAccessory",    "(acc: Accessory)"),
		GetAppliedDescription = meth("GetAppliedDescription","(): HumanoidDescription"),
		ApplyDescription = meth("ApplyDescription","(desc: HumanoidDescription)"),
		MoveTo          = meth("MoveTo",          "(pos: Vector3, part?: BasePart)"),
		ChangeState     = meth("ChangeState",     "(state: Enum.HumanoidStateType)"),
		GetState        = meth("GetState",        "(): Enum.HumanoidStateType"),
		GetPlayingAnimationTracks = meth("GetPlayingAnimationTracks","(): {AnimationTrack}"),
		LoadAnimation   = meth("LoadAnimation",   "(anim: Animation): AnimationTrack"),
		Died            = prop("Died",            "RBXScriptSignal"),
		HealthChanged   = prop("HealthChanged",   "RBXScriptSignal"),
		StateChanged    = prop("StateChanged",    "RBXScriptSignal"),
		MoveToFinished  = prop("MoveToFinished",  "RBXScriptSignal"),
		Seated          = prop("Seated",          "RBXScriptSignal"),
		Touched         = prop("Touched",         "RBXScriptSignal"),
	}
	for k, v in hm do
		humanoidMembers[k] = v
	end
end

local guiObjectMembers: MemberMap = table.clone(instanceMembers) :: MemberMap
do
	local gm: MemberMap = {
		Size              = prop("Size",              "UDim2"),
		Position          = prop("Position",          "UDim2"),
		AnchorPoint       = prop("AnchorPoint",       "Vector2"),
		BackgroundColor3  = prop("BackgroundColor3",  "Color3"),
		BackgroundTransparency = prop("BackgroundTransparency","number"),
		BorderSizePixel   = prop("BorderSizePixel",   "number"),
		BorderColor3      = prop("BorderColor3",      "Color3"),
		Visible           = prop("Visible",           "boolean"),
		ZIndex            = prop("ZIndex",            "number"),
		LayoutOrder       = prop("LayoutOrder",       "number"),
		Rotation          = prop("Rotation",          "number"),
		AutomaticSize     = prop("AutomaticSize",     "Enum.AutomaticSize"),
		ClipsDescendants  = prop("ClipsDescendants",  "boolean"),
		Interactable      = prop("Interactable",      "boolean"),
		SizeConstraint    = prop("SizeConstraint",    "Enum.SizeConstraint"),
		MouseEnter        = prop("MouseEnter",        "RBXScriptSignal"),
		MouseLeave        = prop("MouseLeave",        "RBXScriptSignal"),
		InputBegan        = prop("InputBegan",        "RBXScriptSignal"),
		InputEnded        = prop("InputEnded",        "RBXScriptSignal"),
		SelectionGained   = prop("SelectionGained",   "RBXScriptSignal"),
		SelectionLost     = prop("SelectionLost",     "RBXScriptSignal"),
		TweenPosition     = meth("TweenPosition",     "(pos, easing?, dir?, t?, override?, callback?)"),
		TweenSize         = meth("TweenSize",         "(size, easing?, dir?, t?, override?, callback?)"),
	}
	for k, v in gm do
		guiObjectMembers[k] = v
	end
end

local textLabelMembers: MemberMap = table.clone(guiObjectMembers) :: MemberMap
do
	local tl: MemberMap = {
		Text         = prop("Text",         "string"),
		TextColor3   = prop("TextColor3",   "Color3"),
		TextSize     = prop("TextSize",     "number"),
		Font         = prop("Font",         "Enum.Font"),
		FontFace     = prop("FontFace",     "Font"),
		TextWrapped  = prop("TextWrapped",  "boolean"),
		TextTruncate = prop("TextTruncate", "Enum.TextTruncate"),
		TextScaled   = prop("TextScaled",   "boolean"),
		RichText     = prop("RichText",     "boolean"),
		TextXAlignment = prop("TextXAlignment","Enum.TextXAlignment"),
		TextYAlignment = prop("TextYAlignment","Enum.TextYAlignment"),
		TextTransparency = prop("TextTransparency","number"),
		TextStrokeColor3 = prop("TextStrokeColor3","Color3"),
		TextStrokeTransparency = prop("TextStrokeTransparency","number"),
		MaxVisibleGraphemes = prop("MaxVisibleGraphemes","number"),
		ContentText  = prop("ContentText",  "string"),
		TextBounds   = prop("TextBounds",   "Vector2"),
		TextFits     = prop("TextFits",     "boolean"),
	}
	for k, v in tl do
		textLabelMembers[k] = v
	end
end

local textBoxMembers: MemberMap = table.clone(textLabelMembers) :: MemberMap
do
	local tb: MemberMap = {
		PlaceholderText  = prop("PlaceholderText",  "string"),
		PlaceholderColor3 = prop("PlaceholderColor3","Color3"),
		ClearTextOnFocus = prop("ClearTextOnFocus", "boolean"),
		MultiLine        = prop("MultiLine",        "boolean"),
		TextEditable     = prop("TextEditable",     "boolean"),
		CursorPosition   = prop("CursorPosition",   "number"),
		SelectionStart   = prop("SelectionStart",   "number"),
		ShowNativeInput  = prop("ShowNativeInput",  "boolean"),
		CaptureFocus     = meth("CaptureFocus",     "()"),
		ReleaseFocus     = meth("ReleaseFocus",     "(submitted?: boolean)"),
		FocusLost        = prop("FocusLost",        "RBXScriptSignal"),
		Focused          = prop("Focused",          "RBXScriptSignal"),
	}
	for k, v in tb do
		textBoxMembers[k] = v
	end
end

local animationTrackMembers: MemberMap = {
	Length       = prop("Length",       "number"),
	Speed        = prop("Speed",        "number"),
	Weight       = prop("Weight",       "number"),
	WeightCurrent = prop("WeightCurrent","number"),
	IsPlaying    = prop("IsPlaying",    "boolean"),
	Looped       = prop("Looped",       "boolean"),
	Priority     = prop("Priority",     "Enum.AnimationPriority"),
	TimePosition = prop("TimePosition", "number"),
	Play          = meth("Play",        "(fadeTime?, weight?, speed?)"),
	Stop          = meth("Stop",        "(fadeTime?)"),
	AdjustSpeed   = meth("AdjustSpeed", "(speed)"),
	AdjustWeight  = meth("AdjustWeight","(weight, fadeTime?)"),
	GetMarkerReachedSignal = meth("GetMarkerReachedSignal","(name: string): RBXScriptSignal"),
	Stopped      = prop("Stopped",      "RBXScriptSignal"),
	DidLoop      = prop("DidLoop",      "RBXScriptSignal"),
	KeyframeReached = prop("KeyframeReached","RBXScriptSignal"),
}

local soundMembers: MemberMap = table.clone(instanceMembers) :: MemberMap
do
	local sm: MemberMap = {
		SoundId     = prop("SoundId",     "string"),
		Volume      = prop("Volume",      "number"),
		Pitch       = prop("Pitch",       "number"),
		PlaybackSpeed = prop("PlaybackSpeed","number"),
		Looped      = prop("Looped",      "boolean"),
		Playing     = prop("Playing",     "boolean"),
		IsLoaded    = prop("IsLoaded",    "boolean"),
		IsPaused    = prop("IsPaused",    "boolean"),
		IsPlaying   = prop("IsPlaying",   "boolean"),
		TimeLength  = prop("TimeLength",  "number"),
		TimePosition = prop("TimePosition","number"),
		RollOffMaxDistance = prop("RollOffMaxDistance","number"),
		RollOffMinDistance = prop("RollOffMinDistance","number"),
		Play     = meth("Play",     "()"),
		Stop     = meth("Stop",     "()"),
		Pause    = meth("Pause",    "()"),
		Resume   = meth("Resume",   "()"),
		Ended    = prop("Ended",    "RBXScriptSignal"),
		Loaded   = prop("Loaded",   "RBXScriptSignal"),
		Paused   = prop("Paused",   "RBXScriptSignal"),
		Played   = prop("Played",   "RBXScriptSignal"),
		Stopped  = prop("Stopped",  "RBXScriptSignal"),
	}
	for k, v in sm do
		soundMembers[k] = v
	end
end

Grammar.Classes = {
	gl("Instance",       "Roblox base class",       instanceMembers),
	gl("BasePart",       "Physical part base",      basePartMembers),
	gl("Part",           "Concrete part",           basePartMembers),
	gl("MeshPart",       "Mesh-based part",         basePartMembers),
	gl("Model",          "Model container",         instanceMembers),
	gl("Humanoid",       "Character humanoid",      humanoidMembers),
	gl("GuiObject",      "GUI base class",          guiObjectMembers),
	gl("Frame",          "Frame container",         guiObjectMembers),
	gl("ScreenGui",      "Top-level GUI container", instanceMembers),
	gl("TextLabel",      "Text display",            textLabelMembers),
	gl("TextButton",     "Clickable text",          textLabelMembers),
	gl("TextBox",        "Text input",              textBoxMembers),
	gl("ImageLabel",     "Image display",           guiObjectMembers),
	gl("ImageButton",    "Clickable image",         guiObjectMembers),
	gl("ScrollingFrame", "Scrollable container",    guiObjectMembers),
	gl("ViewportFrame",  "3D viewport",             guiObjectMembers),
	gl("VideoFrame",     "Video player frame",      guiObjectMembers),
	gl("AnimationTrack", "Playing animation",       animationTrackMembers),
	gl("Sound",          "Audio instance",          soundMembers),
	gl("RemoteEvent", "Client<->Server event", {
		FireServer        = meth("FireServer",        "(...)"),
		FireClient        = meth("FireClient",        "(player: Player, ...)"),
		FireAllClients    = meth("FireAllClients",    "(...)"),
		OnClientEvent     = prop("OnClientEvent",     "RBXScriptSignal"),
		OnServerEvent     = prop("OnServerEvent",     "RBXScriptSignal"),
	}),
	gl("RemoteFunction", "Client<->Server invoke", {
		InvokeServer      = meth("InvokeServer",      "(...): ...any"),
		InvokeClient      = meth("InvokeClient",      "(player: Player, ...): ...any"),
		OnClientInvoke    = prop("OnClientInvoke",    "(... ) -> ...any"),
		OnServerInvoke    = prop("OnServerInvoke",    "(player, ...) -> ...any"),
	}),
	gl("BindableEvent", "Intra-script event", {
		Fire   = meth("Fire",   "(...)"),
		Event  = prop("Event",  "RBXScriptSignal"),
	}),
	gl("BindableFunction", "Intra-script invoke", {
		Invoke         = meth("Invoke",         "(...): ...any"),
		OnInvoke       = prop("OnInvoke",       "(...) -> ...any"),
	}),
	gl("RaycastParams", "Raycast configuration", {
		FilterDescendantsInstances = prop("FilterDescendantsInstances","{Instance}"),
		FilterType                 = prop("FilterType",                "Enum.RaycastFilterType"),
		IgnoreWater                = prop("IgnoreWater",               "boolean"),
		CollisionGroup             = prop("CollisionGroup",            "string"),
		RespectCanCollide          = prop("RespectCanCollide",         "boolean"),
		BruteForceAllSlow          = prop("BruteForceAllSlow",         "boolean"),
		new                        = meth("new",                       "(): RaycastParams"),
	}),
	gl("OverlapParams", "Spatial query configuration", {
		FilterDescendantsInstances = prop("FilterDescendantsInstances","{Instance}"),
		FilterType                 = prop("FilterType",                "Enum.RaycastFilterType"),
		MaxParts                   = prop("MaxParts",                  "number"),
		CollisionGroup             = prop("CollisionGroup",            "string"),
		RespectCanCollide          = prop("RespectCanCollide",         "boolean"),
		BruteForceAllSlow          = prop("BruteForceAllSlow",         "boolean"),
		new                        = meth("new",                       "(): OverlapParams"),
	}),
}

Grammar.Datatypes = {
	gl("Vector3", "3D vector", {
		new    = meth("new",    "(x, y, z): Vector3"),
		zero   = prop("zero",   "Vector3"),
		one    = prop("one",    "Vector3"),
		xAxis  = prop("xAxis",  "Vector3"),
		yAxis  = prop("yAxis",  "Vector3"),
		zAxis  = prop("zAxis",  "Vector3"),
		X      = prop("X",      "number"),
		Y      = prop("Y",      "number"),
		Z      = prop("Z",      "number"),
		Magnitude   = prop("Magnitude",   "number"),
		Unit        = prop("Unit",        "Vector3"),
		Dot         = meth("Dot",         "(v: Vector3): number"),
		Cross       = meth("Cross",       "(v: Vector3): Vector3"),
		Lerp        = meth("Lerp",        "(v: Vector3, t: number): Vector3"),
		FuzzyEq     = meth("FuzzyEq",     "(v: Vector3, eps?: number): boolean"),
		Abs         = meth("Abs",         "(): Vector3"),
		Ceil        = meth("Ceil",        "(): Vector3"),
		Floor       = meth("Floor",       "(): Vector3"),
		Sign        = meth("Sign",        "(): Vector3"),
		Max         = meth("Max",         "(v: Vector3): Vector3"),
		Min         = meth("Min",         "(v: Vector3): Vector3"),
		fromNormalId = meth("fromNormalId","(n: Enum.NormalId): Vector3"),
		fromAxis    = meth("fromAxis",    "(a: Enum.Axis): Vector3"),
	}),
	gl("Vector2", "2D vector", {
		new    = meth("new",    "(x, y): Vector2"),
		zero   = prop("zero",   "Vector2"),
		one    = prop("one",    "Vector2"),
		xAxis  = prop("xAxis",  "Vector2"),
		yAxis  = prop("yAxis",  "Vector2"),
		X      = prop("X",      "number"),
		Y      = prop("Y",      "number"),
		Magnitude = prop("Magnitude","number"),
		Unit      = prop("Unit",      "Vector2"),
		Dot       = meth("Dot",       "(v: Vector2): number"),
		Lerp      = meth("Lerp",      "(v: Vector2, t: number): Vector2"),
		Cross     = meth("Cross",     "(v: Vector2): number"),
		FuzzyEq   = meth("FuzzyEq",   "(v: Vector2, eps?: number): boolean"),
		Abs       = meth("Abs",       "(): Vector2"),
		Ceil      = meth("Ceil",      "(): Vector2"),
		Floor     = meth("Floor",     "(): Vector2"),
		Sign      = meth("Sign",      "(): Vector2"),
		Max       = meth("Max",       "(v: Vector2): Vector2"),
		Min       = meth("Min",       "(v: Vector2): Vector2"),
	}),
	gl("CFrame", "Coordinate frame", {
		new         = meth("new",         "(pos?: Vector3, lookAt?: Vector3): CFrame"),
		identity    = prop("identity",    "CFrame"),
		lookAt      = meth("lookAt",      "(from: Vector3, to: Vector3, up?: Vector3): CFrame"),
		fromEulerAnglesXYZ = meth("fromEulerAnglesXYZ","(rx, ry, rz): CFrame"),
		fromEulerAnglesYXZ = meth("fromEulerAnglesYXZ","(rx, ry, rz): CFrame"),
		fromOrientation    = meth("fromOrientation",   "(rx, ry, rz): CFrame"),
		fromAxisAngle      = meth("fromAxisAngle",     "(axis: Vector3, angle: number): CFrame"),
		fromMatrix         = meth("fromMatrix",        "(pos, vX, vY, vZ?): CFrame"),
		Position    = prop("Position",    "Vector3"),
		X           = prop("X",           "number"),
		Y           = prop("Y",           "number"),
		Z           = prop("Z",           "number"),
		LookVector  = prop("LookVector",  "Vector3"),
		RightVector = prop("RightVector", "Vector3"),
		UpVector    = prop("UpVector",    "Vector3"),
		XVector     = prop("XVector",     "Vector3"),
		YVector     = prop("YVector",     "Vector3"),
		ZVector     = prop("ZVector",     "Vector3"),
		Rotation    = prop("Rotation",    "CFrame"),
		Lerp        = meth("Lerp",        "(goal: CFrame, t: number): CFrame"),
		Inverse     = meth("Inverse",     "(): CFrame"),
		ToWorldSpace     = meth("ToWorldSpace",     "(cf: CFrame): CFrame"),
		ToObjectSpace    = meth("ToObjectSpace",    "(cf: CFrame): CFrame"),
		PointToWorldSpace = meth("PointToWorldSpace","(p: Vector3): Vector3"),
		PointToObjectSpace = meth("PointToObjectSpace","(p: Vector3): Vector3"),
		VectorToWorldSpace = meth("VectorToWorldSpace","(v: Vector3): Vector3"),
		VectorToObjectSpace = meth("VectorToObjectSpace","(v: Vector3): Vector3"),
		GetComponents   = meth("GetComponents",   "(): (number x12)"),
		ToEulerAnglesXYZ = meth("ToEulerAnglesXYZ","(): (number, number, number)"),
		ToEulerAnglesYXZ = meth("ToEulerAnglesYXZ","(): (number, number, number)"),
		ToOrientation   = meth("ToOrientation",   "(): (number, number, number)"),
		ToAxisAngle     = meth("ToAxisAngle",     "(): (Vector3, number)"),
		FuzzyEq         = meth("FuzzyEq",         "(cf: CFrame, eps?: number): boolean"),
	}),
	gl("Color3", "RGB color", {
		new          = meth("new",          "(r, g, b): Color3"),
		fromRGB       = meth("fromRGB",       "(r, g, b): Color3"),
		fromHSV       = meth("fromHSV",       "(h, s, v): Color3"),
		fromHex       = meth("fromHex",       "(hex: string): Color3"),
		R            = prop("R",            "number"),
		G            = prop("G",            "number"),
		B            = prop("B",            "number"),
		Lerp         = meth("Lerp",         "(goal: Color3, t: number): Color3"),
		ToHSV        = meth("ToHSV",        "(): (number, number, number)"),
		ToHex        = meth("ToHex",        "(): string"),
	}),
	gl("UDim2", "2D UI dimension", {
		new          = meth("new",          "(xS, xO, yS, yO): UDim2"),
		fromScale     = meth("fromScale",     "(x, y): UDim2"),
		fromOffset    = meth("fromOffset",    "(x, y): UDim2"),
		X            = prop("X",            "UDim"),
		Y            = prop("Y",            "UDim"),
		Width        = prop("Width",        "UDim"),
		Height       = prop("Height",       "UDim"),
		Lerp         = meth("Lerp",         "(goal: UDim2, t: number): UDim2"),
	}),
	gl("UDim", "1D UI dimension", {
		new    = meth("new",    "(scale, offset): UDim"),
		Scale  = prop("Scale",  "number"),
		Offset = prop("Offset", "number"),
	}),
	gl("TweenInfo", "Tween configuration", {
		new = meth("new","(time?, easingStyle?, easingDir?, repeatCount?, reverses?, delayTime?): TweenInfo"),
		Time           = prop("Time",           "number"),
		EasingStyle    = prop("EasingStyle",    "Enum.EasingStyle"),
		EasingDirection = prop("EasingDirection","Enum.EasingDirection"),
		RepeatCount    = prop("RepeatCount",    "number"),
		Reverses       = prop("Reverses",       "boolean"),
		DelayTime      = prop("DelayTime",      "number"),
	}),
	gl("NumberRange", "Min/max number range", {
		new = meth("new","(min: number, max?: number): NumberRange"),
		Min = prop("Min","number"),
		Max = prop("Max","number"),
	}),
	gl("NumberSequence", "Keyframed number curve", {
		new      = meth("new","(n: number | {NumberSequenceKeypoint}): NumberSequence"),
		Keypoints = prop("Keypoints","{ NumberSequenceKeypoint }"),
	}),
	gl("ColorSequence", "Keyframed color curve", {
		new      = meth("new","(c: Color3 | {ColorSequenceKeypoint}): ColorSequence"),
		Keypoints = prop("Keypoints","{ ColorSequenceKeypoint }"),
	}),
	gl("Rect", "2D rectangle", {
		new    = meth("new","(min: Vector2, max: Vector2): Rect"),
		Min    = prop("Min",   "Vector2"),
		Max    = prop("Max",   "Vector2"),
		Width  = prop("Width", "number"),
		Height = prop("Height","number"),
	}),
	gl("Region3", "3D axis-aligned region", {
		new         = meth("new","(min: Vector3, max: Vector3): Region3"),
		CFrame      = prop("CFrame","CFrame"),
		Size        = prop("Size","Vector3"),
		ExpandToGrid = meth("ExpandToGrid","(resolution: number): Region3"),
	}),
	gl("Ray", "3D ray", {
		new       = meth("new","(origin: Vector3, direction: Vector3): Ray"),
		Origin    = prop("Origin",    "Vector3"),
		Direction = prop("Direction", "Vector3"),
		Unit      = prop("Unit",      "Ray"),
		ClosestPoint = meth("ClosestPoint","(p: Vector3): Vector3"),
		Distance     = meth("Distance",    "(p: Vector3): number"),
	}),
	gl("BrickColor", "Named brick color", {
		new     = meth("new","(name: string | number): BrickColor"),
		random  = meth("random","(): BrickColor"),
		White   = meth("White","(): BrickColor"),
		Black   = meth("Black","(): BrickColor"),
		Red     = meth("Red","(): BrickColor"),
		Yellow  = meth("Yellow","(): BrickColor"),
		Blue    = meth("Blue","(): BrickColor"),
		Green   = meth("Green","(): BrickColor"),
		r       = prop("r","number"),
		g       = prop("g","number"),
		b       = prop("b","number"),
		Color   = prop("Color","Color3"),
		Name    = prop("Name","string"),
		Number  = prop("Number","number"),
	}),
}

Grammar.Services = {
	gl("Players", "Players service", {
		LocalPlayer    = prop("LocalPlayer",    "Player"),
		MaxPlayers     = prop("MaxPlayers",     "number"),
		GetPlayers     = meth("GetPlayers",     "(): {Player}"),
		GetPlayerByUserId = meth("GetPlayerByUserId","(id: number): Player?"),
		GetPlayerFromCharacter = meth("GetPlayerFromCharacter","(char: Model): Player?"),
		PlayerAdded    = prop("PlayerAdded",    "RBXScriptSignal"),
		PlayerRemoving = prop("PlayerRemoving", "RBXScriptSignal"),
		CharacterAutoLoads = prop("CharacterAutoLoads","boolean"),
	}),
	gl("Player", "Player instance", {
		Name          = prop("Name",          "string"),
		DisplayName   = prop("DisplayName",   "string"),
		UserId        = prop("UserId",        "number"),
		Team          = prop("Team",          "Team?"),
		TeamColor     = prop("TeamColor",     "BrickColor"),
		Character     = prop("Character",     "Model?"),
		RespawnLocation = prop("RespawnLocation","SpawnLocation?"),
		CameraMinZoomDistance = prop("CameraMinZoomDistance","number"),
		CameraMaxZoomDistance = prop("CameraMaxZoomDistance","number"),
		GetMouse       = meth("GetMouse",       "(): Mouse"),
		Kick           = meth("Kick",           "(msg?: string)"),
		LoadCharacter  = meth("LoadCharacter",  "()"),
		IsInGroup      = meth("IsInGroup",      "(groupId: number): boolean"),
		GetRankInGroup = meth("GetRankInGroup", "(groupId: number): number"),
		HasAppearanceLoaded = meth("HasAppearanceLoaded","(): boolean"),
		GetNetworkPing = meth("GetNetworkPing", "(): number"),
		CharacterAdded    = prop("CharacterAdded",    "RBXScriptSignal"),
		CharacterRemoving = prop("CharacterRemoving", "RBXScriptSignal"),
		CharacterAppearanceLoaded = prop("CharacterAppearanceLoaded","RBXScriptSignal"),
	}),
	gl("Workspace", "3D world container", {
		CurrentCamera      = prop("CurrentCamera",      "Camera"),
		Gravity            = prop("Gravity",            "number"),
		StreamingEnabled   = prop("StreamingEnabled",   "boolean"),
		Raycast            = meth("Raycast",            "(origin, direction, params?): RaycastResult?"),
		Shapecast          = meth("Shapecast",          "(part, displacement, params?): RaycastResult?"),
		Spherecast         = meth("Spherecast",         "(origin, radius, direction, params?): RaycastResult?"),
		Blockcast          = meth("Blockcast",          "(cframe, size, direction, params?): RaycastResult?"),
		GetPartBoundsInBox = meth("GetPartBoundsInBox", "(cframe, size, params?): {BasePart}"),
		GetPartsInPart     = meth("GetPartsInPart",     "(part, params?): {BasePart}"),
		FindPartOnRay      = meth("FindPartOnRay",      "(ray, ignore?, terrainCells?, ignoreWater?): (BasePart?, Vector3, Vector3, Enum.Material)"),
		PGSIsEnabled       = meth("PGSIsEnabled",       "(): boolean"),
	}),
	gl("RunService", "Frame/heartbeat signals", {
		Heartbeat         = prop("Heartbeat",         "RBXScriptSignal"),
		Stepped           = prop("Stepped",           "RBXScriptSignal"),
		RenderStepped     = prop("RenderStepped",     "RBXScriptSignal"),
		PreSimulation     = prop("PreSimulation",     "RBXScriptSignal"),
		PostSimulation    = prop("PostSimulation",    "RBXScriptSignal"),
		PreAnimation      = prop("PreAnimation",      "RBXScriptSignal"),
		PostAnimation     = prop("PostAnimation",     "RBXScriptSignal"),
		IsServer          = meth("IsServer",          "(): boolean"),
		IsClient          = meth("IsClient",          "(): boolean"),
		IsStudio          = meth("IsStudio",          "(): boolean"),
		IsRunning         = meth("IsRunning",         "(): boolean"),
		IsRunMode         = meth("IsRunMode",         "(): boolean"),
		BindToRenderStep  = meth("BindToRenderStep",  "(name, priority, f)"),
		UnbindFromRenderStep = meth("UnbindFromRenderStep","(name: string)"),
	}),
	gl("TweenService", "Tween creation", {
		Create = meth("Create","(inst: Instance, info: TweenInfo, props: {}): Tween"),
	}),
	gl("UserInputService", "Input detection", {
		TouchEnabled     = prop("TouchEnabled",     "boolean"),
		KeyboardEnabled  = prop("KeyboardEnabled",  "boolean"),
		MouseEnabled     = prop("MouseEnabled",     "boolean"),
		GamepadEnabled   = prop("GamepadEnabled",   "boolean"),
		IsKeyDown        = meth("IsKeyDown",        "(key: Enum.KeyCode): boolean"),
		IsMouseButtonPressed = meth("IsMouseButtonPressed","(btn: Enum.UserInputType): boolean"),
		GetMouseLocation = meth("GetMouseLocation", "(): Vector2"),
		GetMouseDelta    = meth("GetMouseDelta",    "(): Vector2"),
		SetNavigationGamepad = meth("SetNavigationGamepad","(gamepadEnum, enabled)"),
		InputBegan       = prop("InputBegan",       "RBXScriptSignal"),
		InputEnded       = prop("InputEnded",       "RBXScriptSignal"),
		InputChanged     = prop("InputChanged",     "RBXScriptSignal"),
	}),
	gl("ReplicatedStorage", "Shared container", instanceMembers),
	gl("ServerStorage",     "Server-only container", instanceMembers),
	gl("ServerScriptService","Server scripts container", instanceMembers),
	gl("StarterGui",        "Client GUI templates", instanceMembers),
	gl("StarterPack",       "Player backpack templates", instanceMembers),
	gl("StarterPlayer",     "Player settings templates", instanceMembers),
	gl("DataStoreService", "Persistent data", {
		GetDataStore        = meth("GetDataStore",        "(name, scope?): DataStore"),
		GetGlobalDataStore  = meth("GetGlobalDataStore",  "(): DataStore"),
		GetOrderedDataStore = meth("GetOrderedDataStore", "(name, scope?): OrderedDataStore"),
		ListDataStoresAsync = meth("ListDataStoresAsync", "(prefix?, pageSize?, cursor?): DataStoreListingPages"),
	}),
	gl("HttpService", "HTTP requests", {
		GetAsync  = meth("GetAsync",  "(url, nocache?, headers?): string"),
		PostAsync = meth("PostAsync", "(url, data, contentType?, compress?, headers?): string"),
		JSONEncode = meth("JSONEncode","(value: any): string"),
		JSONDecode = meth("JSONDecode","(json: string): any"),
		GenerateGUID = meth("GenerateGUID","(wrapInCurlyBraces?: boolean): string"),
		RequestAsync = meth("RequestAsync","(opts: {}): {}"),
		UrlEncode  = meth("UrlEncode",  "(input: string): string"),
	}),
	gl("PathfindingService", "Navigation mesh queries", {
		CreatePath = meth("CreatePath","(agentParams?: {}): Path"),
	}),
	gl("Path", "Computed path", {
		Status          = prop("Status",          "Enum.PathStatus"),
		ComputeAsync    = meth("ComputeAsync",    "(start: Vector3, finish: Vector3)"),
		GetWaypoints    = meth("GetWaypoints",    "(): {PathWaypoint}"),
		Blocked         = prop("Blocked",         "RBXScriptSignal"),
		Unblocked       = prop("Unblocked",       "RBXScriptSignal"),
	}),
	gl("PathWaypoint", "Single path node", {
		new       = meth("new","(pos: Vector3, action: Enum.PathWaypointAction, label?: string): PathWaypoint"),
		Position  = prop("Position",  "Vector3"),
		Action    = prop("Action",    "Enum.PathWaypointAction"),
		Label     = prop("Label",     "string"),
	}),
	gl("CollectionService", "Tag-based grouping", {
		AddTag             = meth("AddTag",             "(inst: Instance, tag: string)"),
		RemoveTag          = meth("RemoveTag",          "(inst: Instance, tag: string)"),
		HasTag             = meth("HasTag",             "(inst: Instance, tag: string): boolean"),
		GetTagged          = meth("GetTagged",          "(tag: string): {Instance}"),
		GetTags            = meth("GetTags",            "(inst: Instance): {string}"),
		GetInstanceAddedSignal   = meth("GetInstanceAddedSignal",   "(tag: string): RBXScriptSignal"),
		GetInstanceRemovedSignal = meth("GetInstanceRemovedSignal", "(tag: string): RBXScriptSignal"),
	}),
	gl("PhysicsService", "Collision group management", {
		RegisterCollisionGroup        = meth("RegisterCollisionGroup",        "(name: string)"),
		UnregisterCollisionGroup      = meth("UnregisterCollisionGroup",      "(name: string)"),
		CollisionGroupsAreCollidable  = meth("CollisionGroupsAreCollidable",  "(g1, g2): boolean"),
		CollisionGroupSetCollidable   = meth("CollisionGroupSetCollidable",   "(g1, g2, collidable)"),
		GetRegisteredCollisionGroups  = meth("GetRegisteredCollisionGroups",  "(): {string}"),
		RenameCollisionGroup          = meth("RenameCollisionGroup",          "(from, to)"),
	}),
	gl("ContextActionService", "Keybind/action binding", {
		BindAction         = meth("BindAction",         "(name, fn, create, ...Enum.KeyCode)"),
		UnbindAction       = meth("UnbindAction",       "(name: string)"),
		BindActionAtPriority = meth("BindActionAtPriority","(name, fn, create, priority, ...Enum.KeyCode)"),
		GetBoundActionInfo = meth("GetBoundActionInfo", "(name: string): {}"),
		GetAllBoundActionInfo = meth("GetAllBoundActionInfo","(): {}"),
	}),
	gl("SoundService", "Global audio settings", {
		PlayLocalSound  = meth("PlayLocalSound",  "(sound: Sound)"),
		GetListener     = meth("GetListener",     "(): (Enum.ListenerType, any)"),
		SetListener     = meth("SetListener",     "(type: Enum.ListenerType, ...)"),
		RespectFilteringEnabled = prop("RespectFilteringEnabled","boolean"),
		VolumeMultiplier = prop("VolumeMultiplier","number"),
	}),
	gl("MarketplaceService", "In-game purchases", {
		PromptProductPurchase     = meth("PromptProductPurchase",     "(player, productId, equipIfPurchased?)"),
		PromptPurchase            = meth("PromptPurchase",            "(player, assetId, equipIfPurchased?)"),
		PromptGamePassPurchase    = meth("PromptGamePassPurchase",    "(player, gamePassId)"),
		PromptPremiumPurchase     = meth("PromptPremiumPurchase",     "(player)"),
		UserOwnsGamePassAsync     = meth("UserOwnsGamePassAsync",     "(userId, gamePassId): boolean"),
		GetProductInfo            = meth("GetProductInfo",            "(id, infoType?): {}"),
		ProcessReceipt            = prop("ProcessReceipt",            "(receiptInfo: {}) -> Enum.ProductPurchaseDecision"),
		PromptProductPurchaseFinished = prop("PromptProductPurchaseFinished","RBXScriptSignal"),
	}),
	gl("Teams", "Team management", {
		GetTeams   = meth("GetTeams","(): {Team}"),
	}),
	gl("Lighting", "World lighting", {
		Brightness        = prop("Brightness",        "number"),
		ClockTime         = prop("ClockTime",         "number"),
		GeographicLatitude = prop("GeographicLatitude","number"),
		GlobalShadows     = prop("GlobalShadows",     "boolean"),
		FogColor          = prop("FogColor",          "Color3"),
		FogEnd            = prop("FogEnd",            "number"),
		FogStart          = prop("FogStart",          "number"),
		Ambient           = prop("Ambient",           "Color3"),
		OutdoorAmbient    = prop("OutdoorAmbient",    "Color3"),
		GetMinutesAfterMidnight = meth("GetMinutesAfterMidnight","(): number"),
		SetMinutesAfterMidnight = meth("SetMinutesAfterMidnight","(minutes: number)"),
	}),
	gl("Camera", "Current scene camera", {
		CFrame          = prop("CFrame",          "CFrame"),
		Focus           = prop("Focus",           "CFrame"),
		CameraType      = prop("CameraType",      "Enum.CameraType"),
		CameraSubject   = prop("CameraSubject",   "Instance?"),
		FieldOfView     = prop("FieldOfView",     "number"),
		ViewportSize    = prop("ViewportSize",    "Vector2"),
		NearPlaneZ      = prop("NearPlaneZ",      "number"),
		DiagonalFieldOfView = prop("DiagonalFieldOfView","number"),
		WorldToScreenPoint    = meth("WorldToScreenPoint",    "(pos: Vector3): (Vector2, boolean, number)"),
		WorldToViewportPoint  = meth("WorldToViewportPoint",  "(pos: Vector3): (Vector2, boolean, number)"),
		ScreenPointToRay      = meth("ScreenPointToRay",      "(x, y, depth?): Ray"),
		ViewportPointToRay    = meth("ViewportPointToRay",    "(x, y, depth?): Ray"),
		GetPartsObscuringTarget = meth("GetPartsObscuringTarget","(castPoints: {Vector3}, ignoreList: {Instance}): {BasePart}"),
	}),
	gl("Animator", "Animation controller", {
		LoadAnimation             = meth("LoadAnimation",             "(anim: Animation): AnimationTrack"),
		GetPlayingAnimationTracks = meth("GetPlayingAnimationTracks", "(): {AnimationTrack}"),
		AnimationPlayed           = prop("AnimationPlayed",           "RBXScriptSignal"),
	}),
}

Grammar.RepclContext = {
	gl("RepclCtx", "Command execution context", {
		Print    = meth("Print",    "(msg: string)"),
		Warn     = meth("Warn",     "(msg: string)"),
		Err      = meth("Err",      "(msg: string)"),
		Error    = meth("Error",    "(msg: string) -- alias for Err"),
		Notify   = meth("Notify",   "(msg: string) -- blue info notification"),
		Reply    = meth("Reply",    "(msg: string)"),
		Abort    = meth("Abort",    "(reason?: string)"),
		Commit   = meth("Commit",   "(payload: any) -- bridge commands only"),
		Args     = prop("Args",     "{ [string]: any }"),
		Flags    = prop("Flags",    "{ [string]: any }"),
		Player   = prop("Player",   "Player"),
		IsServer = prop("IsServer", "boolean"),
	}),
	gl("RepclWin", "Iris window handle", {
		SetTitle    = meth("SetTitle",    "(title: string)"),
		Close       = meth("Close",       "()"),
		Focus       = meth("Focus",       "()"),
		IsOpen      = meth("IsOpen",      "(): boolean"),
		SetSize     = meth("SetSize",     "(size: Vector2)"),
		SetPosition = meth("SetPosition", "(pos: Vector2)"),
	}),
}

Grammar.Snippets = {
	sn("for i",       "for i = 1, ${1:n} do\n\t${2}\nend",              "Numeric for"),
	sn("for pairs",   "for ${1:k}, ${2:v} in pairs(${3:t}) do\n\t${4}\nend", "Pairs loop"),
	sn("for ipairs",  "for ${1:i}, ${2:v} in ipairs(${3:t}) do\n\t${4}\nend","Ipairs loop"),
	sn("function",    "local function ${1:name}(${2})\n\t${3}\nend",    "Local function"),
	sn("method",      "function ${1:obj}:${2:name}(${3})\n\t${4}\nend", "Method"),
	sn("if",          "if ${1:cond} then\n\t${2}\nend",                 "If block"),
	sn("if-else",     "if ${1:cond} then\n\t${2}\nelse\n\t${3}\nend",   "If-else"),
	sn("while",       "while ${1:cond} do\n\t${2}\nend",               "While loop"),
	sn("repeat",      "repeat\n\t${1}\nuntil ${2:cond}",               "Repeat-until"),
	sn("pcall",       "local ok, err = pcall(function()\n\t${1}\nend)", "Protected call"),
	sn("task.spawn",  "task.spawn(function()\n\t${1}\nend)",            "Spawned task"),
	sn("task.delay",  "task.delay(${1:0}, function()\n\t${2}\nend)",    "Delayed task"),
	sn("coroutine",   "local co = coroutine.create(function()\n\t${1}\nend)\ncoroutine.resume(co)", "Coroutine"),
	sn("new Instance","local ${1:inst} = Instance.new(\"${2:ClassName}\")\n${1}.Parent = ${3:parent}", "New instance"),
	sn("connect",     "${1:signal}:Connect(function(${2})\n\t${3}\nend)", "Signal connect"),
	sn("GetService",  "local ${1:svc} = game:GetService(\"${2:ServiceName}\")", "GetService"),
	sn("WaitForChild","local ${1:inst} = ${2:parent}:WaitForChild(\"${3:name}\")", "WaitForChild"),
	sn("type alias",  "export type ${1:Name} = ${2:definition}",        "Type alias"),
	sn("strict",      "--!strict",                                       "Strict mode header"),
	sn("tween",       "local tween = TweenService:Create(${1:inst}, TweenInfo.new(${2:0.3}), {\n\t${3}\n})\ntween:Play()", "Tween"),
}

local index: { [string]: GrammarEntry } = {}

local function addList(list: {GrammarEntry})
	for _, entry in list do
		index[entry.label] = entry
	end
end

addList(Grammar.Keywords)
addList(Grammar.Types)
addList(Grammar.Globals)
addList(Grammar.Libs)
addList(Grammar.Classes)
addList(Grammar.Datatypes)
addList(Grammar.Services)
addList(Grammar.RepclContext)
addList(Grammar.Snippets)

Grammar.Index = index

function Grammar.lookup(name: string): GrammarEntry?
	return index[name]
end

function Grammar.lookupMember(typeName: string, memberName: string): Completion?
	local entry = index[typeName]
	if not entry or not entry.members then return nil end
	return entry.members[memberName]
end

function Grammar.complete(prefix: string, scope: string?): {GrammarEntry}
	local results: {GrammarEntry} = {}
	local lower = string.lower(prefix)
	if scope then
		local entry = index[scope]
		if entry and entry.members then
			for name, member in entry.members do
				if string.lower(string.sub(name, 1, #lower)) == lower then
					table.insert(results, {
						label       = name,
						kind        = member.kind,
						detail      = member.detail,
						documentation = member.documentation,
						insertText  = member.insertText,
						members     = nil,
					})
				end
			end
			return results
		end
	end
	for name, entry in index do
		if string.lower(string.sub(name, 1, #lower)) == lower then
			table.insert(results, entry)
		end
	end
	table.sort(results, function(a, b)
		local ak = a.kind == "keyword" and 0 or a.kind == "snippet" and 1 or 2
		local bk = b.kind == "keyword" and 0 or b.kind == "snippet" and 1 or 2
		if ak ~= bk then return ak < bk end
		return a.label < b.label
	end)
	return results
end

return Grammar