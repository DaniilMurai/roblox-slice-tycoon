--!strict
-- The whole server: build the adapters, hand them to the core, start. A title's behaviour
-- lives in configs/main.json — logic here would be logic the next title cannot reuse.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local core = ReplicatedStorage.Packages.robloxcore
local Config = require(core.logic.config)
local Runtime = require(core.runtime.server)
local Net = require(core.runtime.net)
local Host = require(core.runtime.host)
local DataStoreAdapter = require(core.adapters.datastore)
local MarketplaceAdapter = require(core.adapters.marketplace)
local AnalyticsAdapter = require(core.adapters.analytics)

local Players = game:GetService("Players")

local validated = Config.validate(require(ReplicatedStorage.Config))
if not validated.ok then
	-- Refusing to boot beats booting with a broken economy: a wrong curve is only visible
	-- weeks later, in the retention numbers.
	error(`[config] {validated.message}`)
end
local config = validated.value

local host = Host.new()

local data = DataStoreAdapter.new({
	storeName = "PlayerData_v1",
	config = config,
	autosaveSeconds = 60,
	maxAttempts = 5,
	staleAfterSeconds = 40,
	isActive = function(userId)
		return Players:GetPlayerByUserId(userId) ~= nil
	end,
	onSessionEnd = function(userId)
		host:kick(userId, "Your save was claimed by another server.")
	end,
})

local server = Runtime.server({
	config = config,
	data = data,
	market = MarketplaceAdapter.new(config),
	analytics = AnalyticsAdapter.new(),
	presence = host,
	transport = Net.new(),
	scheduler = host,
	clock = function()
		return host:clock()
	end,
	snapshotHeartbeat = 5,
})

server:start()
print(`[{config.slug}] server up: {#config.upgrades} upgrades, autosave 60s`)
