local Req = require(script.Parent.Req)
local Editor = require(script.Parent.Editor)
local Protocol = require(script.Parent.Protocol)
local Iris = require(script.Parent.deps.Iris)

local RunService = game:GetService("RunService")
local IS_CLIENT  = RunService:IsClient()

local Repl = {}

local _onRunCallbacks: {(source: string, result: any) -> ()} = {}
local _context: "Server" | "Client" = "Server"
local _started = false

function Repl.init(_config: any)
	if not IS_CLIENT then return end
	if _started then return end
	_started = true

	Protocol.init(_context)

	Iris.Connect(function()
		Editor.render()
	end)
end

function Repl.open()
	if not IS_CLIENT then return end
	Editor.open()
end

function Repl.close()
	if not IS_CLIENT then return end
	Editor.close()
end

function Repl.setContext(ctx: "Server" | "Client")
	_context = ctx
	if _started then
		Protocol.setContext(ctx)
	end
end

function Repl.onRun(fn: (source: string, result: any) -> ())
	table.insert(_onRunCallbacks, fn)
end

function Repl.fireOnRun(source: string, result: any)
	for _, fn in _onRunCallbacks do
		task.spawn(fn, source, result)
	end
end

return Repl