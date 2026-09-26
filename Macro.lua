-- RocketSwap | Macro.lua
-- One macro per preset, in the CHARACTER's macros, put on an empty action bar slot.
--
-- The user (25/09): *"quando salvar o conjunto já criar a macro com o icone usado já e jogar
-- para um espaço vazio da barra e/ou informar que a macro foi criada (com mesmo nome do
-- conjunto)"* -- and then: *"nas macros especificas e não na geral"*.
--
-- (!) THE MACRO CANNOT BE "/rs <name>". That runs our code, and our code cannot change the
-- transmog outfit: it is a secure action, done only by a player's click on a secure button
-- (UI.lua, `ArmOutfit`; Data.lua explains the three rounds it took to learn that). So each preset
-- gets a secure button with a FIXED global name, and the macro clicks it:
--
--     /click RocketSwapPreset7 LeftButton 1
--
-- which the game counts as the player's click, so the outfit changes too. The button recipe is
-- EnhanceQoL's (`Submodules/MountActions.lua:553-563`): `RegisterForClicks("AnyDown")` plus
-- `pressAndHoldAction`, with "LeftButton 1" in the macro, so the click lands whether or not the
-- player has "cast on key down" on. Putting the macro on a bar is `PickupMacro` + `PlaceAction`
-- out of combat, the way ZygorGuidesViewer does it (`MacroGuide.lua:315-335`).
local ADDON, ns = ...
local L = ns.L

local Macro = {}
ns.Macro = Macro

local PREFIX = "RocketSwapPreset"
-- The game's macro name limit, in characters.
local NAME_MAX = 16
local QUESTION_MARK = 134400      -- INV_Misc_QuestionMark

-- The bars searched for an empty VISIBLE slot, the extra bars first: the main bar pages with
-- stances and forms, and a slot there can belong to a druid's cat form.
local BARS = {
    "MultiBarBottomLeftButton", "MultiBarBottomRightButton", "MultiBarRightButton",
    "MultiBarLeftButton", "MultiBar5Button", "MultiBar6Button", "MultiBar7Button",
    "ActionButton",
}

-- The number Edit Mode gives each bar ("Action Bar 3"), so the chat can say WHERE the macro went:
-- the log of 26/09 had it placed in slot 52 -- bar 3, 4th button -- and the player did not find it.
local BAR_NUMBER = {
    ActionButton = 1, MultiBarBottomLeftButton = 2, MultiBarBottomRightButton = 3,
    MultiBarRightButton = 4, MultiBarLeftButton = 5, MultiBar5Button = 6, MultiBar6Button = 7,
    MultiBar7Button = 8,
}

local buttons = {}            -- uid -> secure button
local waiting = {}            -- preset -> true while its macro waits for the end of combat
                              -- (kept here, not on the preset: the preset is saved to disk)
local pending = {}            -- work waiting for the end of combat: { fn, arg }

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------
---A preset's id for its button. Names change and positions shift; the button's name must not.
local function Uid(preset)
    if not preset.uid then
        ns.db.nextUid = (ns.db.nextUid or 0) + 1
        preset.uid = ns.db.nextUid
    end
    return preset.uid
end

function Macro.ButtonName(preset)
    return PREFIX .. Uid(preset)
end

function Macro.Body(preset)
    return "/click " .. Macro.ButtonName(preset) .. " LeftButton 1"
end

