--!strict

local TypeSystem = require(script.Parent.TypeSystem)

local BuiltinTypes = {}

function BuiltinTypes.register()

	TypeSystem.define("String", {
		Parse = function(raw: string): string
			return raw
		end,
		Validate = function(value: any): boolean | string
			return type(value) == "string" or "expected string"
		end,
		Autocomplete = function(_raw: string): { any }
			return {}
		end,
		Display = function(value: any): string
			return tostring(value)
		end,
		Multi = false, Delimiter = nil, Searchable = false,
	})

	TypeSystem.define("Number", {
		Parse = function(raw: string): number?
			return tonumber(raw)
		end,
		Validate = function(value: any): boolean | string
			return type(value) == "number" or "expected number"
		end,
		Autocomplete = function(_raw: string): { any }
			return {}
		end,
		Display = function(value: any): string
			return tostring(value)
		end,
		Multi = false, Delimiter = nil, Searchable = false,
	})

	TypeSystem.define("Integer", {
		Parse = function(raw: string): number?
			local n = tonumber(raw)
			return n and math.floor(n) or nil
		end,
		Validate = function(value: any): boolean | string
			return type(value) == "number" or "expected integer"
		end,
		Autocomplete = function(_raw: string): { any }
			return {}
		end,
		Display = function(value: any): string
			return tostring(value)
		end,
		Multi = false, Delimiter = nil, Searchable = false,
	})

	TypeSystem.define("Boolean", {
		Parse = function(raw: string): boolean?
			local l = raw:lower()
			if l == "true"  or l == "yes" or l == "1" then return true  end
			if l == "false" or l == "no"  or l == "0" then return false end
			return nil
		end,
		Validate = function(value: any): boolean | string
			return type(value) == "boolean" or "expected boolean (true/false/yes/no)"
		end,
		Autocomplete = function(_raw: string): { any }
			return { "true", "false" }
		end,
		Display = function(value: any): string
			return tostring(value)
		end,
		Multi = false, Delimiter = nil, Searchable = false,
	})

	TypeSystem.define("Player", {
		Parse = function(raw: string): Player?
			return game:GetService("Players"):FindFirstChild(raw) :: Player?
		end,
		Validate = function(value: any): boolean | string
			return value ~= nil or "player not found"
		end,
		Autocomplete = function(raw: string): { any }
			local all = game:GetService("Players"):GetPlayers()
			if raw == "" then return all end
			local out = {}
			for _, p in all do
				if p.Name:lower():sub(1, #raw) == raw:lower() then
					table.insert(out, p)
				end
			end
			return out
		end,
		Display = function(value: any): string
			return (value :: Player).Name
		end,
		Multi = false, Delimiter = nil, Searchable = false,
	})

	TypeSystem.define("Players", {
		Parse = function(raw: string): { Player }
			local Players = game:GetService("Players")
			if raw == "all" then return Players:GetPlayers() end
			local out: { Player } = {}
			for _, segment in raw:split(",") do
				local trimmed = segment:match("^%s*(.-)%s*$")
				local p = Players:FindFirstChild(trimmed) :: Player?
				if p then table.insert(out, p) end
			end
			return out
		end,
		Validate = function(value: any): boolean | string
			return (type(value) == "table" and #(value :: { any }) > 0) or "no players matched"
		end,
		Autocomplete = function(raw: string): { any }
			local all = game:GetService("Players"):GetPlayers()
			if raw == "" then return all end
			local segments = raw:split(",")
			local current  = (segments[#segments] :: string):match("^%s*(.-)%s*$") or ""
			local out = {}
			for _, p in all do
				if p.Name:lower():sub(1, #current) == current:lower() then
					table.insert(out, p)
				end
			end
			return out
		end,
		Display = function(value: any): string
			return (value :: Player).Name
		end,
		Multi = true, Delimiter = ",", Searchable = true,
	})

	TypeSystem.define("Team", {
		Parse = function(raw: string): Team?
			return game:GetService("Teams"):FindFirstChild(raw) :: Team?
		end,
		Validate = function(value: any): boolean | string
			return value ~= nil or "team not found"
		end,
		Autocomplete = function(_raw: string): { any }
			return game:GetService("Teams"):GetTeams()
		end,
		Display = function(value: any): string
			return (value :: Team).Name
		end,
		Multi = false, Delimiter = nil, Searchable = false,
	})

	TypeSystem.define("Color", {
		Parse = function(raw: string): Color3?
			local parts = raw:split(",")
			if #parts == 3 then
				local r, g, b = tonumber(parts[1]), tonumber(parts[2]), tonumber(parts[3])
				if r and g and b then return Color3.fromRGB(r, g, b) end
			end
			return nil
		end,
		Validate = function(value: any): boolean | string
			return typeof(value) == "Color3" or "expected Color (r,g,b)"
		end,
		Autocomplete = function(_raw: string): { any }
			return {}
		end,
		Display = function(value: any): string
			local c = value :: Color3
			return string.format("%.0f,%.0f,%.0f", c.R * 255, c.G * 255, c.B * 255)
		end,
		Multi = false, Delimiter = nil, Searchable = false,
	})

	TypeSystem.define("Vector3", {
		Parse = function(raw: string): Vector3?
			local parts = raw:split(",")
			if #parts == 3 then
				local x, y, z = tonumber(parts[1]), tonumber(parts[2]), tonumber(parts[3])
				if x and y and z then return Vector3.new(x, y, z) end
			end
			return nil
		end,
		Validate = function(value: any): boolean | string
			return typeof(value) == "Vector3" or "expected Vector3 (x,y,z)"
		end,
		Autocomplete = function(_raw: string): { any }
			return {}
		end,
		Display = function(value: any): string
			local v = value :: Vector3
			return string.format("%.2f,%.2f,%.2f", v.X, v.Y, v.Z)
		end,
		Multi = false, Delimiter = nil, Searchable = false,
	})

end

return BuiltinTypes