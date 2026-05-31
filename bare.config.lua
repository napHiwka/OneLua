return {
	entry = "init.lua",
	src = "./",
	out = "./bundle.lua",
	name = "meow",
	extra = {
		"plugins.backend",
	},
	skip_extra_files_requires = false,
	aliases = {
		["json"] = "vendor.json",
	},
	strip = "all",
	resolve = true,
	compact = true,
	debug = true,
	verify = true,
}
