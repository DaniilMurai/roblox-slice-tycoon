--!strict
-- The whole server: build the adapters, hand them to the core, start. A title's behaviour
-- lives in configs/main.json — logic here would be logic the next title cannot reuse.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local core = ReplicatedStorage.Packages.robloxcore
local Config = require(core.logic.config)
local Runtime = require(core.runtime.server)
local Net = require(core.runtime.net)
local Host = require(core.runtime.host)
local Plots = require(core.runtime.plots)
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
	storeName = "SliceTycoon_v1",
	config = config,
	autosaveSeconds = 60,
	saveTimeoutSeconds = 10,
	staleAfterSeconds = 40,
	isActive = function(userId)
		return Players:GetPlayerByUserId(userId) ~= nil
	end,
	onSessionEnd = function(userId)
		host:kick(userId, "Your save was claimed by another server.")
	end,
})

-- A row of bases in front of the spawn, turned to face it. Built before the server starts:
-- the first player can be inside the game before the first frame of the row exists.
local plots = Plots.new({
	world = config.world,
	zones = config.zones,
	count = 6,
	origin = CFrame.new(0, 0, -60) * CFrame.Angles(0, math.pi, 0),
	parent = workspace,
	vacantSign = config.displayName,
	nameOf = function(userId)
		local player = host:playerOf(userId)
		return if player then player.DisplayName else "Player"
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
	world = plots,
	clock = function()
		return host:clock()
	end,
	snapshotHeartbeat = 5,
})

server:start()
print(`[{config.slug}] server up: {#config.upgrades} upgrades, autosave 60s`)
