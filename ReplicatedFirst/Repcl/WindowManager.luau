--!strict

local Types = require(script.Parent.Types)
type WindowFn = Types.WindowFn

local IS_CLIENT = game:GetService("RunService"):IsClient()

local Iris: any = nil

type WindowEntry = {
	id:          string,
	fn:          WindowFn,
	commandName: string?,
	visible:     boolean,
	values:      { [string]: any },
}

local windows:    { [string]: WindowEntry } = {}
local registered: { string }                = {}

local WindowManager = {}

function WindowManager.init()
	windows    = {}
	registered = {}

	if not IS_CLIENT then return end

	Iris = require(script.Parent.deps.Iris)
	
	Iris:Connect(function()
		for _, id in registered do
			local entry = windows[id]
			if entry and entry.visible then
				WindowManager._renderWindow(entry)
			end
		end
	end)
end

function WindowManager.register(id: string, fn: WindowFn)
	local Registry = require(script.Parent.Registry)
	local cmdDef   = Registry.get(id)

	if windows[id] then
		windows[id].fn          = fn
		windows[id].commandName = cmdDef and cmdDef.Name or nil
		return
	end

	windows[id] = {
		id          = id,
		fn          = fn,
		commandName = cmdDef and cmdDef.Name or nil,
		visible     = false,
		values      = {},
	}
	table.insert(registered, id)
end

function WindowManager.show(id: string)
	assert(IS_CLIENT, "[Repcl:WindowManager] show must be called from client")
	if not windows[id] then warn("[Repcl:WindowManager] no window registered:", id); return end
	windows[id].visible = true
end

function WindowManager.hide(id: string)
	assert(IS_CLIENT, "[Repcl:WindowManager] hide must be called from client")
	if not windows[id] then return end
	windows[id].visible = false
end

local function buildController(entry: WindowEntry): any
	local win       = {}
	local outputLog: { string } = {}

	win.Input = function(name: string, _types: { string })
		local state = Iris.State(entry.values[name] or "")
		local w     = Iris.InputText({ name }, { text = state })
		if w.state.text.value ~= (entry.values[name] or "") then
			entry.values[name] = w.state.text.value
		end
		return w
	end

	win.Dropdown = function(name: string, options: { string })
		local idx   = Iris.State(1)
		local w     = Iris.ComboArray({ name, options }, { index = idx })
		if w.state.index.value then
			entry.values[name] = options[w.state.index.value]
		end
		return w
	end

	win.Checkbox = function(name: string, label: string)
		local state = Iris.State(entry.values[name] == true)
		local w     = Iris.Checkbox({ label }, { isChecked = state })
		entry.values[name] = w.state.isChecked.value
		return w
	end

	win.Slider = function(name: string, min: number, max: number, default: number)
		local state = Iris.State(entry.values[name] or default)
		local w     = Iris.SliderNum({ name, 1, min, max }, { number = state })
		entry.values[name] = w.state.number.value
		return w
	end

	win.ColorPicker = function(name: string, label: string)
		local state = Iris.State(entry.values[name] or Color3.new(1, 1, 1))
		local w     = Iris.InputColor3({ label }, { color = state })
		entry.values[name] = w.state.color.value
		return w
	end

	win.MultiInput = function(name: string, types: { string })
		return win.Input(name, types)
	end

	win.Text = function(content: string)
		Iris.Text({ content })
	end

	win.Label = function(key: string, value: string)
		Iris.SameLine()
		Iris.Text({ key .. ": " })
		Iris.Text({ value })
		-- Fixed: Removed broken Iris.End() here
	end

	win.Separator = function()
		Iris.Separator()
	end

	win.Output = function()
		-- Fixed: Swapped broken BeginChild context for a clean natural text feed block
		Iris.Separator()
		for _, line in outputLog do
			Iris.Text({ line })
		end
	end

	win.Table = function(headers: { string }, rows: { { string } })
		Iris.Table({ #headers, false, false })
		for _, h in headers do
			Iris.Text({ h })
			Iris.NextColumn()
		end
		Iris.Separator()
		for _, row in rows do
			for _, cell in row do
				Iris.Text({ cell })
				Iris.NextColumn()
			end
		end
		Iris.End()
	end

	win.Tree = function(label: string, fn: () -> ())
		local t = Iris.Tree({ label })
		if t.state.isUncollapsed.value then
			fn()
		end
		Iris.End()
	end

	win.Indent = function(fn: () -> ())
		Iris.Indent()
		fn()
		Iris.Unindent()
	end

	win.Button = function(label: string, fn: (vals: { [string]: any }) -> ())
		if Iris.Button({ label }).clicked() then
			if entry.commandName then
				local Auth    = require(script.Parent.AuthManager)
				local Players = game:GetService("Players")
				local player  = Players.LocalPlayer
				local granted, reason = Auth.check(player, entry.commandName)
				if not granted then
					table.insert(outputLog, "[auth] " .. reason)
					return
				end
			end
			local ok, err = pcall(fn, entry.values)
			if not ok then
				table.insert(outputLog, "[err] " .. tostring(err))
			end
		end
	end

	win.Tooltip = function(text: string)
		Iris.Text({ text })
	end

	win.Get = function(name: string): any
		return entry.values[name]
	end

	win.Set = function(name: string, value: any)
		entry.values[name] = value
	end

	win.OnChange = function(_name: string, _fn: (value: any) -> ())
	end

	return win
end

function WindowManager._renderWindow(entry: WindowEntry)
	local openState = Iris.State(true)
	local w         = Iris.Window(
		{ entry.id, false, false, false, false, false, false, false },
		{ isOpened = openState }
	)

	if not w.state.isOpened.value then
		entry.visible = false
		Iris.End()
		return
	end

	local controller = buildController(entry)
	local ok, err    = pcall(entry.fn, controller)
	if not ok then
		Iris.Text({ "[Repcl:WindowManager] error: " .. tostring(err) })
	end

	Iris.End()
end

return WindowManager