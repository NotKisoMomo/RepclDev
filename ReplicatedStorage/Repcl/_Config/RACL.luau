local RACL = {
	Window = {
		Opacity = 0.9,
		Borderless = false,
		Width = 800,
		Height = 500,
		Position = "center", -- "center" |"centerleft" | "centerright" | "bottomleft" | "bottomright" | "bottom" | "topright" | "topleft" | "top" | Udim2 | Vector2
		Padding = 8,
	},
	Font = {
		Family = "RobotoMono",
		Size = 14,
	},
	Scrollback = {
		Lines = 1000,
		Multiplier = 3,
	},
	Cursor = {
		Style = "block", -- "block" | "underline" | "bar"
		Blink = true,
		BlinkRate = 0.5,
	},
}
return RACL