--[[
    Made by Akane  V1.0
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
	Q = Spell.Skillshot({
		 Slot = Enums.SpellSlots.Q,
		 Range = 900,
		 Delay = 0.25,
		 Speed = 1200,
		 Radius = 70,
		 Type = "Linear",
		 Collision = {Heroes=true, Minions=true, WindWall=true},
	}),
	W = Spell.Skillshot({
		 Slot = Enums.SpellSlots.W,
		 Range = 900,
		 Delay = 1.25,
		 Speed = 1650,
		 Radius = 125,
		 Type = "Circular",
	}),
	E = Spell.Skillshot({
		 Slot = Enums.SpellSlots.E,
		 Range = 725,
		 Delay = 0.5,
		 Speed = 500,
		 Radius = 375,
		 Type = "Circular",
	}),
	R = Spell.Targeted({
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
			Menu.Slider("Combo.QHC", "Q HitChance", 0.7, 0, 1, 0.05) 
			Menu.Checkbox("Combo.UseW", "Use W", true)
			Menu.Slider("Combo.WHC", "W Hit Chance", 0.60, 0, 1, 0.05)
            Menu.Checkbox("Combo.UseE", "Use E", true)
			Menu.Slider("Combo.EHC", "E Hit Chance", 0.60, 0, 1, 0.05)
			Menu.Checkbox("Combo.UseR", "Use R", true)
			
            Menu.NextColumn()

            Menu.ColoredText("KillSteal", 0xFFD700FF, true)
            Menu.Checkbox("KillSteal.Q", "Use Q", true)
            Menu.Checkbox("KillSteal.W", "Use W", true)
			Menu.Checkbox("KillSteal.R", "Use R", true)
			
			Menu.NextColumn()
			
			Menu.ColoredText("Harass", 0xFFD700FF, true)
			Menu.Checkbox("Harass.UseQ", "Use Q", true) 
            Menu.Checkbox("Harass.UseW", "Use W", true)
			Menu.Slider("Harass.Mana", "Mana Percent", 50, 0, 100)
			
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

function Veigar.IsEnabledAndReady(spell, mode)
    return Menu.Get(mode .. ".Use"..spell) and spells[spell]:IsReady()
end

function ValidMinion(minion)
	return minion and minion.IsTargetable and minion.MaxHealth > 6 -- check if not plant or shroom
end

function Veigar.GetTargets(range)
    return {TS:GetTarget(range, true)}
end

function Veigar.Qdmg()
	return (80 + (spells.Q:GetLevel() - 1) * 40) + (0.6 * Player.TotalAP)
end 

function Veigar.Wdmg()
	return (100 + (spells.W:GetLevel() - 1) * 50) + (1 * Player.TotalAP)
end

function Veigar.Rdmg(target)
	local missingHealthPercent = (1 - target.Health / target.MaxHealth) * 100;
    local totalIncreasement = 1 + 1.5 * missingHealthPercent / 100;
	return ((175 + (spells.R:GetLevel() - 1) * 75) + (0.75 * Player.TotalAP)) * totalIncreasement
end

function Veigar.OnTick()

	local gameTime = Game.GetTime()
    if gameTime < (lastTick + 0.25) then return end
    lastTick = gameTime
	
	if Veigar.KsQ() then return end
	if Veigar.KsW() then return end
	if Veigar.KsR() then return end
	
	if Orbwalker.GetMode() == "Waveclear" then
		local minionsInRange = {}
	do
		Veigar.GetMinionsQ(minionsInRange, "enemy")
		sort(minionsInRange, function(a,b) return a.MaxHealth > b.MaxHealth end)
	end
	Veigar.FarmLogic(minionsInRange)
		Veigar.Waveclear()
	end
	
	local ModeToExecute = Veigar[Orbwalker.GetMode()]
    if ModeToExecute then
        ModeToExecute()
    end
end

function Veigar.ComboLogic(mode)
    if Veigar.IsEnabledAndReady("Q", mode) then
        local qChance = Menu.Get(mode .. ".QHC")
        for k, qTarget in ipairs(Veigar.GetTargets(spells.Q.Range)) do
            if spells.Q:CastOnHitChance(qTarget, qChance) then
                return
            end
        end
    end
	if Veigar.IsEnabledAndReady("W", mode) then
		local wChance = Menu.Get(mode .. ".WHC")
		for k, wTarget in ipairs(Veigar.GetTargets(spells.W.Range)) do
			if spells.W:CastOnHitChance(wTarget, wChance) then
				return
			end
		end
	end
	if Veigar.IsEnabledAndReady("E", mode) then
		local eChance = Menu.Get(mode .. ".EHC")
		for k, eTarget in ipairs(Veigar.GetTargets(spells.E.Range)) do
			if spells.E:CastOnHitChance(eTarget, eChance) then
				return
			end
		end
	end
	if Veigar.IsEnabledAndReady("R", mode) then
		for k, rTarget in ipairs(Veigar.GetTargets(spells.R.Range + Player.BoundingRadius)) do
			local RDmg = Veigar.Rdmg(rTarget)
			local ksHealth = spells.R:GetKillstealHealth(rTarget)
			if RDmg > ksHealth and spells.R:Cast(rTarget) then
				return
			end
		end
	end
end
function Veigar.HarassLogic(mode)
	local Man = Player.Mana / Player.MaxMana * 100
	local SlM = Menu.Get("Harass.Mana")
	if SlM > Man then
	return
	end
	if Veigar.IsEnabledAndReady("Q", mode) then
		local qChance = Menu.Get("Combo.QHC")
		for k, qTarget in ipairs(Veigar.GetTargets(spells.Q.Range)) do
			if spells.Q:CastOnHitChance(qTarget, qChance)then
				return
			end
		end
	end
	if Veigar.IsEnabledAndReady("W", mode) then
		local wChance = Menu.Get("Combo.WHC")
		for k, wTarget in ipairs(Veigar.GetTargets(spells.W.Range)) do
			if spells.W:CastOnHitChance(wTarget, wChance)then
				return
			end
		end
	end
end

function Veigar.KsQ()
	if Menu.Get("KillSteal.Q") then
		for k, qTarget in ipairs(TS:GetTargets(spells.Q.Range, true)) do
		local qDmg = DmgLib.CalculateMagicalDamage(Player, qTarget, Veigar.Qdmg())
		local ksHealth = spells.Q:GetKillstealHealth(qTarget)
			if qDmg > ksHealth and spells.Q:Cast(qTarget) then
				return
			end
		end
	end
end

function Veigar.KsW()
	if Menu.Get("KillSteal.W") then
		for k, wTarget in ipairs(TS:GetTargets(spells.W.Range, true)) do
		local wDmg = DmgLib.CalculateMagicalDamage(Player, wTarget, Veigar.Wdmg())
		local ksHealth = spells.W:GetKillstealHealth(wTarget)
			if wDmg > ksHealth and spells.W:Cast(wTarget) then
				return
			end
		end
	end
end

function Veigar.KsR()
	if Menu.Get("KillSteal.R") then
		for k, rTarget in ipairs(TS:GetTargets(spells.R.Range, true)) do
		local rDmg = DmgLib.CalculateMagicalDamage(Player, rTarget, Veigar.Rdmg(rTarget))
		local ksHealth = spells.R:GetKillstealHealth(rTarget)
			if rDmg > ksHealth and spells.R:Cast(rTarget) then
				return
			end
		end
	end
end

function Veigar.OnDraw() 
if Menu.Get("Draw.Q.Enabled") then
        Renderer.DrawCircle3D(Player.Position, spells.Q.Range, 25, 2, Menu.Get("Draw.Q.Color"))
    end
    if Menu.Get("Draw.W.Enabled") then
        Renderer.DrawCircle3D(Player.Position, spells.W.Range, 25, 2, Menu.Get("Draw.W.Color"))
    end
	if Menu.Get("Draw.E.Enabled") then
        Renderer.DrawCircle3D(Player.Position, spells.E.Range, 25, 2, Menu.Get("Draw.E.Color"))
    end
	if Menu.Get("Draw.R.Enabled") then
        Renderer.DrawCircle3D(Player.Position, spells.R.Range, 25, 2, Menu.Get("Draw.R.Color"))
    end
end

function Veigar.Combo()  Veigar.ComboLogic("Combo")  end
function Veigar.Harass() Veigar.HarassLogic("Harass") end

function Veigar.Waveclear()

	local pPos, pointsQ, pointsW = Player.Position, {}, {}
		
	-- Enemy Minions
	for k, v in pairs(ObjManager.Get("enemy", "minions")) do
		local minion = v.AsAI
		if ValidMinion(minion) then
			local posW = minion:FastPrediction(spells.W.Delay)
			if posW:Distance(pPos) < spells.W.Range and minion.IsTargetable then
				table.insert(pointsW, posW)
			end 
		end    
	end
		
	-- Jungle Minions
	if #pointsQ == 0 or pointsW == 0 then
		for k, v in pairs(ObjManager.Get("neutral", "minions")) do
			local minion = v.AsAI
			if ValidMinion(minion) then
				local posQ = minion:FastPrediction(spells.Q.Delay)
				local posW = minion:FastPrediction(spells.W.Delay)
				if posQ:Distance(pPos) < spells.Q.Range then
					table.insert(pointsQ, posQ)
				end
				if posW:Distance(pPos) < spells.W.Range then
					table.insert(pointsW, posW)
				end     
			end
		end
	end
	
	local bestPosQ, hitCountQ = spells.Q:GetBestLinearCastPos(pointsQ)
	if bestPosQ and hitCountQ >= Menu.Get("Wave.CastQHC")
		and spells.Q:IsReady() and Menu.Get("Wave.UseQ") then
		spells.Q:Cast(bestPosQ)
    end
	local bestPosW, hitCountW = spells.W:GetBestCircularCastPos(pointsW)
	if bestPosW and hitCountW >= Menu.Get("Wave.CastWHC")
		and spells.W:IsReady() and Menu.Get("Wave.UseW") then
		spells.W:Cast(bestPosW)
    end
end

function Veigar.GetMinionsQ(t, team_lbl)
    if Menu.Get("QL") then
        for k, v in pairs(ObjManager.Get(team_lbl, "minions")) do
            local minion = v.AsAI
            local minionInRange = minion and minion.MaxHealth > 6 and spells.Q:IsInRange(minion)
            local shouldIgnoreMinion = minion and (Orbwalker.IsLasthitMinion(minion) or Orbwalker.IsIgnoringMinion(minion))
            if minionInRange and not shouldIgnoreMinion and minion.IsTargetable then
                insert(t, minion)
            end                       
        end
    end
end

function Veigar.FarmLogic(minions)
    local rawDmg = Veigar.Qdmg()
    for k, minion in ipairs(minions) do
        local healthPred = spells.Q:GetHealthPred(minion)
        local qDmg = DmgLib.CalculateMagicalDamage(Player, minion, rawDmg)
        if healthPred > 0 and healthPred < qDmg and spells.Q:Cast(minion) then

            return true
        end                       
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