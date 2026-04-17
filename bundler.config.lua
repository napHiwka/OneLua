-- Template configuration file for OneLua (can be used to bundle itself).
--
-- The bundler automatically detects this file if it is present in the working directory.
-- Any field can be overridden via the command line, for example:
--   lua bundler.lua --out dist/dev_build.lua --debug
--
-- For multi-target projects, use separate config files:
--   lua bundler.lua --config configs/release.lua
--   lua bundler.lua --config configs/debug.lua

return {
	------------------------------------------------------------------------
	-- Required
	------------------------------------------------------------------------

	-- Entry point module name or file path.
	entry = "bundler",

	-- Root directory containing local modules.
	-- Module "a.b.c" resolves to src/a/b/c.lua or src/a/b/c/init.lua.
	src = "./",

	------------------------------------------------------------------------
	-- Output
	------------------------------------------------------------------------

	-- Output file path for the generated bundle.
	out = "dist/onelua.lua",

	-- Name of the variable that stores the entry module's return value
	-- in the generated bundle. Defaults to the last segment of `entry`.
	name = "bundler",

	------------------------------------------------------------------------
	-- Dependency management
	------------------------------------------------------------------------

	-- Modules to force-include, even if not detected during auto-discovery.
	-- Useful for modules loaded via dynamic require() that static analysis
	-- cannot resolve.
	-- extra = {
	-- 	"plugins.json_backend",
	-- 	"plugins.xml_backend",
	-- },

	-- If true, include `extra` modules as-is without scanning their local require() calls.
	-- skip_extra_files_requires = false,

	-- Require aliases: when bundled code calls require(from), it resolves to require(to).
	-- Useful for environment-specific substitutions or shortening long module paths.
	-- aliases = {
	-- 	["json"] = "vendor.json",
	-- 	["config"] = "app.config.production",
	-- },

	------------------------------------------------------------------------
	-- Other
	------------------------------------------------------------------------

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
	-- Also prints the keys of the returned module table.
	verify = true,
}
