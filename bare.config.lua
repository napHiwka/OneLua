return {
	entry = "init",
	src = "./",
	out = "./bundle.lua",
	name = "meow",
	extra = {
		"plugins.json_backend",
		"plugins.xml_backend",
	},
	skip_extra_files_requires = false,
	aliases = {
		["json"] = "vendor.json",
		["config"] = "app.config.production",
	},
	strip = "all",
	resolve = true,
	compact = true,
	debug = true,
	verify = true,
}
