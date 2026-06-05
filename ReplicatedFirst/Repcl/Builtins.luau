local Req      = require(script.Parent.Req)
local Registry = require(script.Parent.Registry)

local IS_CLIENT = game:GetService("RunService"):IsClient()

local Builtins = {}

function Builtins.register()

	Registry.register({
		Name        = "help",
		Aliases     = { "h", "?" },
		Description = "list all registered commands",
		Context     = "Client",
		Permission  = "User",
		Args        = {},
		Flags       = {},
		Run = function(ctx)
			local all = Registry.getAll()
			-- Sort alphabetically for readability
			table.sort(all, function(a, b) return a.Name:lower() < b.Name:lower() end)
			ctx.Print("commands (" .. #all .. "):")
			for _, def in all do
				-- Build "name | alias1 | alias2" heading
				local nameStr = def.Name
				if def.Aliases and #def.Aliases > 0 then
					nameStr = nameStr .. " | " .. table.concat(def.Aliases, " | ")
				end
				ctx.Print(string.format("  %-32s %-10s %s",
					nameStr,
					"(" .. (def.Context or "?"):lower() .. ")",
					def.Description or ""))
			end
		end,
	})

	Registry.register({
		Name        = "clear",
		Aliases     = { "cls", "cl" },
		Description = "clear the console",
		Context     = "Client",
		Permission  = "User",
		Args        = {},
		Flags       = {},
		Run = function(_ctx)
			Req.get("Interface").clearLocal()
		end,
	})

	Registry.register({
		Name        = "repl",
		Aliases     = { "r" },
		Description = "open the REPL editor",
		Context     = "Client",
		Permission  = "User",
		Args        = {},
		Flags       = {
			{ Name = "server", Short = "s", Description = "execute in server context" },
		},
		Run = function(ctx)
			if not IS_CLIENT then ctx.Err("repl is client-only"); return end
			local Repl = Req.get("Repl")
			Repl.setContext(ctx.Flags.server and "Server" or "Client")
			Repl.open()
			ctx.Reply("opening repl...")
		end,
	})

	Registry.register({
		Name        = "version",
		Aliases     = { "v", "ver" },
		Description = "show version info",
		Context     = "Client",
		Permission  = "User",
		Args        = {},
		Flags       = {},
		Run = function(ctx)
			ctx.Print("Repcl v0.1.0")
		end,
	})

	Registry.register({
		Name        = "players",
		Aliases     = { "pl", "plist" },
		Description = "list connected players",
		Context     = "Client",
		Permission  = "User",
		Args        = {},
		Flags       = {
			{ Name = "verbose", Short = "v", Description = "show ping and userId" },
		},
		Run = function(ctx)
			local Players = game:GetService("Players")
			local all     = Players:GetPlayers()
			ctx.Print(string.format("players (%d/%d):", #all, Players.MaxPlayers))
			for _, p in all do
				if ctx.Flags.verbose then
					local ping = math.floor(p:GetNetworkPing() * 1000)
					ctx.Print(string.format("  %-24s uid:%-14d %dms", p.Name, p.UserId, ping))
				else
					ctx.Print("  " .. p.Name)
				end
			end
		end,
	})

	Registry.register({
		Name        = "echo",
		Aliases     = { "e" },
		Description = "echo text back",
		Context     = "Client",
		Permission  = "User",
		Args        = {
			{ Name = "text", Types = { "String" }, Required = true },
		},
		Flags = {},
		Run = function(ctx)
			ctx.Reply(tostring(ctx.Args.text))
		end,
	})

	Registry.register({
		Name        = "list",
		Aliases     = { "ls" },
		Description = "list children at path",
		Context     = "Client",
		Permission  = "User",
		Args        = {
			{ Name = "path", Types = { "String" }, Required = false },
		},
		Flags = {},
		Run = function(ctx)
			local path  = ctx.Args.path or "game"
			local split = string.split(path:lower(), ".")

			local current: Instance = game
			for _, part in ipairs(split) do
				if part == "" or part == "game" then continue end
				local next = current:FindFirstChild(part)
				if not next then
					ctx.Err("invalid path segment: " .. part)
					return
				end
				current = next
			end

			local children = current:GetChildren()
			local count    = #children

			if count == 0 then
				ctx.Print("(empty)")
				return
			end

			local maxLen = 4
			for _, child in ipairs(children) do
				if #child.Name > maxLen then maxLen = #child.Name end
			end

			local function pad(s: string, n: number): string
				local diff = n - #s
				return diff > 0 and (s .. string.rep(" ", diff)) or s
			end

			local sep = string.rep("-", maxLen) .. "   " .. string.rep("-", 15)
			ctx.Print(pad("Name", maxLen) .. "   ClassName")
			ctx.Print(sep)
			for _, child in ipairs(children) do
				ctx.Print(pad(child.Name, maxLen) .. "   " .. child.ClassName)
			end
			ctx.Print(sep)
			ctx.Print("total: " .. count)
		end,
	})

	-- Bridge test: client collects a payload, server echoes it back
	Registry.register({
		Name        = "ping",
		Aliases     = { "pg" },
		Description = "bridge test — client sends timestamp, server replies",
		Context     = "Bridge",
		Permission  = "User",
		Args        = {
			{ Name = "message", Types = { "String" }, Required = false, Default = "ping" },
		},
		Flags = {
			{ Name = "verbose", Short = "v", Description = "include server tick in reply" },
		},
		Client = function(ctx)
			local payload = {
				message = ctx.Args.message,
				sentAt  = os.clock(),
				verbose = ctx.Flags.verbose,
			}
			ctx.Notify("sending to server: " .. tostring(payload.message))
			ctx.Commit(payload)
		end,
		Server = function(ctx)
			-- payload comes through ctx.Args when routed via runServerBridge
			local payload = ctx.Args
			local elapsed = os.clock() - (payload.sentAt or 0)
			local msg = string.format("pong — '%s' (%.1fms round-trip)",
				tostring(payload.message), elapsed * 1000)
			if payload.verbose then
				msg = msg .. string.format("  |  server tick: %.4f", os.clock())
			end
			ctx.Print(msg)
		end,
	})

	Registry.register({
		Name        = "num",
		Aliases     = { "n" },
		Description = "push a number onto the stack and print it  (stack test)",
		Context     = "Client",
		Permission  = "User",
		Args        = {
			{ Name = "value", Types = { "Number" }, Required = true },
		},
		Flags = {
			{ Name = "silent", Short = "s", Description = "push without printing" },
		},
		Run = function(ctx)
			local v = ctx.Args.value
			if not ctx.Flags.silent then
				ctx.Print("num: " .. tostring(v))
			end
			return v
		end,
	})

	Registry.register({
		Name        = "add",
		Aliases     = { "+" },
		Description = "pop top two stack values and print their sum  (stack test)",
		Context     = "Client",
		Permission  = "User",
		Args        = {
			{ Name = "a", Types = { "Number" }, Required = false },
			{ Name = "b", Types = { "Number" }, Required = false },
		},
		Flags = {},
		Run = function(ctx)
			local a = ctx.Args.a
			local b = ctx.Args.b
			if a == nil or b == nil then
				ctx.Err("add requires two numbers — pipe two `num` calls or pass args directly")
				return
			end
			local result = a + b
			ctx.Print(string.format("%s + %s = %s", tostring(a), tostring(b), tostring(result)))
			return result
		end,
	})

	Registry.register({
		Name        = "stackdump",
		Aliases     = { "sd" },
		Description = "print current stack refs in a chain  (stack test)",
		Context     = "Client",
		Permission  = "User",
		Args        = {
			{ Name = "ref", Types = { "String" }, Required = false, Default = "_1" },
		},
		Flags = {},
		Run = function(ctx)
			ctx.Print("stack ref resolved to: " .. tostring(ctx.Args.ref))
			return ctx.Args.ref
		end,
	})

	Registry.register({
		Name        = "REPL",
		Aliases     = { "rp" },
		Description = "open the interactive script editor",
		Context     = "Client",
		Permission  = "User",
		Args        = {
			{ Name = "FileName", Types = { "String" }, Required = false, Default = "QuickEdit" },
		},
		Flags = {
			{ Name = "server", Short = "s", Description = "open REPL in server context" },
		},
		Run = function(ctx)
			local Repl      = require(script.Parent.Repl)
			local Interface = require(script.Parent.Interface)
			Interface.hide()
			Repl.open()
			if ctx.Flags.server then
				Repl.setContext("Server")
			end
		end,
	})

	Registry.register({
		Name        = "math",
		Aliases     = { "m" },
		Description = "perform a math operation on the given terms",
		Context     = "Client",
		Permission  = "User",
		Args        = {
			{ Name = "Operation", Types = { "String" }, Required = true },
			{ Name = "Terms",     Types = { "Number"  }, Required = true, Variadic = true },
		},
		Flags = {},
		Run = function(ctx)
			local operation = ctx.Args.Operation
			local terms     = ctx.Args.Terms

			if type(terms) ~= "table" or #terms == 0 then
				ctx.Err("math requires at least one term")
				return
			end

			local result = terms[1]
			for i = 2, #terms do
				local n = terms[i]
				if     operation == "+"          then result = result + n
				elseif operation == "-"          then result = result - n
				elseif operation == "*"          then result = result * n
				elseif operation == "/"          then result = result / n
				elseif operation == "^"
					or operation == "**"         then result = result ^ n
				elseif operation == "%"          then result = result % n
				elseif operation == "//"         then result = math.floor(result / n)
				else ctx.Err("invalid operation: " .. operation); return
				end
			end

			ctx.Print("Result: " .. tostring(result))
			return result
		end,
	})

	Registry.register({
		Name        = "settings",
		Aliases     = { "config", "sets", "cfg", "man", "manifest", "ss" },
		Description = "open the settings menu",
		Context     = "Client",
		Args        = {},
		Flags       = {},
		Run = function(_ctx)
			local Sets      = require(script.Parent.SettingsMenu)
			local Interface = require(script.Parent.Interface)
			Interface.hide()
			Sets.open()
		end,
	})

	Registry.register({
		Name        = "credit",
		Aliases     = { "cred", "cc", "cont" },
		Description = "list credits",
		Context     = "Client",
		Args        = {},
		Flags       = {},
		Run = function(ctx)
			ctx.Print("Kr3ative -- (Creator)")
		end,
	})

end

return Builtins