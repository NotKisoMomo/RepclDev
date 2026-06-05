--!strict

local Types = require(script.Parent.Types)
type Config    = Types.Config
type AuthHook  = Types.AuthHook
type RoleHook  = Types.RoleHook
type GroupHook = Types.GroupHook

local authHook:    AuthHook?  = nil
local roleHook:    RoleHook?  = nil
local groupHook:   GroupHook? = nil
local defaultRole: string     = "User"
local whitelist:   { [number]: boolean } = {}
local blacklist:   { [number]: boolean } = {}

local AuthManager = {}

function AuthManager.init(config: Config)
	defaultRole = config.DefaultRole or "User"
	whitelist   = {}
	blacklist   = {}
	authHook    = nil
	roleHook    = nil
	groupHook   = nil
end

function AuthManager.setAuthHook(fn: AuthHook)
	authHook = fn
end

function AuthManager.setRoleHook(fn: RoleHook)
	roleHook = fn
end

function AuthManager.setGroupHook(fn: GroupHook)
	groupHook = fn
end

function AuthManager.setDefaultRole(role: string)
	defaultRole = role
end

function AuthManager.allow(userId: number)
	whitelist[userId] = true
end

function AuthManager.deny(userId: number)
	blacklist[userId] = true
end

function AuthManager.getRole(player: Player): string
	if roleHook then
		local ok, role = pcall(roleHook, player)
		if ok and type(role) == "string" then return role end
	end
	return defaultRole
end

function AuthManager.getRank(player: Player): number
	if groupHook then
		local ok, rank = pcall(groupHook, player)
		if ok and type(rank) == "number" then return rank end
	end
	return 0
end

function AuthManager.check(player: Player, commandName: string): (boolean, string)
	if blacklist[player.UserId] then
		return false, "you are not permitted to use commands"
	end
	if whitelist[player.UserId] then
		return true, ""
	end
	if authHook then
		local ok, result = pcall(authHook, player, commandName)
		if not ok then return false, "auth check failed internally" end
		if result == false then return false, "insufficient permissions" end
		return true, ""
	end
	return true, ""
end

return AuthManager