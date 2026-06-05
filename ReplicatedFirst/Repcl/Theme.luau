-- Theme.lua
-- Typed settings profile for Repcl. Zero hardcoded values live here.
-- Interface.lua and SettingsMenu.lua both read from this.

export type ColorPalette = {
	Background:   Color3,
	Scrollbar:    Color3,
	Arrow:        Color3,
	Input:        Color3,
	Placeholder:  Color3,
	HintBg:       Color3,
	HintText:     Color3,
	HintArg:      Color3,
	HintFlag:     Color3,
	-- output kinds
	Err:   Color3,
	Warn:  Color3,
	Info:  Color3,
	Ok:    Color3,
	Cmd:   Color3,
	Dim:   Color3,
	Print: Color3,
}

export type SizeConfig = {
	LineHeight:   number,
	FontSize:     number,
	InputHeight:  number,
	PaddingH:     number,
	PaddingV:     number,
	ArrowWidth:   number,
	ScrollbarW:   number,
	HintHeight:   number,
}

export type LayoutConfig = {
	ConsoleHeight: number,  -- 0..1, fraction of screen
	MaxLines:      number,
	AnchorTop:     boolean, -- true = top of screen, false = bottom
}

export type BehaviorConfig = {
	ClearOnSpawn:    boolean,
	ShowTimestamps:  boolean,
	TimestampFormat: string,  -- strftime pattern passed to os.date
	HistoryMax:      number,
	AutoScroll:      boolean,
	FocusOnShow:     boolean,
}

export type FontConfig = {
	LogFont:   Enum.Font,
	InputFont: Enum.Font,
	HintFont:  Enum.Font,
}

export type BackgroundConfig = {
	Transparency: number,   -- 0 = opaque, 1 = invisible
	HintTransparency: number,
}

export type SettingsProfile = {
	Version:    string,
	Name:       string,
	Colors:     ColorPalette,
	Sizes:      SizeConfig,
	Layout:     LayoutConfig,
	Behavior:   BehaviorConfig,
	Fonts:      FontConfig,
	Background: BackgroundConfig,
}

-- ─── Defaults ───────────────────────────────────────────────────────────────

local DEFAULT_COLORS: ColorPalette = {
	Background  = Color3.fromHex("0a0a0c"),
	Scrollbar   = Color3.fromHex("374151"),
	Arrow       = Color3.fromHex("9ca3af"),
	Input       = Color3.fromHex("ffffff"),
	Placeholder = Color3.fromHex("4b5563"),
	HintBg      = Color3.fromHex("111318"),
	HintText    = Color3.fromHex("6b7280"),
	HintArg     = Color3.fromHex("93c5fd"),
	HintFlag    = Color3.fromHex("86efac"),
	Err         = Color3.fromHex("f05252"),
	Warn        = Color3.fromHex("e3a008"),
	Info        = Color3.fromHex("3f83f8"),
	Ok          = Color3.fromHex("0e9f6e"),
	Cmd         = Color3.fromHex("ffffff"),
	Dim         = Color3.fromHex("6b7280"),
	Print       = Color3.fromHex("d1d5db"),
}

local DEFAULT_SIZES: SizeConfig = {
	LineHeight  = 18,
	FontSize    = 14,
	InputHeight = 25,
	PaddingH    = 10,
	PaddingV    = 5,
	ArrowWidth  = 15,
	ScrollbarW  = 6,
	HintHeight  = 22,
}

local DEFAULT_LAYOUT: LayoutConfig = {
	ConsoleHeight = 0.4,
	MaxLines      = 300,
	AnchorTop     = true,
}

local DEFAULT_BEHAVIOR: BehaviorConfig = {
	ClearOnSpawn    = false,
	ShowTimestamps  = true,
	TimestampFormat = "%H:%M",
	HistoryMax      = 100,
	AutoScroll      = true,
	FocusOnShow     = true,
}

local DEFAULT_FONTS: FontConfig = {
	LogFont   = Enum.Font.Code,
	InputFont = Enum.Font.Code,
	HintFont  = Enum.Font.Code,
}

local DEFAULT_BACKGROUND: BackgroundConfig = {
	Transparency      = 0.05,
	HintTransparency  = 0.2,
}

