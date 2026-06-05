-- SettingsMenu.lua
-- Iris 2.x settings panel for Repcl.
-- Client-only. Summon via SettingsMenu.open() / .close() / .toggle().

local Iris  = require(script.Parent.deps.Iris)
local Theme = require(script.Parent.Theme)

type SettingsProfile = Theme.SettingsProfile

-- ─── State ───────────────────────────────────────────────────────────────────

local _open  = false
local _stage: SettingsProfile = nil :: any

local _presetIdx    = Iris.State(1)
local _presetNames: { string } = {}
local _exportText   = Iris.State("")
local _importText   = Iris.State("")
local _importStatus = Iris.State("")

-- ─── Section renderers ───────────────────────────────────────────────────────

local function renderColors()
	Iris.CollapsingHeader({ "Colors" })
	Iris.Indent()

	local c = _stage.Colors

	local function col(label: string, key: string)
		local state = Iris.TableState(c, key)
		Iris.InputColor3({ label }, { color = state })
		if state.value ~= (c :: any)[key] then
			Theme.patch({ Colors = { [key] = state.value } })
		end
	end

	Iris.Text({ "Output kinds" })
	col("Error",   "Err")
	col("Warning", "Warn")
	col("Info",    "Info")
	col("OK",      "Ok")
	col("Command", "Cmd")
	col("Dim",     "Dim")
	col("Print",   "Print")

	Iris.Separator()
	Iris.Text({ "UI chrome" })
	col("Background",  "Background")
	col("Scrollbar",   "Scrollbar")
	col("Arrow",       "Arrow")
	col("Input text",  "Input")
	col("Placeholder", "Placeholder")
	col("Hint bg",     "HintBg")
	col("Hint text",   "HintText")
	col("Hint arg",    "HintArg")
	col("Hint flag",   "HintFlag")

	Iris.End() -- Indent
	Iris.End() -- CollapsingHeader
end

local function renderSizes()
	Iris.CollapsingHeader({ "Sizes" })
	Iris.Indent()

	local sz = _stage.Sizes

	local function intField(label: string, key: string, min: number, max: number)
		local state = Iris.TableState(sz, key)
		Iris.DragNum({ label, 1, min, max }, { number = state })
		local v = math.clamp(math.round(state.value), min, max)
		if v ~= (sz :: any)[key] then
			Theme.patch({ Sizes = { [key] = v } })
		end
	end

	intField("Line height",     "LineHeight",  10, 40)
	intField("Font size",       "FontSize",     8, 28)
	intField("Input height",    "InputHeight", 16, 50)
	intField("Padding H",       "PaddingH",     0, 30)
	intField("Padding V",       "PaddingV",     0, 20)
	intField("Arrow width",     "ArrowWidth",   8, 30)
	intField("Scrollbar width", "ScrollbarW",   2, 16)
	intField("Hint height",     "HintHeight",  12, 40)

	Iris.End() -- Indent
	Iris.End() -- CollapsingHeader
end

local function renderLayout()
	Iris.CollapsingHeader({ "Layout" })
	Iris.Indent()

	local l = _stage.Layout

	local hState = Iris.TableState(l, "ConsoleHeight")
	Iris.SliderNum({ "Console height", 0.01, 0.1, 0.9 }, { number = hState })
	if math.abs(hState.value - l.ConsoleHeight) > 0.001 then
		Theme.patch({ Layout = { ConsoleHeight = hState.value } })
	end

	local anchorState = Iris.TableState(l, "AnchorTop")
	Iris.Checkbox({ "Anchor to top" }, { isChecked = anchorState })
	if anchorState.value ~= l.AnchorTop then
		Theme.patch({ Layout = { AnchorTop = anchorState.value } })
	end

	local maxState = Iris.TableState(l, "MaxLines")
	Iris.DragNum({ "Max lines", 10, 50, 2000 }, { number = maxState })
	local mv = math.clamp(math.round(maxState.value), 50, 2000)
	if mv ~= l.MaxLines then
		Theme.patch({ Layout = { MaxLines = mv } })
	end

	Iris.End() -- Indent
	Iris.End() -- CollapsingHeader
end

local function renderBehavior()
	Iris.CollapsingHeader({ "Behavior" })
	Iris.Indent()

	local b = _stage.Behavior

	local function checkbox(label: string, key: string)
		local state = Iris.TableState(b, key)
		Iris.Checkbox({ label }, { isChecked = state })
		if state.value ~= (b :: any)[key] then
			Theme.patch({ Behavior = { [key] = state.value } })
		end
	end

	checkbox("Show timestamps", "ShowTimestamps")
	checkbox("Auto-scroll",     "AutoScroll")
	checkbox("Focus on show",   "FocusOnShow")
	checkbox("Clear on spawn",  "ClearOnSpawn")

	local histState = Iris.TableState(b, "HistoryMax")
	Iris.DragNum({ "History max", 1, 10, 500 }, { number = histState })
	local hv = math.clamp(math.round(histState.value), 10, 500)
	if hv ~= b.HistoryMax then
		Theme.patch({ Behavior = { HistoryMax = hv } })
	end

	Iris.End() -- Indent
	Iris.End() -- CollapsingHeader
end

local FONT_OPTIONS = {
	Enum.Font.Code,
	Enum.Font.RobotoMono,
	Enum.Font.Michroma,
	Enum.Font.IndieFlower,
	Enum.Font.SourceSansBold,
	Enum.Font.Gotham,
}
local FONT_LABELS: { string } = {}
for _, f in FONT_OPTIONS do
	table.insert(FONT_LABELS, f.Name)
end

