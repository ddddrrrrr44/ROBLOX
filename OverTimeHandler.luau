local OverTimeHandler = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatEvent = ReplicatedStorage.Events.CombatEvent
local CombatStateEvent = ReplicatedStorage.Events.CombatStateEvent

local StateManager = require(game.ServerScriptService.StateManager)
local CharacterManager = require(game.ServerScriptService.CharacterManager)
local InstanceCache = require(game.ServerScriptService.InstanceCache)
local Buffer = require(game.ServerScriptService.Buffer)
local PvP = require(game.ServerScriptService.PvP)
local CombatFunctions = require(game.ServerScriptService.CombatFunctions)
local Configuration = require(game.ServerScriptService.Configuration)

local CONFIG = Configuration.CONFIG_TABLE

local DoT = {}
local HoT = {}

--DOT SECTION
local function checkDOTLimit(target, dotType, dotIdentifier, targetTable, tickAmount)
	local counter = 0
	local replaceDOT = {ID = dotIdentifier, tick = tickAmount}
	for DotID, DotINFO in pairs(targetTable[dotType]) do --iterate through the dot table
		if DotID == "amount" or next(DotINFO) == nil then -- if no dots or the ID is amount then continue
			continue
		end
		counter += 1 
		if DotINFO.tickAmount < replaceDOT.tick then -- as we iterate we find the weakest dot to replace
			replaceDOT.ID = DotID
			replaceDOT.tick = DotINFO.tickAmount
		end
	end
	if counter == CONFIG.OVERTIME[dotType].LIMIT and replaceDOT.ID ~= dotIdentifier then --if the id of the weakest dot is different than initialization and we are at limit we remove that dot and add new one -> true
		DoT[target][dotType][replaceDOT.ID] = nil 
		return true
	end
	return counter < CONFIG.OVERTIME[dotType].LIMIT -- if dot is weaker than any dots return true or false based on current dot amount
end

function OverTimeHandler.addDamageOverTime(target, source, dotType, dotIdentifier, dotDuration, dotTick)
	if not StateManager.getState(target, "Attackable") or StateManager.getState(target, "SuperArmor") then
		return false --did not apply a dot
	end
	local dotTicks = math.floor(dotDuration / CONFIG.OVERTIME[dotType].TICK_DELAY)
	DoT[target] = DoT[target] or {}
	local targetTable = DoT[target] --grab table for all dots, initialize here to not iterate through entire npc/player list but rather tick check / iterate only when the dots actually exist
	targetTable[dotType] = targetTable[dotType] or {}  -- grab type of dot ie -> poison or fire
	if targetTable[dotType] and targetTable[dotType][dotIdentifier] then --if dot already exists we reapply the dot for maximum ticks
		targetTable[dotType][dotIdentifier].dotTicks = dotTicks
		return true -- applied a dot
	end
	if not checkDOTLimit(target, dotType, dotIdentifier, targetTable, dotTick) then
		return false --did not apply a dot
	end
	targetTable[dotType]["amount"] = (targetTable[dotType]["amount"] or 0) + 1
	targetTable[dotType][dotIdentifier] = {source = source, dotTicks = dotTicks, tickAmount = dotTick, timer = os.clock()} -- we set the source, the amount of ticks / TICK_DELAY, tickamount(DAMAGE), and the current timer
	return true --applied a dot
end

local function applyTick(target, dotType, dotIdentifier, dotInfo)
	local targetHealth = CharacterManager.getStat(target, "Health", nil)
	if not targetHealth then
		DoT[target][dotType][dotIdentifier] = nil
		return
	end
	local damage = dotInfo.tickAmount
	if dotType == CONFIG.DOT_POISON then -- if 3 or more dots swap to table with function calls
		if targetHealth > 0 then -- poison can not kill instance sets to maximum limit 
			CharacterManager.setStat(target, "Health", math.max(targetHealth - dotInfo.tickAmount, 0.01))
		end
	elseif dotType == CONFIG.DOT_FIRE then
		damage = damage + damage * (CharacterManager.getStat(target, "Wounds", 0) * CONFIG.FIRE_TICK_MULTIPLER / CONFIG.FIRE_TICK_DIVISOR)
		CombatFunctions.applyDamage(dotInfo.source, target, damage) -- fire can kill instance
		CombatFunctions.giveWounds(target, damage, CONFIG.FIRE_WOUND_MULTIPLIER)
	end
	if InstanceCache.getPlayerBool(target) then
		PvP.flagPvP(dotInfo.source) -- flag player for damage dealt
	else
		local NPCSpawner = require(game.ServerScriptService.NPCs.NPCSpawner) -- need to add this here to avoid recursion
		NPCSpawner.addDamage(dotInfo.source, target, damage) --add to npcThreatTable
	end
	local bufferedTable = Buffer.writeUINT8State(dotType, damage) -- buffer then fire client visual tick / particles
	CombatEvent:FireAllClients(target, bufferedTable)
	dotInfo.dotTicks -= 1  --reduce ticks by 1
	if dotInfo.dotTicks <= 0 then -- if tick is <= 0 then remove the dot as it expended all ticks
		DoT[target][dotType][dotIdentifier] = nil
		DoT[target][dotType].amount -= 1 
		if DoT[target][dotType].amount <= 0 then --if no dots exist then remove the DotType and set the state
			DoT[target][dotType] = nil
			StateManager.setState(target, dotType, false)
		end
		return
	end
	dotInfo.timer = os.clock() --set new tick timer
