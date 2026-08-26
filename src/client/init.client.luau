--!strict
-- Mounts the core HUD and relays intent. No amounts are computed here: the server owns
-- every number, the client only draws the last snapshot it was given.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local core = ReplicatedStorage.Packages.robloxcore
local Hud = require(core.uikit.hud)
local Config = require(core.logic.config)

local validated = Config.validate(require(ReplicatedStorage.Config))
if not validated.ok then
	error(`[config] {validated.message}`)
end

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local stateEvent = remotes:WaitForChild("State") :: RemoteEvent
local actionFunction = remotes:WaitForChild("Action") :: RemoteFunction

local hud
hud = Hud.new(validated.value, function(action)
	local result = actionFunction:InvokeServer(action)
	if type(result) == "table" and result.ok == false then
		hud:deny(action, result.code)
	end
end)

hud:mount(Players.LocalPlayer:WaitForChild("PlayerGui"))
stateEvent.OnClientEvent:Connect(function(snapshot)
	hud:update(snapshot)
end)
