--[[
    Made by Akane  V1.0
]]

require("common.log")
module("Nebula MasterYi", package.seeall, log.setup)

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
    Q = Spell.Targeted({
        Slot = Enums.SpellSlots.Q,
        Range = 600,
    }),
    W = Spell.Active({
        Slot = Enums.SpellSlots.W,
        Range = 225,
    }),
    E = Spell.Active({
        Slot = Enums.SpellSlots.E,
        Range = 600,
    }),
    R = Spell.Active({
        Slot = Enums.SpellSlots.R,
        Range = 600,
    }),
}

---@type TargetSelector
local TS = _G.Libs.TargetSelector()
local MasterYi = {}
local blockList = {}


function MasterYi.LoadMenu()
    Menu.RegisterMenu("NebulaMasterYi", "Nebula MasterYi", function()
        Menu.ColumnLayout("cols", "cols", 2, true, function()
            Menu.ColoredText("Combo", 0xFFD700FF, true)
            Menu.Checkbox("Combo.UseQ", "Use Q", true)
            Menu.Checkbox("Combo.UseE", "Use E", true)
            Menu.Checkbox("Combo.UseR", "Use R", true)

            Menu.NextColumn()

            Menu.ColoredText("KillSteal", 0xFFD700FF, true)
            Menu.Checkbox("KillSteal.Q", "Use Q", true)

            Menu.NextColumn()

            Menu.ColoredText("Harass", 0xFFD700FF, true)
            Menu.Checkbox("Harass.UseQ", "Use Q", true)
            Menu.Slider("Harass.Mana", "Mana Percent", 50, 0, 100)

            Menu.NextColumn()

            Menu.ColoredText("Misc", 0xFFD700FF, true)
            Menu.Checkbox("WRD", "Use W To Reduce Spell Damage", true)
            Menu.Slider("WH", "Health Percent To Use W Reduce", 50, 0, 100)

            Menu.NextColumn()
            Menu.ColoredText("Clear", 0xFFD700FF, true)
            Menu.Checkbox("Clear.UseQ", "Use Q To Wave Clear", true)
            Menu.Checkbox("Clear.UseQJ", "Use Q To JG Clear", true)
            Menu.Slider("Clear.Mana", "Mana Percent", 50, 0, 100)


        end)

        Menu.Separator()

        Menu.ColoredText("Draw Options", 0xFFD700FF, true)
        Menu.Checkbox("Draw.Q.Enabled",   "Draw Q Range")
        Menu.ColorPicker("Draw.Q.Color", "Draw Q Color", 0x1CA6A1FF)
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

function MasterYi.IsEnabledAndReady(spell, mode)
    return Menu.Get(mode .. ".Use"..spell) and spells[spell]:IsReady()
end

function ValidMinion(minion)
    return minion and minion.IsTargetable and minion.MaxHealth > 6 -- check if not plant or shroom
end

function MasterYi.GetTargets(range)
    return {TS:GetTarget(range, true)}
end

function MasterYi.Qdmg()
    return (25 + (spells.Q:GetLevel() - 1) * 35) + (1 * Player.TotalAD)
end

function MasterYi.OnTick()

    local gameTime = Game.GetTime()
    if gameTime < (lastTick + 0.25) then return end
    lastTick = gameTime

    if MasterYi.KsQ() then return end

    local ModeToExecute = MasterYi[Orbwalker.GetMode()]
    if ModeToExecute then
        ModeToExecute()
    end
end

function MasterYi.ComboLogic(mode)
    if MasterYi.IsEnabledAndReady("Q", mode) then
        for k, qTarget in ipairs(MasterYi.GetTargets(spells.Q.Range)) do
            if spells.Q:Cast(qTarget) then
                return
            end
        end
    end
    if MasterYi.IsEnabledAndReady("E",mode) then
        if spells.E:Cast() then
            return
        end
    end
    if MasterYi.IsEnabledAndReady("R", mode) then
        if spells.R:Cast() then
            return
        end
    end
end
function MasterYi.HarassLogic(mode)
    local man = Player.Mana / Player.MaxMana * 100
    local slm = Menu.Get("Harass.Mana")
    if slm> man then
        return
    end
    if MasterYi.IsEnabledAndReady("Q", mode) then
        for k, qTarget in ipairs(MasterYi.GetTargets(spells.Q.Range)) do
            if spells.Q:Cast(qTarget) then
                return
            end
        end
    end
end


function MasterYi.KsQ()
    if Menu.Get("KillSteal.Q") then
        for k, qTarget in ipairs(TS:GetTargets(spells.Q.Range)) do
            local Qdmg = DmgLib.CalculatePhysicalDamage(Player, qTarget, MasterYi.Qdmg())
            local ksHealth = spells.Q:GetKillstealHealth(qTarget)
            if Qdmg > ksHealth and spells.Q:Cast(qTarget) then
                return
            end
        end
    end
end

local function OnProcessSpell(sender,spell)
    local wrd = Menu.Get("WRD")
    local LM = Player.Mana / Player.MaxMana * 100
    local SM = Menu.Get("Harass.Mana")
    local PH = Player.Health / Player.MaxHealth * 100
    local SH = Menu.Get("WH")
    if SM > LM then
        return
    end
    if PH < SH then
        return
    end
    if not (sender.IsHero and sender.IsEnemy) then
        return
    end
    local spellTarget = spell.Target
    if not wrd then return end
    if spellTarget and spellTarget.IsMe and spellTarget.IsHero and spells.W:IsInRange(spellTarget)and spells.W:IsReady() then
        spells.W:Cast()
    end
end

function MasterYi.OnDraw()
    if Menu.Get("Draw.Q.Enabled") then
        Renderer.DrawCircle3D(Player.Position, spells.Q.Range, 25, 2, Menu.Get("Draw.Q.Color"))
    end
end

function MasterYi.Combo() MasterYi.ComboLogic("Combo") end
function MasterYi.Harass() MasterYi.HarassLogic("Harass") end

function MasterYi.Waveclear() 
    local useQC = Menu.Get("Clear.UseQ")
    local cman = Player.Mana / Player.MaxMana * 100
    local cslm = Menu.Get("Clear.Mana")
    if cslm > cman then
        return
    end
    if spells.Q:IsReady() and useQC then
        for k, v in pairs(ObjManager.Get("enemy", "minions")) do
            local minion = v.AsAI
            sort(minion, function(a, b) return a.MaxHealth > b.MaxHealth end)
            local healthPred = spells.Q:GetHealthPred(minion)
            local minionInRange = minion and minion.MaxHealth > 6 and spells.Q:IsInRange(minion)
            local shouldIgnoreMinion = minion and (Orbwalker.IsLasthitMinion(minion) or Orbwalker.IsIgnoringMinion(minion))

            if minionInRange and not shouldIgnoreMinion and minion.IsTargetable and healthPred > 0 and MasterYi.Qdmg() > healthPred then
                spells.Q:Cast(minion)
            end
        end
    end
    local usejQ = Menu.Get("Clear.UseQJ")
    local cman = Player.Mana / Player.MaxMana * 100
    local cslm = Menu.Get("Clear.Mana")
    if cslm > cman then
        return
    end
    if usejQ and spells.Q:IsReady() then
        for k, v in pairs(ObjManager.Get("neutral", "minions")) do
            local minion = v.AsAI
            local minionInRange = spells.Q:IsInRange(minion)
            if minionInRange and minion.IsMonster  and minion.IsTargetable then
                if spells.Q:Cast(minion) then
                    return
                end
            end
        end
    end
end

function OnLoad()
    if Player.CharName == "MasterYi" then
        MasterYi.LoadMenu()
        for eventName, eventId in pairs(Enums.Events) do
            if MasterYi[eventName] then
                EventManager.RegisterCallback(eventId, MasterYi[eventName])
                EventManager.RegisterCallback(Enums.Events.OnProcessSpell, OnProcessSpell)
            end
        end
    end
    return true
end