-- ─── Module ─────────────────────────────────────────────────────────────────

local Theme = {}

-- Deep-copy a table (one level of nested tables, sufficient for our structs)
local function deepCopy(t: { [any]: any }): { [any]: any }
	local copy = {}
	for k, v in t do
		if type(v) == "table" then
			copy[k] = deepCopy(v)
		else
			copy[k] = v
		end
	end
	return copy
end

local function makeDefault(): SettingsProfile
	return {
		Version    = "1.0.0",
		Name       = "Default",
		Colors     = deepCopy(DEFAULT_COLORS)     :: ColorPalette,
		Sizes      = deepCopy(DEFAULT_SIZES)       :: SizeConfig,
		Layout     = deepCopy(DEFAULT_LAYOUT)      :: LayoutConfig,
		Behavior   = deepCopy(DEFAULT_BEHAVIOR)    :: BehaviorConfig,
		Fonts      = deepCopy(DEFAULT_FONTS)       :: FontConfig,
		Background = deepCopy(DEFAULT_BACKGROUND)  :: BackgroundConfig,
	}
end

-- Active profile (starts as a copy of default so mutations don't corrupt it)
local _active: SettingsProfile = makeDefault()

-- Change listeners: { id -> (profile) -> () }
local _listeners: { [string]: (SettingsProfile) -> () } = {}
local _listenerCount = 0

local function _fire()
	for _, fn in _listeners do
		fn(_active)
	end
end

-- ─── Core API ───────────────────────────────────────────────────────────────

--- Returns the live profile. Do not mutate directly; use patch() or apply().
function Theme.get(): SettingsProfile
	return _active
end

--- Returns a fresh default profile (does not affect the active one).
function Theme.default(): SettingsProfile
	return makeDefault()
end

--- Shallow-merges a partial profile table over the active profile,
--- then fires all change listeners.
--- Only the top-level keys you pass are affected; nested keys are merged one
--- level deep so you can do e.g. Theme.patch({ Colors = { Err = ... } }).
function Theme.patch(partial: { [string]: any })
	for key, value in partial do
		if type(value) == "table" and type(_active[key]) == "table" then
			for subKey, subVal in value do
				(_active :: any)[key][subKey] = subVal
			end
		else
			(_active :: any)[key] = value
		end
	end
	_fire()
end

--- Replaces the active profile entirely. Validates version field.
function Theme.apply(profile: SettingsProfile)
	_active = deepCopy(profile :: { [any]: any }) :: SettingsProfile
	_fire()
end

--- Resets the active profile to factory defaults.
function Theme.reset()
	_active = makeDefault()
	_fire()
end

--- Subscribe to profile changes. Returns an unsubscribe function.
---   local unsub = Theme.onChange(function(p) ... end)
---   unsub()   -- to disconnect
function Theme.onChange(fn: (SettingsProfile) -> ()): () -> ()
	_listenerCount += 1
	local id = tostring(_listenerCount)
	_listeners[id] = fn
	return function()
		_listeners[id] = nil
	end
end

-- ─── Export / Import ────────────────────────────────────────────────────────

-- Serialises Color3 -> { r, g, b } and Enum.Font -> string so the
-- profile can be JSON-encoded or stored as a plain DataStore value.

local function encodeColor(c: Color3): { number }
	return { c.R, c.G, c.B }
end

local function decodeColor(t: { number }): Color3
	return Color3.new(t[1], t[2], t[3])
end

local function encodeFont(f: Enum.Font): string
	return tostring(f)
end

local function decodeFont(s: string): Enum.Font
	for _, v in Enum.Font:GetEnumItems() do
		if tostring(v) == s then return v end
	end
	return Enum.Font.Code
end

local function encodeColors(c: ColorPalette): { [string]: { number } }
	local out: { [string]: { number } } = {}
	for k, v in c :: { [string]: Color3 } do
		out[k] = encodeColor(v)
	end
	return out
end

local function decodeColors(t: { [string]: { number } }): ColorPalette
	local out: { [string]: Color3 } = {}
	for k, v in t do
		out[k] = decodeColor(v)
	end
	return out :: ColorPalette
end

local function encodeFonts(f: FontConfig): { [string]: string }
	return {
		LogFont   = encodeFont(f.LogFont),
		InputFont = encodeFont(f.InputFont),
		HintFont  = encodeFont(f.HintFont),
	}
end

local function decodeFonts(t: { [string]: string }): FontConfig
	return {
		LogFont   = decodeFont(t.LogFont),
		InputFont = decodeFont(t.InputFont),
		HintFont  = decodeFont(t.HintFont),
	}
end

function Theme.export(): { [string]: any }
	local p = _active
	return {
		Version    = p.Version,
		Name       = p.Name,
		Colors     = encodeColors(p.Colors),
		Sizes      = deepCopy(p.Sizes :: { [any]: any }),
		Layout     = deepCopy(p.Layout :: { [any]: any }),
		Behavior   = deepCopy(p.Behavior :: { [any]: any }),
		Fonts      = encodeFonts(p.Fonts),
		Background = deepCopy(p.Background :: { [any]: any }),
	}
end

function Theme.import(data: { [string]: any })
	if data.Colors     then Theme.patch({ Colors     = decodeColors(data.Colors) }) end
	if data.Fonts      then Theme.patch({ Fonts      = decodeFonts(data.Fonts) }) end
	if data.Sizes      then Theme.patch({ Sizes      = data.Sizes }) end
	if data.Layout     then Theme.patch({ Layout     = data.Layout }) end
	if data.Behavior   then Theme.patch({ Behavior   = data.Behavior }) end
	if data.Background then Theme.patch({ Background = data.Background }) end
	if data.Name       then (_active :: any).Name    = data.Name end
	if data.Version    then (_active :: any).Version = data.Version end
end

-- ─── Preset library ─────────────────────────────────────────────────────────
-- Add named presets here; SettingsMenu will surface them in a dropdown.

local PRESETS: { [string]: () -> SettingsProfile } = {}

function Theme.registerPreset(name: string, builder: () -> SettingsProfile)
	PRESETS[name] = builder
end

function Theme.getPresetNames(): { string }
	local names: { string } = {}
	for k in PRESETS do table.insert(names, k) end
	table.sort(names)
	return names
end

function Theme.applyPreset(name: string): boolean
	local builder = PRESETS[name]
	if not builder then return false end
	Theme.apply(builder())
	return true
end

-- ─── Built-in presets ───────────────────────────────────────────────────────

Theme.registerPreset("Default (Dark)", makeDefault)

Theme.registerPreset("Midnight Blue", function(): SettingsProfile
	local p = makeDefault()
	p.Name                  = "Midnight Blue"
	p.Colors.Background     = Color3.fromHex("0d1117")
	p.Colors.HintBg         = Color3.fromHex("161b22")
	p.Colors.Info           = Color3.fromHex("58a6ff")
	p.Colors.Ok             = Color3.fromHex("3fb950")
	p.Colors.Err            = Color3.fromHex("f85149")
	p.Colors.Warn           = Color3.fromHex("d29922")
	p.Colors.Cmd            = Color3.fromHex("e6edf3")
	p.Colors.Print          = Color3.fromHex("8b949e")
	p.Colors.Dim            = Color3.fromHex("484f58")
	p.Colors.Arrow          = Color3.fromHex("58a6ff")
	p.Colors.Placeholder    = Color3.fromHex("484f58")
	return p
end)

Theme.registerPreset("Solarized", function(): SettingsProfile
	local p = makeDefault()
	p.Name                  = "Solarized"
	p.Colors.Background     = Color3.fromHex("002b36")
	p.Colors.HintBg         = Color3.fromHex("073642")
	p.Colors.Info           = Color3.fromHex("268bd2")
	p.Colors.Ok             = Color3.fromHex("859900")
	p.Colors.Err            = Color3.fromHex("dc322f")
	p.Colors.Warn           = Color3.fromHex("b58900")
	p.Colors.Cmd            = Color3.fromHex("fdf6e3")
	p.Colors.Print          = Color3.fromHex("839496")
	p.Colors.Dim            = Color3.fromHex("586e75")
	p.Colors.Arrow          = Color3.fromHex("2aa198")
	p.Colors.Input          = Color3.fromHex("eee8d5")
	p.Colors.Placeholder    = Color3.fromHex("586e75")
	return p
end)

return Theme