---The preset's name cut to the game's limit WITHOUT splitting a character: "Mítica" is 7 bytes
---for 6 letters, and a byte cut would leave half a letter.
function Macro.Name(preset)
    local name = preset.name or ""
    local out, n = {}, 0
    for ch in name:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        n = n + 1
        if n > NAME_MAX then break end
        out[#out + 1] = ch
    end
    return table.concat(out)
end

---The icon the window shows for the preset: its equipment set's, else its specialization's.
function Macro.Icon(preset)
    local _, icon = ns.Data.GearSetName(preset.gear)
    if icon then return icon end
    local spec = preset.spec and ns.Data.GetSpecByIndex(preset.spec)
    return spec and spec.icon or QUESTION_MARK
end

local function PresetByUid(uid)
    for _, p in ipairs(ns.db and ns.db.presets or {}) do
        if p.uid == uid then return p end
    end
end

---The index of OUR macro for this preset, found by its body -- never by name, since the player may
---have another macro with the same name, and ours may have been renamed.
local function OurIndex(preset)
    if not (preset.uid and GetNumMacros and GetMacroBody) then return nil end
    local marca = PREFIX .. preset.uid .. " "
    local global, char = GetNumMacros()
    local first = (MAX_ACCOUNT_MACROS or 120) + 1
    for i = first, first + (char or 0) - 1 do
        local body = GetMacroBody(i)
        if body and body:find(marca, 1, true) then return i end
    end
end

local function Later(fn, arg)
    pending[#pending + 1] = { fn = fn, arg = arg }
end

--------------------------------------------------------------------------------
-- The secure button
--------------------------------------------------------------------------------
---Creates (or finds) the preset's secure button. Out of combat only: a secure frame cannot be
---set up in combat.
function Macro.Button(preset)
    local uid = Uid(preset)
    if buttons[uid] then return buttons[uid] end
    if InCombatLockdown() then return nil end
    local b = CreateFrame("Button", PREFIX .. uid, UIParent, "SecureActionButtonTemplate")
    b:RegisterForClicks("AnyDown")
    b:SetAttribute("pressAndHoldAction", true)
    b.uid = uid
    -- The outfit is armed at the moment of the click, from the preset as it is THEN: outfits are
    -- found by index, and the index moves when the player adds or deletes one.
    b:SetScript("PreClick", function(self)
        local p = PresetByUid(self.uid)
        if p and not InCombatLockdown() then ns.UI.ArmOutfit(self, p) end
    end)
    b:SetScript("PostClick", function(self)
        local p = PresetByUid(self.uid)
        if p then ns.UI.Load(p) end
    end)
    buttons[uid] = b
    return b
end

--------------------------------------------------------------------------------
-- The action bar
--------------------------------------------------------------------------------
---What the addon sees of the bars: for `/rs macrobar` and the log. Written after the first test in
---the game (25/09): *"criou a macro, só não jogou o icone pra barra"* -- and nothing saved could say
---whether no empty slot was found or the slot was found and the game did not take the macro.
---
---(!) AN EMPTY SLOT IS NOT A VISIBLE BUTTON (found 25-26/09 from the log). The first version
---asked each BUTTON `IsVisible()`, and the log answered "no empty slot" on a character with empty
---slots on four visible bars. Blizzard's own rule (`Blizzard_ActionBar/Shared/ActionBar.lua`,
---`UpdateShownButtons`, wow-ui-source) shows a button only when
---    index <= bar.numButtonsShowable and not statehidden and (grid shown or HasAction)
----- so with "Always Show Buttons" off EVERY empty slot is hidden. A slot is usable when its BAR is
---visible, its index is within the icons the player set for that bar in Edit Mode, and it is not
---hidden by state. Once the macro is in, the game shows the button itself (it now has an action).
local function Utilizavel(b)
    local bar = b.bar
    if bar then
        if not (bar.IsVisible and bar:IsVisible()) then return false end
        if b.index and bar.numButtonsShowable and b.index > bar.numButtonsShowable then return false end
    elseif not (b.IsVisible and b:IsVisible()) then
        return false               -- no bar to ask: fall back to the button itself
    end
    if b.GetAttribute and b:GetAttribute("statehidden") then return false end
    return true
end

function Macro.Survey()
    local out = { bars = {}, empty = {}, where = {} }
    for _, bar in ipairs(BARS) do
        local info = { name = bar, found = 0, visible = 0, empty = 0, noAction = 0 }
        for i = 1, 12 do
            local b = _G[bar .. i]
            if b then
                info.found = info.found + 1
                local usavel = Utilizavel(b)
                if usavel then info.visible = info.visible + 1 end
                if not b.action then
                    info.noAction = info.noAction + 1
                elseif usavel and HasAction and not HasAction(b.action) then
                    info.empty = info.empty + 1
                    out.empty[#out.empty + 1] = b.action
                    out.where[b.action] = { bar = BAR_NUMBER[bar], button = i }
                end
            end
        end
        out.bars[#out.bars + 1] = info
    end
    out.cursor = GetCursorInfo and GetCursorInfo() or nil
    return out
end

---Is OUR macro in that slot? The only proof that `PlaceAction` took.
local function MacroIn(slot, index)
    if not GetActionInfo then return HasAction and HasAction(slot) end
    local tipo, id = GetActionInfo(slot)
    return tipo == "macro" and id == index
end

---"Action Bar 3, button 4", in the game's words where it has them.
function Macro.WhereText(where)
    if not where then return nil end
    local barra = _G.HUD_EDIT_MODE_ACTION_BAR_LABEL and string.format(_G.HUD_EDIT_MODE_ACTION_BAR_LABEL, where.bar)
        or string.format(L["Action Bar %d"], where.bar)
    return string.format(L["%s, button %d"], barra, where.button)
end

---Puts the macro on the first empty slot of a visible bar, and CHECKS that it is there. Returns
---true and where it went (see `WhereText`) only when the slot holds our macro afterwards.
function Macro.PlaceOnBar(index)
    if not (PickupMacro and PlaceAction and HasAction) then
        ns.Log.Add("macro-barra", { desfecho = "sem API" })
        return false
    end
    local cursor = GetCursorInfo and GetCursorInfo()
    if cursor then           -- the player is holding something
        ns.Log.Add("macro-barra", { desfecho = "cursor ocupado", cursor = tostring(cursor) })
        return false
    end
    local survey = Macro.Survey()
    local slot = survey.empty[1]
    if not slot then
        local resumo = {}
        for _, b in ipairs(survey.bars) do
            resumo[#resumo + 1] = string.format("%s=%d/%d/%d", b.name, b.found, b.visible, b.empty)
        end
        ns.Log.Add("macro-barra", { desfecho = "sem vaga", barras = table.concat(resumo, " ") })
        return false
    end
    local okP, errP = pcall(PickupMacro, index)
    local naMao = GetCursorInfo and GetCursorInfo()
    local okA, errA = pcall(PlaceAction, slot)
    if ClearCursor then ClearCursor() end
    local ficou = MacroIn(slot, index)
    ns.Log.Add("macro-barra", {
        desfecho = ficou and "colocada" or "nao ficou", slot = slot, macro = index,
        pegou = okP and tostring(naMao) or ("erro: " .. tostring(errP)),
        colocou = okA and "ok" or ("erro: " .. tostring(errA)),
        barra = survey.where[slot] and survey.where[slot].bar,
        botao = survey.where[slot] and survey.where[slot].button,
    })
    if ficou then return true, survey.where[slot] end
    return false
end

---THE "PUT ON THE BAR" BUTTON (26/09). The user: *"se colocar um botão de salvar na parte das
---seleções do preset e forçar a ir para a barra"*. The macro goes on the CURSOR, as the game's own
---macro window does it (`PickupMacro`), and the player clicks the slot they want -- no guessing
---which slot they can see. Made (or remade) first when it does not exist.
---@return boolean ok, string|nil why
function Macro.PickUp(preset)
    if not preset or not preset.name or preset.name == "" then return false, "noname" end
    if InCombatLockdown() then return false, "combat" end
    if not (PickupMacro and CreateMacro) then return false, "noapi" end
    local idx = OurIndex(preset)
    if not idx then
        preset.macroMade = nil
        Macro.Sync(preset, true)
        idx = OurIndex(preset)
    else
        Macro.Sync(preset, true)
    end
    if not idx then return false, "full" end
    if ClearCursor then ClearCursor() end
    local ok = pcall(PickupMacro, idx)
    ns.Log.Add("macro-cursor", { macro = idx, ok = ok and true or false })
    return ok, ok and nil or "error"
end

--------------------------------------------------------------------------------
-- Keeping the macro in step with the preset
--------------------------------------------------------------------------------
---Creates the macro the first time the preset has a name; afterwards keeps name and icon in step.
-- While the "Put on the bar" button works, nothing is placed on its own: the button puts the macro
-- on the cursor, and an automatic copy in some slot would be a second one the player did not ask for.
local semColocar = false
function Macro.WithoutAutoPlace(fn)
    semColocar = true
    local ok, err = pcall(fn)
    semColocar = false
    if not ok then error(err, 0) end
end

function Macro.Sync(preset, porBotao)
    if not preset or not preset.name or preset.name == "" then return end
    porBotao = porBotao or semColocar
    if not (CreateMacro and EditMacro and GetNumMacros) then return end
    if InCombatLockdown() then
        if not waiting[preset] then
            waiting[preset] = true
            Later(Macro.Sync, preset)
            ns.Print(L["in combat: the preset's macro will be made when the fight ends."])
        end
        return
    end
    waiting[preset] = nil
    Macro.Button(preset)

    local nome, icone, corpo = Macro.Name(preset), Macro.Icon(preset), Macro.Body(preset)
    local idx = OurIndex(preset)
    if idx then
        local antigo = GetMacroInfo and GetMacroInfo(idx)
        EditMacro(idx, nome, icone, corpo)
        if antigo and antigo ~= nome then
            ns.Print(string.format(L["macro renamed: %s"], nome))
        end
        return
    end

    -- Created once. A player who later deletes it from /macro has said no: it is not remade on
    -- every edit (`/rs macro` makes it again on purpose).
    if preset.macroMade then return end

    local _, char = GetNumMacros()
    local max = MAX_CHARACTER_MACROS or 18
    if (char or 0) >= max then
        ns.Print(string.format(L["this character's macros are full (%d of %d): the preset has no macro."],
            char, max))
        return
    end
    local novo = CreateMacro(nome, icone, corpo, true)
    if not novo then return end
    preset.macroMade = true
    if porBotao then return end          -- the button puts it on the cursor itself
    local colocou, onde = Macro.PlaceOnBar(novo)
    if colocou then
        ns.Print(string.format(L["macro created in this character's macros and placed on your action bar: %s"], nome)
            .. (onde and ("  (" .. Macro.WhereText(onde) .. ")") or ""))
    else
        ns.Print(string.format(L["macro created in this character's macros (no empty slot on a visible bar, drag it from /macro): %s"], nome))
    end
end

---The preset is going away: its macro goes too (only ours, found by its body).
function Macro.Remove(preset)
    if not preset or not preset.uid then return end
    if InCombatLockdown() then
        Later(Macro.Remove, { uid = preset.uid, name = preset.name })
        return
    end
    local idx = OurIndex(preset)
    if idx and DeleteMacro then
        local nome = GetMacroInfo and GetMacroInfo(idx) or preset.name
        DeleteMacro(idx)
        ns.Print(string.format(L["macro deleted with the preset: %s"], nome or "?"))
    end
end

---`/rs macro`: a macro for every named preset -- the ones saved before this existed, or one the
---player deleted and wants back.
function Macro.All()
    for _, p in ipairs(ns.db and ns.db.presets or {}) do
        if p.name and p.name ~= "" then
            if not OurIndex(p) then p.macroMade = nil end
            Macro.Sync(p)
        end
    end
end

---At login: the buttons the macros click have to exist again (they are not saved).
function Macro.Restore()
    if InCombatLockdown() then Later(Macro.Restore) return end
    for _, p in ipairs(ns.db and ns.db.presets or {}) do
        if p.macroMade or OurIndex(p) then Macro.Button(p) end
    end
end

function Macro.CombatEnded()
    local fila = pending
    pending = {}
    for _, t in ipairs(fila) do t.fn(t.arg) end
end
