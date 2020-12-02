--[[
    Release by Akane V1.0.1  
]]

require("common.log")
module("Nebula Lux", package.seeall, log.setup)

local clock = os.clock
local insert = table.insert

local _SDK = _G.CoreEx
local Console, ObjManager, EventManager, Geometry, Input, Renderer, Enums, Game = _SDK.Console, _SDK.ObjectManager, _SDK.EventManager, _SDK.Geometry, _SDK.Input, _SDK.Renderer, _SDK.Enums, _SDK.Game
local Menu, Orbwalker, Collision, Prediction, HealthPred = _G.Libs.NewMenu, _G.Libs.Orbwalker, _G.Libs.CollisionLib, _G.Libs.Prediction, _G.Libs.HealthPred
local DmgLib, ImmobileLib, Spell = _G.Libs.DamageLib, _G.Libs.ImmobileLib, _G.Libs.Spell
local SpellSlots, SpellStates = Enums.SpellSlots, Enums.SpellStates
local Spell = _G.Libs.Spell

local spells = {
	_Q = Spell.Skillshot({
		 Slot = Enums.SpellSlots.Q,
		 Range = 1250,
		 Delay = 0.25,
		 Speed = 1200,
		 Radius = 80,
		 Type = "Linear",
		 Collisions = {Heroes=true, Minions=true, WindWall=true},
	}),
	_W = Spell.Skillshot({
		 Slot = Enums.SpellSlots.W,
		 Range = 1075,
		 Delay = 0.25,
		 Speed = 1200,
		 Radius = 150,
		 Type = "Linear",
		 Collisions = {WindWall=true},
	}),
	_E = Spell.Skillshot({
		 Slot = Enums.SpellSlots.E,
		 Range = 1100,
		 Delay = 0.25,
		 Speed = 1300,
		 Radius = 150,
		 Type = "Circular",
		 Collisions = {WindWall=true},
		 UseHitbox = true
	}),
	_R = Spell.Skillshot({
		 Slot = Enums.SpellSlots.R,
		 Range = 3340,
		 Delay = 1,
		 Speed = 3000,
		 Radius = 250,
		 Type = "Linear",
	}),
}

---@type TargetSelector
local TS = _G.Libs.TargetSelector()
local Lux = {}
local blockList = {}


