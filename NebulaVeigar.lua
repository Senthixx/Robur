--[[
    Made by Akane  
]]

require("common.log")
module("Nebula Veigar", package.seeall, log.setup)

local clock = os.clock
local insert = table.insert

local _SDK = _G.CoreEx
local Console, ObjManager, EventManager, Geometry, Input, Renderer, Enums, Game = _SDK.Console, _SDK.ObjectManager, _SDK.EventManager, _SDK.Geometry, _SDK.Input, _SDK.Renderer, _SDK.Enums, _SDK.Game
local Menu, Orbwalker, Collision, Prediction, HealthPred = _G.Libs.NewMenu, _G.Libs.Orbwalker, _G.Libs.CollisionLib, _G.Libs.Prediction, _G.Libs.HealthPred
local DmgLib, ImmobileLib, Spell = _G.Libs.DamageLib, _G.Libs.ImmobileLib, _G.Libs.Spell
local SpellSlots, SpellStates = Enums.SpellSlots, Enums.SpellStates
local insert, sort = table.insert, table.sort
local Spell = _G.Libs.Spell

local spells = {
	_Q = Spell.Skillshot({
		 Slot = Enums.SpellSlots.Q,
		 Range = 900,
		 Delay = 0.25,
		 Speed = 1200,
		 Radius = 70,
		 Type = "Linear",
		 Collision = {Heroes=true, Minions=true, WindWall=true},
	}),
	_W = Spell.Skillshot({
		 Slot = Enums.SpellSlots.W,
		 Range = 900,
		 Delay = 1.25,
		 Speed = 1650,
		 Radius = 125,
		 Type = "Circular",
	}),
	_E = Spell.Skillshot({
		 Slot = Enums.SpellSlots.E,
		 Range = 725,
		 Delay = 0.5,
		 Speed = 500,
		 Radius = 375,
		 Type = "Circular",
	}),
	_R = Spell.Targeted({
		 Slot = Enums.SpellSlots.R,
		 Range = 650,
		 Collision = {WindWall=true},
	}),
}

---@type TargetSelector
local TS = _G.Libs.TargetSelector()
local Veigar = {}
local blockList = {}


function Veigar.LoadMenu()
    Menu.RegisterMenu("NebulaVeigar", "Nebula Veigar", function()
        Menu.ColumnLayout("cols", "cols", 2, true, function()
            Menu.ColoredText("Combo", 0xFFD700FF, true)
            Menu.Checkbox("Combo.UseQ", "Use Q", true)
			Menu.Slider("Combo.QHC", "Q Hit Chance", 0.7, 0, 1, 0.05)
			Menu.Checkbox("Combo.UseW", "Use W", true)
			Menu.Slider("Combo.WHC", "W Hit Chance", 0.7, 0, 1, 0.05)
            Menu.Checkbox("CE", "Use E", true)
			Menu.Slider("Combo.EHC", "E Hit Chance", 0.7, 0, 1, 0.05)
            Menu.NextColumn()

            Menu.ColoredText("KillSteal", 0xFFD700FF, true)
            Menu.Checkbox("KillSteal.Q", "Use Q", true)
            Menu.Checkbox("KillSteal.W", "Use W", true)
			Menu.Checkbox("KillSteal.R", "Use R", true)
			
			Menu.NextColumn()
			
			Menu.ColoredText("Harass", 0xFFD700FF, true)
			Menu.Checkbox("HQ", "Use Q", true) 
            Menu.Checkbox("HW", "Use W", true) 
			
			Menu.NextColumn()
			
			Menu.ColoredText("LastHit", 0xFFD700FF, true)
			Menu.Checkbox("QL", "Use Q To Last Hit", true)
			
			Menu.NextColumn()
			
			Menu.ColoredText("Clear", 0xFFD700FF, true)
			Menu.Checkbox("Wave.UseQ", "Use Q for jungleclear", true)
			Menu.Slider("Wave.CastQHC", "Q Min. Hit Count", 1, 0, 10, 1)
			Menu.Checkbox("Wave.UseW", "Use W", true)
			Menu.Slider("Wave.CastWHC", "W Min. Hit Count", 1, 0, 10, 1)
			
        end)        

        Menu.Separator()

        Menu.ColoredText("Draw Options", 0xFFD700FF, true)
		Menu.Checkbox("Draw.Q.Enabled",   "Draw Q Range")
        Menu.ColorPicker("Draw.Q.Color", "Draw Q Color", 0x1CA6A1FF)
        Menu.Checkbox("Draw.W.Enabled",   "Draw W Range")
        Menu.ColorPicker("Draw.W.Color", "Draw W Color", 0x1CA6A1FF) 
		Menu.Checkbox("Draw.E.Enabled",   "Draw E Range")
        Menu.ColorPicker("Draw.E.Color", "Draw E Color", 0x1CA6A1FF)
		Menu.Checkbox("Draw.R.Enabled",   "Draw R Range")
        Menu.ColorPicker("Draw.R.Color", "Draw R Color", 0x1CA6A1FF)
    end)
