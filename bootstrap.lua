-- Builds the bundler itself into dist/onelua.lua using the bundler
local SELF_DIR = ((debug.getinfo(1, "S").source:sub(2)):match("^(.*[/\\])") or "./")
package.path = SELF_DIR .. "?.lua;" .. SELF_DIR .. "?/init.lua;" .. package.path

local Bundler = require("bundler")

-- Ensure the output directory exists
local dist_dir = "dist"
local sep = package.config:sub(1, 1)
if sep == "\\" then
	os.execute('mkdir "' .. dist_dir:gsub("/", "\\") .. '" 2>nul')
else
	os.execute('mkdir -p "' .. dist_dir .. '"')
end

local output = dist_dir .. "/onelua.lua"
print("[bootstrap] building bundler -> " .. output)
print("[bootstrap] source modules:")
Bundler.bundle({
	entry = "bundler",
	src = "./",
	out = output,
	name = "bundler",
	strip = "all",
	debug = true,
	verify = true,
})

print("[bootstrap] done -> " .. output)
