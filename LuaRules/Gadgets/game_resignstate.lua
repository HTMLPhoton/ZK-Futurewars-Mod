if not gadgetHandler:IsSyncedCode() then
	return
end

function gadget:GetInfo()
	return {
		name      = "Resign Handler",
		desc      = "Handles Resign state",
		author    = "Shaman, terve886",
		date      = "4/15/2021",
		license   = "PD-0",
		layer     = 1,
		enabled   = true  --  loaded by default?
	}
end

local DestroyAlliance = GG.DestroyAlliance
local PUBLIC = {public = true}
local ALLIED = {allied = true}

local states = {} -- allyTeamID = {count = num, playerStates = {}}
local playerMap = {} -- playerID = allyTeamID
local resigntimer = 180 -- timer starts at 3 minutes and loses a second every 3rd second (down to 60s) over the first 6 minutes.
local mintime = 60
local resignteams = {}
local afkplayers = {}
Spring.SetGameRulesParam("resigntimer_max", resigntimer, PUBLIC)

-- config --

local thresholds = {
	[1] = 1,
	[2] = 2,
	[3] = 3,
	[4] = 3,
	[5] = 4,
	[6] = 4,
	[7] = 5,
	[8] = 5,
	[9] = 6,
	[10] = 6,
	[11] = 7,
	[12] = 7,
	[13] = 8,
	[14] = 8,
	[15] = 9,
	[16] = 9,
}

local function GetAllyTeamPlayerCount(allyTeamID)
	local teamlist = Spring.GetTeamList(allyTeamID)
	local aiteam = true
	local aicount = 0
	local playerCount = 0
	for i = 1, #teamlist do
		local teamID = teamlist[i]
		local teamAI = select(2, Spring.GetAIInfo(teamID))
		if teamAI then
			aicount = aicount + 1
		else
			aiteam = false
		end
		local playerList = Spring.GetPlayerList(teamID) -- spectators are ignored as of 104.0
		if #playerList > 0 then
			playerCount = playerCount + #playerList
		end
	end
	return playerCount
end

local function GetAllyTeamThreshold(allyTeamID)
	local playerCount = GetAllyTeamPlayerCount(allyTeamID)
	local threshold = thresholds[playerCount] or math.max(math.ceil((playerCount / 2) + 1), math.min(playerCount, 3))
	if threshold > playerCount then
		threshold = playerCount
	end
	return threshold, playerCount
end

local function AddResignTeam(allyTeamID)
	local count = #resignteams
	resignteams[count + 1] = allyTeamID
end

