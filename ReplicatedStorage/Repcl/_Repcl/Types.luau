export type CommandRegistry = {
	Name: string,
	Aliases: {string},
	Description: string,
	Args: {string},
	Flags: {string},
	CaseSensitive: boolean?,
	StudioOnly: boolean?,
	Handle: () -> (Output)
}

export type CommandContext = {
	Args: {string},
	
}

export type Output = {
	Type: ("Warn" | "Info" | "Error" | "Log" | "Custom" | "Reply")?,
	Message: string,
	TypeData: {
		Color: Color3,
	}?
}

export type CELConfig = {
	
}

return {}