end

local lastTick = 0
local function CanPerformCast()
    local curTime = clock()
    if curTime - lastTick > 0.25 then 
        lastTick = curTime

        local gameAvailable = not (Game.IsChatOpen() or Game.IsMinimized())
        return gameAvailable and not (Player.IsDead or Player.IsRecalling) and Orbwalker.CanCast()
    end
end

function ValidMinion(minion)
	return minion and minion.IsTargetable and minion.MaxHealth > 6 -- check if not plant or shroom
end

function Veigar.GetTargets(range)
    return {TS:GetTarget(range, true)}
end

function Veigar.Qdmg()
	return (80 + (spells._Q:GetLevel() - 1) * 40) + (0.6 * Player.TotalAP)
end

function Veigar.Wdmg()
	return (100 + (spells._W:GetLevel() - 1) * 50) + (1 * Player.TotalAP)
end

function Veigar.Rdmg()
	return (175 + (spells._W:GetLevel() - 1) * 75) + (0.75 * Player.TotalAP)
end

function Veigar.OnTick()

	local gameTime = Game.GetTime()
    if gameTime < (lastTick + 0.25) then return end
    lastTick = gameTime
	
	if Veigar.KsQ() then return end
	if Veigar.KsW() then return end
	if Veigar.KsR() then return end
	
	if Orbwalker.GetMode() == "Combo" then
	
		if Menu.Get("Combo.UseQ") then
			local target = Orbwalker.GetTarget() or TS:GetTarget(spells._Q.Range + Player.BoundingRadius, true)
			if target then
				CastQ(target,Menu.Get("Combo.QHC"))
			end
		end
		if Menu.Get("Combo.UseW") then
			local target = Orbwalker.GetTarget() or TS:GetTarget(spells._W.Range + Player.BoundingRadius, true)
			if target then
				CastW(target,Menu.Get("Combo.WHC"))
			end
		end
		if Menu.Get("CE") then
			local target = Orbwalker.GetTarget() or TS:GetTarget(spells._E.Range + Player.BoundingRadius, true)
			if target then
				CastE(target,Menu.Get("Combo.EHC"))
			end
		end
		
	elseif Orbwalker.GetMode() == "Harass" then
	
		if Menu.Get("HQ") then
			local target = Orbwalker.GetTarget() or TS:GetTarget(spells._Q.Range + Player.BoundingRadius, true)
			if target then
				CastQ(target,Menu.Get("Combo.QHC"))
			end
		end
		if Menu.Get("HW") then
			local target = Orbwalker.GetTarget() or TS:GetTarget(spells._W.Range + Player.BoundingRadius, true)
			if target then
				CastW(target,Menu.Get("Combo.WHC"))
			end
		end	
	elseif Orbwalker.GetMode() == "Waveclear" then
		local minionsInRange = {}
        do -- Llenar la variable con los minions en rango
           Veigar.GetMinionsQ(minionsInRange, "enemy")       
           sort(minionsInRange, function(a, b) return a.MaxHealth > b.MaxHealth end)
        end
        Veigar.FarmLogic(minionsInRange)
		Waveclear()
	end
end
	
function CastQ(target,hitChance)
	if Player:GetSpellState(Enums.SpellSlots.Q) == SpellStates.Ready then
		local targetAI = target.AsAI
		local qPred = Prediction.GetPredictedPosition(targetAI, spells._Q, Player.Position)
		if qPred and qPred.HitChance >= hitChance then
			Input.Cast(SpellSlots.Q, qPred.CastPosition)
		end
	end
end

function CastW(target,hitChance)
	if Player:GetSpellState(Enums.SpellSlots.W) == SpellStates.Ready then
		local targetAI = target.AsAI
		local wPred = Prediction.GetPredictedPosition(targetAI, spells._W, Player.Position)
		if wPred and wPred.HitChance >= hitChance then
			Input.Cast(SpellSlots.W, wPred.CastPosition)
		end
	end
end

function CastE(target,hitChance)
	if Player:GetSpellState(Enums.SpellSlots.E) == SpellStates.Ready then
		local targetAI = target.AsAI
		local ePred = Prediction.GetPredictedPosition(targetAI, spells._E, Player.Position)
		if ePred and ePred.HitChance >= hitChance then
			Input.Cast(SpellSlots.E, ePred.CastPosition)
		end
	end
end

function Veigar.KsQ()
	if Menu.Get("KillSteal.Q") then
	for k, qTarget in ipairs(TS:GetTargets(spells._Q.Range, true)) do
		local qDmg = DmgLib.CalculateMagicalDamage(Player, qTarget, Veigar.Qdmg())
		local ksHealth = spells._Q:GetKillstealHealth(qTarget)
		if qDmg > ksHealth and spells._Q:Cast(qTarget) then
			return
		end
	end
  end
