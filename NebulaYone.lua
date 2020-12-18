--[[
    Made by Akane  V1.0
]]

require("common.log")
module("Nebula Yone", package.seeall, log.setup)

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
        Range = 450,
        Delay = 0.25,
        Speed = 1500,
        Radius = 100,
        Type = "Linear",
    }),
    Q3 = Spell.Skillshot({
        Slot = Enums.SpellSlots.Q,
        Range = 900,
        Delay = 0.25,
        Speed = 1500,
        Radius = 100,
        Type = "Linear",
    }),
    W = Spell.Skillshot({
        Slot = Enums.SpellSlots.W,
        Range = 600,
        Delay = 0.5,
        Angle = 80,
        Type = "Cone"
    }),
    E = Spell.Active({
        Slot = Enums.SpellSlots.E,
        Range = 450,
        Speed = 1200,
    }),
    R = Spell.Skillshot({
        Slot = Enums.SpellSlots.R,
        Range = 1000,
        Delay = 0.75,
        Speed = 1500,
        Radius = 225,
        Type = "Linear",
    }),
}

---@type TargetSelector
local TS = _G.Libs.TargetSelector()
local Yone = {}
local blockList = {}


function Yone.LoadMenu()
    Menu.RegisterMenu("NebulaYone", "Nebula Yone", function()
        Menu.ColumnLayout("cols", "cols", 2, true, function()
            Menu.ColoredText("Combo", 0xFFD700FF, true)
            Menu.Checkbox("Combo.UseQ", "Use Q", true)
            Menu.Slider("Combo.QHC", "Q HitChance", 0.7, 0, 1, 0.05)
            Menu.Checkbox("Combo.UseQ3", "Use Q3", true)
            Menu.Slider("Combo.Q3HC", "Q3 HitChance", 0.7, 0, 1, 0.05)
            Menu.Checkbox("Combo.UseW", "Use W", true)
            Menu.Checkbox("Combo.UseR", "Use R", true)
            Menu.Slider("RT", "Min Target R", 2, 1, 5, 1)
            Menu.Slider("Combo.RTH", "Health Percent To R", 50, 0, 100, 50)

            Menu.NextColumn()

            Menu.ColoredText("KillSteal", 0xFFD700FF, true)
            Menu.Checkbox("KillSteal.Q", "Use Q", true)
            Menu.Checkbox("KillSteal.R", "Use R", true)

            Menu.NextColumn()

            Menu.ColoredText("Harass", 0xFFD700FF, true)
            Menu.Checkbox("Harass.UseQ", "Use Q", true)
            Menu.Checkbox("Harass.UseW", "Use W", true)

            Menu.NextColumn()
            Menu.ColoredText("Clear", 0xFFD700FF, true)
            Menu.Checkbox("Wave.UseQ", "Use Q To Wave Clear", true)
            Menu.Slider("Wave.CastQHC", "Q Min. Hit Count", 1, 0, 10, 1)
            Menu.Checkbox("Wave.UseW", "Use W To Wave Clear", true)
            Menu.Slider("Wave.CastWHC", "W Min. Hit Count", 1, 0, 10, 1)


        end)

        Menu.Separator()

        Menu.ColoredText("Draw Options", 0xFFD700FF, true)
        Menu.Checkbox("Draw.Q.Enabled",   "Draw Q Range")
        Menu.ColorPicker("Draw.Q.Color", "Draw Q Color", 0x1CA6A1FF)
        Menu.Checkbox("Draw.Q3.Enabled",   "Draw Q3 Range")
        Menu.ColorPicker("Draw.Q3.Color", "Draw Q3 Color", 0x1CA6A1FF)
        Menu.Checkbox("Draw.W.Enabled",   "Draw W Range")
        Menu.ColorPicker("Draw.W.Color", "Draw W Color", 0x1CA6A1FF)
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

function Yone.IsEnabledAndReady(spell, mode)
    return Menu.Get(mode .. ".Use"..spell) and spells[spell]:IsReady()
end

function ValidMinion(minion)
    return minion and minion.IsTargetable and minion.MaxHealth > 6 -- check if not plant or shroom
end

function Yone.GetTargets(range)
    return {TS:GetTarget(range, true)}
end

function Yone.Qdmg()
    return (20 + (spells.Q:GetLevel() - 1) * 20) + (1 * Player.TotalAD)
end

function Yone.Wdmg()
    return (10 + (spells.W:GetLevel() - 1) * 10)
end

function Yone.Rdmg()
    return (200 + (spells.R:GetLevel() - 1) * 200) + (0.8 + Player.TotalAD)
end

function CountEnemiesInRange(pos, range, t)
    local res = 0
    for k, v in pairs(t or ObjManager.Get("neutral", "minions")) do
        local hero = v.AsAI
        if hero and hero.IsTargetable and hero:Distance(pos) < range then
            res = res + 1
        end
    end
    return res
end
function CountEnemiesHeroesInRange(pos, range, t)
    local res = 0
    for k, v in pairs(t or ObjManager.Get("enemy", "heroes")) do
        local hero = v.AsAI
        if hero and hero.IsTargetable and hero:Distance(pos) < range then
            res = res + 1
        end
    end
    return res
end

function Yone.OnTick()

    local gameTime = Game.GetTime()
    if gameTime < (lastTick + 0.25) then return end
    lastTick = gameTime
    
    if Yone.KsQ() then return end
    if Yone.KsR() then return end

    if Orbwalker.GetMode() == "Waveclear" then
        Yone.Waveclear()
    end

    local ModeToExecute = Yone[Orbwalker.GetMode()]
    if ModeToExecute then
        ModeToExecute()
    end
end

function Yone.ComboLogic(mode)
    if Yone.IsEnabledAndReady("Q", mode) and not Player:GetBuff("yoneq3ready") then
        local qChance = Menu.Get(mode .. ".QHC")
        for k, qTarget in ipairs(Yone.GetTargets(spells.Q.Range)) do
            if spells.Q:CastOnHitChance(qTarget, qChance) then
                return
            end
        end
    end
    if Yone.IsEnabledAndReady("Q3", mode) and Player:GetBuff("yoneq3ready") then
        local q3Chance = Menu.Get(mode .. ".Q3HC")
        for k, q3Target in ipairs(Yone.GetTargets(spells.Q3.Range)) do
            if spells.Q3:CastOnHitChance(q3Target, q3Chance) then
                return
            end
        end
    end
    if Yone.IsEnabledAndReady("W", mode) then
        for k, wTarget in ipairs(Yone.GetTargets(spells.W.Range)) do
            if spells.W:Cast(wTarget) then
                return
            end
        end
    end
    if Yone.IsEnabledAndReady("R", mode) then
        for k, rTarget in ipairs(Yone.GetTargets(spells.R.Range)) do
            local HP = rTarget.Health / rTarget.MaxHealth * 100
            local hps = Menu.Get("Combo.RTH")
            if hps < HP then
                return
            end
            if #TS:GetTargets(spells.R.Range, true) >= Menu.Get("RT") then
                spells.R:Cast(rTarget) return
            end
        end
    end
end
function Yone.HarassLogic(mode)
    if Yone.IsEnabledAndReady("Q", mode) and not Player:GetBuff("yoneq3ready") then
        local qChance = Menu.Get("Combo.QHC")
        for k, qTarget in ipairs(Yone.GetTargets(spells.Q.Range)) do
            if spells.Q:CastOnHitChance(qTarget, qChance) then
                return
            end
        end
    end
    if Yone.IsEnabledAndReady("W", mode) then
        for k, wTarget in ipairs(Yone.GetTargets(spells.W.Range)) do
            if spells.W:Cast(wTarget) then
                return
            end
        end
    end
end

function Yone.KsQ()
    if Menu.Get("KillSteal.Q") then
        for k, qTarget in ipairs(TS:GetTargets(spells.Q.Range, true)) do
            local qDmg = DmgLib.CalculatePhysicalDamage(Player, qTarget, Yone.Qdmg())
            local ksHealth = spells.Q:GetKillstealHealth(qTarget)
            if qDmg > ksHealth and spells.Q:Cast(qTarget) then
                return
            end
        end
    end
end

function Yone.KsR()
    if Menu.Get("KillSteal.R") then
        for k, rTarget in ipairs(TS:GetTargets(spells.R.Range, true)) do
            local rDmg = DmgLib.CalculatePhysicalDamage(Player, rTarget, Yone.Rdmg())
            local ksHealth = spells.R:GetKillstealHealth(rTarget)
            if rDmg > ksHealth and spells.R:Cast(rTarget) then
                return
            end
        end
    end
end

function Yone.OnDraw()
    if Menu.Get("Draw.Q.Enabled") then
        Renderer.DrawCircle3D(Player.Position, spells.Q.Range, 25, 2, Menu.Get("Draw.Q.Color"))
    end
    if Menu.Get("Draw.Q3.Enabled") and Player:GetBuff("yoneq3ready") then
        Renderer.DrawCircle3D(Player.Position, spells.Q3.Range, 25, 2, Menu.Get("Draw.Q.Color"))
    end
    if Menu.Get("Draw.W.Enabled") then
        Renderer.DrawCircle3D(Player.Position, spells.W.Range, 25, 2, Menu.Get("Draw.W.Color"))
    end
    if Menu.Get("Draw.R.Enabled") then
        Renderer.DrawCircle3D(Player.Position, spells.R.Range, 25, 2, Menu.Get("Draw.R.Color"))
    end
end

function Yone.Combo() Yone.ComboLogic("Combo") end
function Yone.Harass() Yone.HarassLogic("Harass") end

function Yone.Waveclear()
    
    local pPos, pointsQ, pointsW = Player.Position, {}, {}
    
    -- enemy minions
    for k, v in pairs(ObjManager.Get("enemy", "minions")) do
        local minion = v.AsAI
        if ValidMinion(minion) then
            local posW = minion:FastPrediction(spells.W.Delay)
            local posQ = minion:FastPrediction(spells.Q.Delay)
            if posQ:Distance(pPos) < spells.Q.Range and minion.IsTargetable then
                table.insert(pointsQ, posQ)
            end
            if posW:Distance(pPos) < spells.W.Range and minion.IsTargetable then
                table.insert(pointsW, posW)
            end
        end
    end
    
    --Jungle minions
    if #pointsQ == 0 or pointsW == 0 then
        for k, v in pairs(ObjManager.Get("neutral", "minions")) do
            local minion = v.AsAI
            if ValidMinion(minion) then
                local posW = minion:FastPrediction(spells.W.Delay)
                local posQ = minion:FastPrediction(spells.Q.Delay)
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

function OnLoad()
    if Player.CharName == "Yone" then
        Yone.LoadMenu()
        for eventName, eventId in pairs(Enums.Events) do
            if Yone[eventName] then
                EventManager.RegisterCallback(eventId, Yone[eventName])
            end
        end
    end
    return true
end