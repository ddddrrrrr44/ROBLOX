local Accuracy = {}

local StateManager = require(game.ServerScriptService.StateManager)

local function getAccuracy(player, tool)
	if tool and tool.pointBlank and tool.idealRange and tool.maxRange then
		local pbM, irM, mrM = tool.pointBlankMod, tool.idealRangeMod, tool.maxRangeMod
		if tool.Powerup and tool.Powerup.accuracy then
			pbM += tool.Powerup.accuracy 
			irM += tool.Powerup.accuracy 
			mrM += tool.Powerup.accuracy 
		end
		return tool.pointBlank, tool.idealRange, tool.maxRange, pbM, irM, mrM, player:GetAttribute("Accuracy")
	else
		return 0, 8, 14, math.random(5,20), math.random(25,50), math.random(15,30), player:GetAttribute("Accuracy")
	end
end

function Accuracy.CalculateAccuracy(player, targetDistance, tool)
	local PointBlank, IdealRange, MaxRange, PointBlankMod, IdealRangeMod, MaxRangeMod, baseAccuracy = getAccuracy(player, tool)
	if targetDistance >= PointBlank and targetDistance <= IdealRange then
		local AccuracyMod = PointBlankMod + ((targetDistance - PointBlank) / (IdealRange - PointBlank)) * (IdealRangeMod - PointBlankMod)
		local FinalAccuracy = AccuracyMod + baseAccuracy 
		if StateManager.States[player].Blind then
			FinalAccuracy *= 0.7
		end
		if StateManager.States[player].Locomotion then
			FinalAccuracy *= 0.9
		end
		return FinalAccuracy
	elseif targetDistance > IdealRange and targetDistance <= MaxRange then
		local AccuracyMod = IdealRangeMod + ((targetDistance - IdealRange) / (MaxRange - IdealRange)) * (MaxRangeMod - IdealRangeMod)
		local FinalAccuracy = AccuracyMod + baseAccuracy
		if StateManager.States[player].Blind then
			FinalAccuracy *= 0.7
		end
		if StateManager.States[player].Locomotion then
			FinalAccuracy *= 0.9
		end
		return FinalAccuracy
	else
		return 0 
	end
end

function Accuracy.CalculateNPCAccuracy(npc, accuracy)
	local FinalAccuracy = accuracy + 5
	if StateManager.States[npc].Blind then
		FinalAccuracy = FinalAccuracy - (FinalAccuracy * .30)
	end
	if StateManager.States[npc].Locomotion then
		FinalAccuracy *= 0.9
	end
	return FinalAccuracy
end

function Accuracy.CalculateHitChance(player, accuracy, targetEvasion) --CHECK AREA AND CONE ATTACKS SINGLES REGISTER FINE BUT NOT AREA / CONE BECAUSE OF REFERENCE TO CHARACTER
	local finalChance = accuracy - (targetEvasion * 0.5) 
	local randomRoll = math.random(0, 100)
	if randomRoll <= finalChance then
		return true  -- Hit
	else
		return false  -- Miss
	end
end

return Accuracy