end

function Veigar.KsW()
	if Menu.Get("KillSteal.W") then
	for k, wTarget in ipairs(TS:GetTargets(spells._W.Range, true)) do
		local wDmg = DmgLib.CalculateMagicalDamage(Player, wTarget, Veigar.Wdmg())
		local ksHealth = spells._W:GetKillstealHealth(wTarget)
		if wDmg > ksHealth and spells._W:Cast(wTarget) then
			return
		end
	end
  end
end

function Veigar.KsR()
	if Menu.Get("KillSteal.R") then
	for k, rTarget in ipairs(TS:GetTargets(spells._R.Range, true)) do
		local rDmg = DmgLib.CalculateMagicalDamage(Player, rTarget, Veigar.Rdmg())
		local ksHealth = spells._R:GetKillstealHealth(rTarget)
		if rDmg > ksHealth and spells._R:Cast(rTarget) then
			return
		end
	end
  end
end

function Waveclear()

	local pPos, pointsQ, pointsW = Player.Position, {}, {}
		
	-- Enemy Minions
	for k, v in pairs(ObjManager.Get("enemy", "minions")) do
		local minion = v.AsAI
		if ValidMinion(minion) then
			local posW = minion:FastPrediction(spells._W.Delay)
			if posW:Distance(pPos) < spells._W.Range and minion.IsTargetable then
				table.insert(pointsW, posW)
			end 
		end    
	end
		
	-- Jungle Minions
	if #pointsQ == 0 or pointsW == 0 then
		for k, v in pairs(ObjManager.Get("neutral", "minions")) do
			local minion = v.AsAI
			if ValidMinion(minion) then
				local posQ = minion:FastPrediction(spells._Q.Delay)
				local posW = minion:FastPrediction(spells._W.Delay)
				if posQ:Distance(pPos) < spells._Q.Range then
					table.insert(pointsQ, posQ)
				end
				if posW:Distance(pPos) < spells._W.Range then
					table.insert(pointsW, posW)
				end     
			end
		end
	end
	
	local bestPosQ, hitCountQ = spells._Q:GetBestLinearCastPos(pointsQ)
	if bestPosQ and hitCountQ >= Menu.Get("Wave.CastQHC")
		and spells._Q:IsReady() and Menu.Get("Wave.UseQ") then
		spells._Q:Cast(bestPosQ)
    end
	local bestPosW, hitCountW = spells._W:GetBestCircularCastPos(pointsW)
	if bestPosW and hitCountW >= Menu.Get("Wave.CastWHC")
		and spells._W:IsReady() and Menu.Get("Wave.UseW") then
		spells._W:Cast(bestPosW)
    end
end

function Veigar.FarmLogic(minions)
	local qqDmg = Veigar.Qdmg()
	for k, minion in ipairs(minions) do
	local healthPred = spells._Q:GetHealthPred(minion)
	local qDmg = DmgLib.CalculateMagicalDamage(Player, minion, qqDmg)
	if healthPred > 0 and healthPred < qDmg and spells._Q:Cast(minion) then
	
		return true
	end
  end
end

function Veigar.GetMinionsQ(t, team_lbl)
	if Menu.Get("QL") then
		for k,v in pairs(ObjManager.Get(team_lbl, "minions")) do
			local minion = v.AsAI
            local minionInRange = minion and minion.MaxHealth > 6 and spells._Q:IsInRange(minion)
			local shouldIgnoreMinion = minion and (Orbwalker.IsLasthitMinion(minion) or Orbwalker.IsIgnoringMinion(minion))
			if minionInRange and not shouldIgnoreMinion and minion.IsTargetable then
				insert(t, minion)
			end
		end
	end
end

function Veigar.OnDraw() 
if Menu.Get("Draw.Q.Enabled") then
        Renderer.DrawCircle3D(Player.Position, spells._Q.Range, 25, 2, Menu.Get("Draw.Q.Color"))
    end
    if Menu.Get("Draw.W.Enabled") then
        Renderer.DrawCircle3D(Player.Position, spells._W.Range, 25, 2, Menu.Get("Draw.W.Color"))
    end
	if Menu.Get("Draw.E.Enabled") then
        Renderer.DrawCircle3D(Player.Position, spells._E.Range, 25, 2, Menu.Get("Draw.E.Color"))
    end
	if Menu.Get("Draw.R.Enabled") then
        Renderer.DrawCircle3D(Player.Position, spells._R.Range, 25, 2, Menu.Get("Draw.R.Color"))
    end
end


function OnLoad()
    if Player.CharName == "Veigar" then
        Veigar.LoadMenu()
        for eventName, eventId in pairs(Enums.Events) do
            if Veigar[eventName] then
                EventManager.RegisterCallback(eventId, Veigar[eventName])
            end
        end
    end
    return true
end