end

local function checkDOTTable(target)
	if not DoT[target]["Poison"] and not DoT[target]["Fire"] then --if fire and poison do not exist then we clear the dot table so it doesnt iterate through this instance
		DoT[target] = nil
	end
end

local function checkDOTs()
	local now = os.clock()
	for target, table1 in pairs(DoT) do --iterate through all active dots (all playres/npcs with active dots)
		for dotType, table2 in pairs(table1) do --check dotType maximum (2 fire/poison)
			for dotIdentifier, dotInfo in pairs(table2) do --check dotInfo (max 5 per type so 10 iterations per player/npc in worst case + *+ amount of whatever is newly added)
				if dotIdentifier == "amount" then --no identifier in the game can be amount so this is safe
					continue
				end
				if dotInfo.timer + CONFIG.OVERTIME[dotType].TICK_DELAY < now then --check if the dot is ready to be applied
					applyTick(target, dotType, dotIdentifier, dotInfo)
				end
			end 
		end
		checkDOTTable(target) --check to see if we remove the table to avoid further iterations or not
	end
end

--HOT section

local function checkHOTLimit(target, targetTable, hotID, hotAmount)
	local hotList = targetTable[hotID]
	if #hotList >= CONFIG.OVERTIME[hotID].LIMIT then -- iterate through the entire table 
		local hotRemoveIndex = 1
		local hotTick = hotAmount 
		for index, hotInfo in ipairs(hotList) do
			local totalAmount = hotInfo.tickAmount * hotInfo.hotTicks --find the lowest tick hot
			if totalAmount <= hotTick then
				hotRemoveIndex = index
				hotTick = totalAmount
			end
		end
		table.remove(hotList, hotRemoveIndex) --remove the lowest tick hot
	end
end

function OverTimeHandler.addHealOverTime(target, player, hotID, hotDuration, hotAmount) --target validation ie same party / faction / pvp status etc all checked in prior script this part is safe to add heals
	HoT[target] = HoT[target] or {}
	local targetTable = HoT[target] --grab table for all possible HoTs
	targetTable[hotID] = targetTable[hotID] or {}  -- set hotidentifier won't need to differentiate between types
	checkHOTLimit(target, targetTable, hotID, hotAmount * hotDuration) --multiply the tickAmount by amountofTicks to find the replacable HoT
	table.insert(targetTable[hotID], {source = player, hotTicks = hotDuration, tickAmount = hotAmount, timer = os.clock()})
end

local function applyHeal(target, hotIdentifier, hotInfo, index)
	if not StateManager.getState(target, "Alive") then
		HoT[target][hotIdentifier] = nil --remove the table if the player is dead so the skill isn't applied on respawn
		return false
	end
	local health = CharacterManager.getStat(target, "Health", 0)
	local maxHealth = CharacterManager.getStat(target, "MaxHealth", 0)
	local wounds = CharacterManager.getStat(target, "Wounds", 0)
	hotInfo.hotTicks -= 1
	if health >= maxHealth - wounds then
		return false
	end
	CharacterManager.setStat(target, "Health", math.min(health + hotInfo.tickAmount, maxHealth - wounds))
	if hotInfo.hotTicks <= 0 then
		table.remove(HoT[target][hotIdentifier], index)
		return true
	end
	hotInfo.timer = os.clock()
	return true
end

local function checkHOTs()
	local now = os.clock()
	for target, table1 in pairs(HoT) do --iterate through all active hots (all playres/npcs with active hots)
		for hotIdentifier, table2 in pairs(table1) do
			for index, hotInfo in ipairs(table2) do
				if hotInfo.timer + CONFIG.OVERTIME[hotIdentifier].TICK_DELAY < now then --check if the hot is ready to be applied
					if applyHeal(target, hotIdentifier, hotInfo, index) then
						local bufferedTable = Buffer.writeUINT8State("Heal", hotInfo.tickAmount, hotIdentifier.."Particle")
						CombatStateEvent:FireAllClients(target, bufferedTable)
					end
				end
			end
		end 
	end
end

function OverTimeHandler.removeInstanceTable(instance) --remove leaving players or dead npcs 
	if DoT[instance] then
		DoT[instance] = nil
	end	
	if HoT[instance] then
		HoT[instance] = nil
	end
end


task.spawn(function()
	while true do
		task.wait(CONFIG.OVERTIME.INTERVAL)
		checkDOTs()
		checkHOTs()
	end
end)

return OverTimeHandler