function Lux.LoadMenu()
    Menu.RegisterMenu("NebulaLux", "Nebula Lux", function()
        Menu.ColumnLayout("cols", "cols", 2, true, function()
            Menu.ColoredText("Combo", 0xFFD700FF, true)
            Menu.Checkbox("Combo.UseQ", "Use Q", true)
			Menu.Slider("Combo.QHC", "Q Hit Chance", 0.7, 0, 1, 0.05)
            Menu.Checkbox("Combo.UseE", "Use E", true)
			Menu.Slider("Combo.EHC", "E Hit Chance", 0.7, 0, 1, 0.05)

            Menu.NextColumn()

            Menu.ColoredText("KillSteal", 0xFFD700FF, true)
            Menu.Checkbox("KillSteal.Q", "Use Q", true)
            Menu.Checkbox("KillSteal.E", "Use E", true)
			Menu.Checkbox("KillSteal.R", "Use R", true)
			
			Menu.NextColumn()
			
			Menu.ColoredText("Harass", 0xFFD700FF, true)
            Menu.Checkbox("HQ", "Use Q", true)
            Menu.Checkbox("HE", "Use E", true) 
        end)        

        Menu.Separator()
    
        Menu.ColoredText("Misc", 0xFFD700FF, true)
        Menu.Checkbox("WAE", "Use W to Shield Allies", true)
		Menu.Checkbox("AGQ", "Use Q on Gapcloser", true)
		Menu.Checkbox("AQS", "Auto Q Immobile/Dash")
		Menu.Slider("SLM", "W Mana Percent", 50, 0 ,100)
        Menu.Separator()

        Menu.ColoredText("Draw Options", 0xFFD700FF, true)
		Menu.Checkbox("Draw.Q.Enabled",   "Draw Q Range")
        Menu.ColorPicker("Draw.Q.Color", "Draw Q Color", 0x1CA6A1FF)
        Menu.Checkbox("Draw.W.Enabled",   "Draw W Range")
        Menu.ColorPicker("Draw.W.Color", "Draw W Color", 0x1CA6A1FF) 
		Menu.Checkbox("Draw.E.Enabled",   "Draw E Range")
        Menu.ColorPicker("Draw.E.Color", "Draw E Color", 0x1CA6A1FF)
        Menu.Checkbox("Draw.R.Enabled",   "Draw R Range")
        Menu.ColorPicker("Draw.R.Color", "Draw R Color", 0x0E1E6EFF) 
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

function Lux.GetTargets(range)
    return {TS:GetTarget(range, true)}
end

function Lux.Qdmg()
	return (80 + (spells._Q:GetLevel() - 1) * 45) + (0.6 * Player.TotalAP)
end

function Lux.Edmg()
	return (60 + (spells._E:GetLevel() - 1) * 45) + (0.6 * Player.TotalAP)
end

function Lux.Rdmg()
	return (300 + (spells._R:GetLevel() - 1) * 100) + (1 * Player.TotalAP)
end

function Lux.OnTick()

	local gameTime = Game.GetTime()
    if gameTime < (lastTick + 0.25) then return end
    lastTick = gameTime

	for k, v in pairs(blockList) do
		if gameTime > v + 2.5 then
			blockList[k] = nil
		end
	end
	

	if Lux.KsQ() then return end
	if Lux.KsE() then return end
	if Lux.KsR() then return end
	
	if Orbwalker.GetMode() == "Combo" then
	
		if Menu.Get("Combo.UseQ") then
			local target = Orbwalker.GetTarget() or TS:GetTarget(spells._Q.Range + Player.BoundingRadius, true)
			if target then
				CastQ(target,Menu.Get("Combo.QHC"))
			end
		end
		if Menu.Get("Combo.UseE") then
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
		if Menu.Get("HE") then
			local target = Orbwalker.GetTarget() or TS:GetTarget(spells._E.Range + Player.BoundingRadius, true)
			if target then
				CastE(target,Menu.Get("Combo.EHC"))
			end
		end		
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

function CastE(target,hitChance)
	if Player:GetSpellState(Enums.SpellSlots.E) == SpellStates.Ready then
		local targetAI = target.AsAI
		local ePred = Prediction.GetPredictedPosition(targetAI, spells._E, Player.Position)
		if ePred and ePred.HitChance >= hitChance then
			Input.Cast(SpellSlots.E, ePred.CastPosition)
		end
	end
end


function Lux.KsQ()
  if Menu.Get("KillSteal.Q") then
	for k, qTarget in ipairs(TS:GetTargets(spells._Q.Range, true)) do
		local qDmg = DmgLib.CalculateMagicalDamage(Player, qTarget, Lux.Qdmg())
		local ksHealth = spells._Q:GetKillstealHealth(qTarget)
		if qDmg > ksHealth and spells._Q:CastOnHitChance(qTarget, Enums.HitChance.Medium) then
			return
		end
	end
  end
end

function Lux.KsE()
  if Menu.Get("KillSteal.E") then
	for k, eTarget in ipairs(TS:GetTargets(spells._E.Range, true)) do
		local eDmg = DmgLib.CalculateMagicalDamage(Player, eTarget, Lux.Edmg())
		local ksHealth = spells._E:GetKillstealHealth(eTarget)
		if eDmg > ksHealth and spells._E:CastOnHitChance(eTarget, Enums.HitChance.Medium) then
			return
		end
	end
  end
end
 
function Lux.KsR()
  if Menu.Get("KillSteal.R") then
	for k, rTarget in ipairs(TS:GetTargets(spells._R.Range, true)) do
		local rDmg = DmgLib.CalculateMagicalDamage(Player, rTarget, Lux.Rdmg())
		local ksHealth = spells._R:GetKillstealHealth(rTarget)
		if rDmg > ksHealth and spells._R:CastOnHitChance(rTarget, Enums.HitChance.Medium) then
			return
		end
	end
  end
end


function Lux.OnGapclose(source, dash)
    if not (source.IsEnemy and Menu.Get("AGQ") and spells._Q:IsReady()) then return end

    if source:Distance(Player) < 300 then
        spells._Q:Cast(source)        
        end
    end
	
function Lux.OnHeroImmobilized(source, endT)
	if not source.IsEnemy then return end
	
	if not blockList[source.Handle] and spells._Q:IsReady() and Menu.Get("AQS") then
        if spells._Q:CastOnHitChance(source, Enums.HitChance.VeryHigh) then
            blockList[source.Handle] = Game.GetTime()
            return
        end
    end
end

local function OnProcessSpell(sender,spell)
    local wsa = Menu.Get("WAE")
	local LM = Player.Mana / Player.MaxMana * 100
	local SM = Menu.Get("SLM")
	if SM > LM then
		return
		end
		if  not (sender.IsHero and sender.IsEnemy) then
			return 
		end
		local spellTarget = spell.Target
		if not wsa then return end
		if spellTarget and spellTarget.IsAlly and spellTarget.IsHero and spells._W:IsInRange(spellTarget) and spells._W:IsReady() then
			spells._W:Cast(spell.Target)
		end
	end

function Lux.OnDraw() 
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
    if Player.CharName == "Lux" then
        Lux.LoadMenu()
        for eventName, eventId in pairs(Enums.Events) do
            if Lux[eventName] then
                EventManager.RegisterCallback(eventId, Lux[eventName])
				EventManager.RegisterCallback(Enums.Events.OnProcessSpell, OnProcessSpell)
            end
        end
    end
    return true
end