local function RemoveResignTeam(allyTeamID)
	local id
	if #resignteams == 1 then
		resignteams[1] = nil
		return
	end
	for i = 1, #resignteams do
		if resignteams[i] == allyTeamID then
			id = i
			break
		end
	end
	resignteams[id] = resignteams[#resignteams]
	resignteams[#resignteams] = nil
end

local function CheckAllyTeamState(allyTeamID)
	if states[allyTeamID].count == states[allyTeamID].total then
		DestroyAlliance(allyTeamID)
		RemoveResignTeam(allyTeamID)
	end
	if states[allyTeamID].count >= states[allyTeamID].threshold and not states[allyTeamID].thresholdState then
		states[allyTeamID].thresholdState = true
		AddResignTeam(allyTeamID)
	elseif states[allyTeamID].count < states[allyTeamID].threshold and states[allyTeamID].thresholdState then
		states[allyTeamID].thresholdState = false
	end
end

local function UpdatePlayerResignState(playerID, state, update)
	local allyTeamID = playerMap[playerID]
	local currentState = states[allyTeamID].playerStates[playerID] or false
	if currentState == state then
		return
	end
	local mod = 0
	if state then
		mod = 1
	else
		mod = -1
	end
	states[allyTeamID].count = states[allyTeamID].count + mod
	states[allyTeamID].playerStates[playerID] = state
	if update then
		CheckAllyTeamState(allyTeamID)
	end
end

local function AFKUpdate(playerID)
	local state = Spring.GetPlayerRulesParam(playerID, "lagmonitor_lagging") or 0
	if state == 1 and not afkplayers[playerID] then
		local allyTeamID = playerMap[playerID]
		local wantsResign = states[allyTeamID].playerStates[playerID]
		afkplayers[playerID] = states[allyTeamID].playerStates[playerID] or false
		UpdatePlayerResignState(playerID, false, false)
		states[allyTeamID].total = states[allyTeamID].total - 1
	elseif state == 0 and afkplayers[playerID] ~= nil then
		local wantedresign = afkplayers[playerID]
		local allyTeamID = playerMap[playerID]
		states[allyTeamID].total = states[allyTeamID].total + 1
		states[allyTeamID].threshold = 
		if wantedresign then
			UpdatePlayerResignState(playerID, true, true)
		end
		afkplayers[playerID] = nil
	end
end

GG.ResignState = {UpdateAFK = AFKUpdate}

local function Initialize()
	local allyteamlist = Spring.GetAllyTeamList()
	for a = 1, #allyteamlist do
		local allyTeamID = allyteamlist[a]
		states[allyTeamID] = {
			playerStates = {},
			count = 0,
			timer = 180,
		}
		states[allyTeamID].threshold, states[allyTeamID].total = GetAllyTeamThreshold(allyTeamID)
		Spring.SetGameRulesParam("resign_alliance_" .. allyTeamID .. "_threshold", states[allyTeamID].threshold, PUBLIC)
		Spring.SetGameRulesParam("resign_alliance_" .. allyTeamID .. "_count", 0, PUBLIC)
		Spring.SetGameRulesParam("resign_alliance_" .. allyTeamID .. "_voters", "", ALLIED)
	end
end

local function UpdateResignTimer(allyTeamID)
	Spring.SetGameRulesParam("resigntimer_" .. allyTeamID, states[allyTeamID].timer, PUBLIC)
end

function gadget:GameFrame(f)
	if f%90 == 15 then
		if resigntimer > mintime then
			for i = 1, #states do
				states[i].timer = states[i].timer - 1
				UpdateResignTimer(i)
			end
			resigntimer = resigntimer - 1
			Spring.SetGameRulesParam("resigntimer_max", resigntimer, PUBLIC)
		end
		if #resignteams > 0 then
			for i = 1, #resignteams do
				local allyTeamID = resignteams[i]
				if not states[allyTeamID].thresholdState then
					states[allyTeamID].timer = states[allyTeamID].timer + 1
					if states[allyTeamID].timer == resigntimer then
						RemoveResignTeam(allyTeamID)
					end
				end
			end
		end
	end
	if f%30 == 0 and #resignteams > 0 then
		for i = 1, #resignteams do
			local allyTeamID = resignteams[i]
			if states[allyTeamID].thresholdState then
				states[allyTeamID].timer = states[allyTeamID].timer - 1
				UpdateResignTimer(allyTeamID)
				if states[allyTeamID].timer == 0 then
					Spring.Echo("game_message: Team " .. allyTeamID .. " Destroyed due to morale.")
					DestroyAlliance(allyTeamID)
				end
			end
		end
	end
end

function gadget:RecvLuaMsg(msg, playerID)
	if playerMap[playerID] == nil then
		return
	end
	if msg:find("forceresign") then
		local allyTeamID = playerMap[playerID]
		if allyTeamID == nil then
			return
		end
		states[allyTeamID].threshold, states[allyTeamID].total = GetAllyTeamThreshold(allyTeamID)
		if states[allyTeamID].playerStates[playerID] then
			states[allyTeamID].count = states[allyTeamID].count - 1
			CheckAllyTeamState(allyTeamID)
		end
		states[allyTeamID].playerStates[playerID] = nil
		playerMap[playerID] = nil
	end
	if msg:find("resignstate") then -- resignstate 1 or resignstate 0
		msg = msg:gsub("resignstate", "")
		msg = msg:gsub(" ", "")
		local s = tonumber(msg)
		if s ~= nil then
			UpdatePlayerResignState(playerID, s == 1, true)
		end
	end
end
