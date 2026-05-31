-- Template configuration file for OneLua (can be used to bundle itself)
return {
	entry = "bundler.lua", -- Entry point module name or file path.

	-- Root directory containing local modules.
	-- Module "a.b.c" resolves to src/a/b/c.lua or src/a/b/c/init.lua.
	src = "./",
	out = "dist/onelua.lua", -- Output file path for the generated bundle.
	name = "bundler", -- Exported variable name

	-- Modules to force-include, even if not detected during auto-discovery.
	-- Useful for modules loaded via dynamic require().
	-- extra = {
	-- 	"plugins.json_backend",
	-- },

	-- If true, include `extra` modules as-is without scanning their local require() calls.
	-- skip_extra_files_requires = false,

	-- Require aliases: when bundled code calls require(from), it resolves to require(to).
	-- aliases = {
	-- 	["json"] = "vendor.json",
	-- },

	-- Comment stripping mode:
	-- false | "all" | "non_ann" ("non_ann" = non-annotation comments)
	strip = "all",

	-- Try to resolve a simple dynamic require; example utils = require(SOME .. "utils")
	-->utils = require("utils"). If an extra file `utils` is included, it will recognize
	-- it immediately, and there will be no need to edit the source code manually.
	resolve = true,

	-- Will collapse all line breaks in the source code to make it more compact.
	compact = true,

	-- Print each discovered module and dependency edge during bundling.
	debug = true,

	-- After writing, require() the bundle to verify it loads without errors.
	verify = true,
}