local function fontDropdown(label: string, current: Enum.Font, onChange: (Enum.Font) -> ())
	local idx = 1
	for i, f in FONT_OPTIONS do
		if f == current then idx = i; break end
	end
	local state = Iris.State(idx)
	Iris.Combo({ label }, { index = state, selectionList = FONT_LABELS })
	Iris.End() -- [FIXED] Combo requires an End() even with selectionList

	if state.value ~= idx then
		onChange(FONT_OPTIONS[state.value] or Enum.Font.Code)
	end
end

local function renderFonts()
	Iris.CollapsingHeader({ "Fonts" })
	Iris.Indent()

	local f = _stage.Fonts

	fontDropdown("Log font", f.LogFont, function(v)
		f.LogFont = v
		Theme.patch({ Fonts = { LogFont = v } })
	end)

	fontDropdown("Input font", f.InputFont, function(v)
		f.InputFont = v
		Theme.patch({ Fonts = { InputFont = v } })
	end)

	fontDropdown("Hint font", f.HintFont, function(v)
		f.HintFont = v
		Theme.patch({ Fonts = { HintFont = v } })
	end)

	Iris.End()
	Iris.End()
end

local function renderBackground()
	Iris.CollapsingHeader({ "Background" })
	Iris.Indent()

	local bg = _stage.Background

	local tState = Iris.TableState(bg, "Transparency")
	Iris.SliderNum({ "Transparency", 0.01, 0, 1 }, { number = tState })
	if math.abs(tState.value - bg.Transparency) > 0.001 then
		Theme.patch({ Background = { Transparency = tState.value } })
	end

	local htState = Iris.TableState(bg, "HintTransparency")
	Iris.SliderNum({ "Hint transparency", 0.01, 0, 1 }, { number = htState })
	if math.abs(htState.value - bg.HintTransparency) > 0.001 then
		Theme.patch({ Background = { HintTransparency = htState.value } })
	end

	Iris.End()
	Iris.End()
end

local function renderPresets()
	Iris.CollapsingHeader({ "Presets" })
	Iris.Indent()

	_presetNames = Theme.getPresetNames()
	if #_presetNames == 0 then
		Iris.Text({ "No presets registered." })
	else
		Iris.Combo({ "Preset" }, { index = _presetIdx, selectionList = _presetNames })
		Iris.End()

		if Iris.Button({ "Apply preset" }).clicked() then
			local name = _presetNames[_presetIdx.value]
			if name then
				Theme.applyPreset(name)
				_stage = Theme.get()
			end
		end
	end

	Iris.SameLine()
	if Iris.Button({ "Reset to default" }).clicked() then
		Theme.reset()
		_stage = Theme.get()
	end
	Iris.End()

	Iris.End()
	Iris.End()
end

local function renderExportImport()
	Iris.CollapsingHeader({ "Export / Import" })
	Iris.Indent()

	Iris.Text({ "Export" })
	if Iris.Button({ "Generate export string" }).clicked() then
		local ok, result = pcall(function()
			return game:GetService("HttpService"):JSONEncode(Theme.export())
		end)
		_exportText:set(ok and result or ("error: " .. tostring(result)))
	end

	if _exportText.value ~= "" then
		local it = Iris.InputText({ "", nil, false }, { text = _exportText })
		local inst = it.Instance
		Iris.Separator()
		Iris.Text({ "Copy the string above to save your profile." })
	end

	Iris.Separator()

	Iris.Text({ "Import" })
	Iris.InputText({ "Paste JSON here##importin" }, { text = _importText })

	if Iris.Button({ "Apply import" }).clicked() then
		local raw = _importText.value
		if raw == "" then
			_importStatus:set("Nothing to import.")
		else
			local ok, data = pcall(function()
				return game:GetService("HttpService"):JSONDecode(raw)
			end)
			if not ok then
				_importStatus:set("JSON parse error: " .. tostring(data))
			else
				local applyOk, applyErr = pcall(Theme.import, data)
				if applyOk then
					_stage = Theme.get()
					_importStatus:set("Imported successfully.")
					_importText:set("")
				else
					_importStatus:set("Import error: " .. tostring(applyErr))
				end
			end
		end
	end

	if _importStatus.value ~= "" then
		Iris.Text({ _importStatus.value })
	end

	Iris.End()
	Iris.End()
end

local function renderMenu()
	if not _open then return end

	local openState = Iris.State(true)
	Iris.Window({ "Repcl Settings", [Iris.Args.Window.NoCollapse] = false }, { isOpened = openState })

	if not openState.value then
		_open = false
		Iris.End()
		return
	end

	Iris.InputText({ "Profile name" }, { text = Iris.TableState(_stage, "Name") })
	Iris.Separator()

	renderColors()
	renderSizes()
	renderLayout()
	renderBehavior()
	renderFonts()
	renderBackground()
	renderPresets()
	renderExportImport()

	Iris.End()
end

local SettingsMenu = {}

function SettingsMenu.init()
	_stage = Theme.get()
	Iris:Connect(renderMenu)
end

function SettingsMenu.open()
	_open  = true
	_stage = Theme.get()
end

function SettingsMenu.close()
	_open = false
end

function SettingsMenu.toggle()
	if _open then SettingsMenu.close() else SettingsMenu.open() end
end

function SettingsMenu.isOpen(): boolean
	return _open
end

function SettingsMenu.exportProfile(): { [string]: any }
	return Theme.export()
end

function SettingsMenu.importProfile(data: { [string]: any }): (boolean, string)
	local ok, err = pcall(Theme.import, data)
	if ok then
		_stage = Theme.get()
		return true, "ok"
	end
	return false, tostring(err)
end

return SettingsMenu