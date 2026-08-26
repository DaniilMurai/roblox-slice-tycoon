--!strict
-- A title's own headless check: the config it ships must satisfy the core's validator.
-- The core's logic is tested in the core; duplicating that here would only rot.

local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")

local Config = require("../core/robloxcore/src/logic/config")

local raw = serde.decode("json", fs.readFile("configs/main.json"))
local validated = Config.validate(raw)

if not validated.ok then
	print(`FAIL configs/main.json: {validated.message}`)
	process.exit(1)
end

print(`configs/main.json is valid: {validated.value.slug}, {#validated.value.upgrades} upgrades`)
