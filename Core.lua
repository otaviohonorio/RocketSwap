-- RocketSwap | Core.lua
-- Namespace do addon: tudo que for compartilhado entre arquivos vai em `ns`.
local ADDON, ns = ...

-- (!) THE ADDON'S OWN ICON (06/10/2026). The three addons had the game's icons (two of them the
-- SAME one, so the list of addons showed them alike). The art is ours and ships in `Textures/`:
-- the rocket of the three addons with this addon's badge. One file serves every place: the
-- addon list (`## IconTexture`), the minimap button (masked round) and the window's portrait.
ns.LOGO = "Interface\\AddOns\\" .. ADDON .. "\\Textures\\Logo.png"
-- The minimap button is some 20 points wide: there the rocket would be a smudge, so it takes
-- the BADGE alone, large (06/10: "no icone do minimap tem que ficar apenas o redondo que fica
-- no canto sem o foguete, pq e muito pequeno pra ver qual e").
ns.LOGO_MINIMAP = "Interface\\AddOns\\" .. ADDON .. "\\Textures\\Minimap.png"
local L = ns.L

-- The version comes from the .toc, never from a constant here: a number in two places becomes a
-- wrong number in one of them. (Standardised with RocketMeter on 05/09/2026.)
ns.version = C_AddOns.GetAddOnMetadata(ADDON, "Version") or "0.0.0"

ns.defaults = {
    presets = {},        -- { { name, spec, talent, gear }, ... }
    last = nil,          -- nome do ultimo conjunto carregado, para o clique direito
    minimap = { angle = 210 },
    pos = nil,

    -- The two warnings, on by default: they are what the addon does for whoever never makes
    -- a set. They are turned off with /rs warn and /rs ready.
    -- (!) ONE PER CONTEXT (22/09). It was a single key (`warn`) for both contents, and the
    -- request was to split it: *"tem como separar os avisos para PVP e PVE?"*. It makes sense because
    -- the two situations do not go together -- whoever does mythic+ every night and PvP now and then
    -- wants the warning on in one and quiet in the other, and with one key had to choose.
    --
    -- The old key is still read once, in the migration (see `Core.lua`, ADDON_LOADED): whoever
    -- had turned the warning off cannot see it come back by itself.
    warnPvE = true,       -- equipamento de PvP em masmorra ou raide
    warnPvP = true,       -- equipamento de PvE em arena ou campo de batalha
    readyCheck = true,    -- resumo do que voce esta usando, no ready check
    queuePop = true,      -- o mesmo resumo quando a fila de PvP chama (convite na tela)

    -- ⚑ WAR MODE STARTS QUIET (request of 12/09: *"tira o alerta dos itens de pvp em mundo
    -- aberto no war mode, ou transforma em opcao por padrao desmarcada"*).
    --
    -- The context STAYS -- it exists by his own request, of 08/09 (*"inclusive quando seto para
    -- pvp, habilitando o war mode on, sem avisos"*) --, but its warning becomes opt-in. The
    -- reason is the difference between the two situations: a PvP match is a closed window where
    -- the wrong gear costs the match; War Mode is the open world, where most of the time is
    -- quests and farming, and the warning shows with nothing going on.
    warnWarMode = false,  -- avisar tambem com Modo Guerra ligado, no mundo aberto
    muted = {},           -- situacoes que o usuario mandou calar
    mutedSlots = {},      -- slots que o usuario mandou calar
}

-- THE LOG IS A DEVELOPMENT TOOL, AND IT DOES NOT GO IN THE PACKAGE. The user's rule (23/09):
-- *"quando forem publicados não devem gerar os logs, por que vai ficar consumindo espaço e disco
-- do usuário, apenas aqui para desenvolvimento"*. `Log.lua` and `RocketSwapLogDB` sit in
-- `#@debug@` in the .toc, which the packager removes from EVERY build (alpha included), and the
-- `.pkgmeta` takes the file out of the zip.
--
-- This stand-in is what the player gets: every call answers nothing, so the ~30 calls to the
-- log spread over the addon need no guard, and forgetting one does not break the published
-- version. In development `Log.lua`, loaded after this file, swaps it for the real one.
ns.Log = setmetatable({ enabled = false }, {
    __index = function() return function() end end,
})

-- (!) THE ADDON'S NAME, AS THE PLAYER READS IT (29/09). The user, looking at the three minimap
-- buttons: *"Rocket Mount, Rocket Meter estão com esse espaço e pintada a palavra rocket, o swap
-- não tá nesse padrão"* -- this one said "RocketSwap", the folder's name, in white. The
-- workspace's format is the .toc's `## Title`: "Rocket" in the orange of the three addons, a
-- space, the name. `NAME` is the same without the colour, for where the game paints the text
-- itself (a window's title bar).
ns.TITLE = "|cffff6a00Rocket|r Swap"
ns.NAME = "Rocket Swap"

function ns.Print(...)
    print(ns.TITLE .. ":", ...)
end

--------------------------------------------------------------------------------
-- Fila de combate: trocar spec, talentos ou itens e proibido com o combate travado.
--------------------------------------------------------------------------------
local queue = {}

function ns.RunWhenSafe(fn)
    if InCombatLockdown() then
        queue[#queue + 1] = fn
    else
        fn()
    end
end

local function FlushQueue()
    if #queue == 0 then return end
    local pending = queue
    queue = {}
    for i = 1, #pending do
        pending[i]()
    end
end

--------------------------------------------------------------------------------
-- Icone: escolher sem chutar
--------------------------------------------------------------------------------
--- Returns the first texture path of the list that EXISTS in this client.
---
--- `SetTexture` with a path that does not exist fails SILENTLY -- the button stays empty and nothing
--- warns. An icon name is the kind of thing I cannot confirm on disk (the textures live in the
--- CASC, not in the addons folder), so up to here I was hoping.
---
--- `GetFileIDFromPath` solves it: it returns the file's id, or nil if the path does not exist.
--- It is documented API of 12.1.0 (`ClientDocumentation.lua:29`), and works exactly as an
--- existence test.
--- @param paths string[] candidates, from the preferred one to the last resort
--- @return string|nil path, boolean checked
function ns.FirstIcon(paths)
    if type(GetFileIDFromPath) ~= "function" then
        return paths[#paths], false     -- sem como verificar: usa o ultimo recurso
    end

    for _, path in ipairs(paths) do
        local ok, id = pcall(GetFileIDFromPath, path)
        if ok and id then return path, true end
    end
    return paths[#paths], false
end

--------------------------------------------------------------------------------
--- Applies an atlas ONLY IF it exists in this client, and says whether it worked.
---
--- This function was already called in two places (`UI.lua:365` and `:472`) and **never existed**:
--- the guard `if not ns.SetAtlasSafe` always fell to plan B, so the column's divider never even
--- tried Blizzard's art. Code that reads as "try the atlas, else use the colour" doing only the
--- second half -- and with nothing flagging it, because the guard was right.
---
--- `SetAtlas` with a name that does not exist fails SILENTLY and leaves the texture blank, the
--- hardest symptom to diagnose: there is no error, only an empty rectangle. `GetAtlasInfo`
--- returns nil for an atlas that does not exist, and `GetAtlas()` after `SetAtlas` confirms it
--- took -- both checks, because one alone already let a blue header through here.
--- @param texture table
--- @param atlas string
--- @return boolean applied
function ns.SetAtlasSafe(texture, atlas)
    if not texture or not atlas or not texture.SetAtlas then return false end

    if C_Texture and C_Texture.GetAtlasInfo then
        local ok, info = pcall(C_Texture.GetAtlasInfo, atlas)
        if not ok or not info then return false end
    end

    if not pcall(texture.SetAtlas, texture, atlas) then return false end
    if not texture.GetAtlas then return false end
    return texture:GetAtlas() ~= nil
end

--------------------------------------------------------------------------------
--- The window, without closing the one already open.
---
--- `UI.Toggle` toggles, so calling it with the window open CLOSES it -- and the shortcut meant to
--- show a set ended up hiding everything.
local function Abrir()
    if ns.UI.IsShown and ns.UI.IsShown() then return end
    ns.UI.Toggle()
end

--- Loads a set by the SHORTCUT path: the minimap menu or `/rs load`.
---
--- (!) A SHORTCUT IS NOT A SECURE CLICK, and that difference decides what can be done here.
---
--- A SET WITH AN APPEARANCE IS NOT APPLIED THIS WAY. The appearance swap only happens on the
--- SECURE BUTTON's click, and what happened was worse than not working:
---
---  1. the appearance never went in, so `IsLoaded` never came out true;
---  2. with `IsLoaded` false, the shortcut APPLIED everything AGAIN at every use -- and the player saw
---     "do nada ele seta o item que ja deveria estar setado", which was the report;
---  3. and it was still a partial swap, the worst of both worlds.
---
--- So the shortcut opens the window with that set selected. One click more, and the right
--- click -- the one that makes the WHOLE swap.
--- @return boolean really switched
function ns.LoadPreset(preset)
    if not preset then return false end

    -- Without a name it does not load (`Data.HasName`): the window opens on it, where the name
    -- is typed.
    if not ns.Data.HasName(preset) then
        Abrir()
        ns.UI.Select(preset)
        ns.UI.SetStatus(L["Give the preset a name first."], true)
        ns.Print(L["Give the preset a name first."])
        return false
    end

    if preset.transmog then
        Abrir()
        ns.UI.Select(preset)
        ns.Print(format(L["click Load to switch to %s completely."], preset.name or "?"))
        return false
    end

    ns.Data.Apply(preset, function(text, isError)
        ns.UI.SetStatus(text, isError)
        if isError then ns.Print(text) end
    end)
    return true
end

--- The set used last, by name. It is left for `/rs load` with no argument and for whoever
--- called from outside; the minimap does NOT use this any more -- see the comment in `Minimap.lua`.
function ns.LoadLast()
    local wanted = ns.db and ns.db.last
    if not wanted then
        Abrir()
        return false
    end
    for _, preset in ipairs(ns.db.presets) do
        if preset.name == wanted then
            return ns.LoadPreset(preset)
        end
    end
    Abrir()
    return false
end

--------------------------------------------------------------------------------
-- Eventos
--------------------------------------------------------------------------------
local handlers = {}

function handlers:ADDON_LOADED(addon)
    if addon ~= ADDON then return end

    -- SavedVariables so existem a partir daqui.
    RocketSwapDB = RocketSwapDB or {}
    -- (!) MIGRATION OF THE SINGLE KEY `warn` TO THE TWO PER CONTEXT (0.35.0).
    --
    -- It runs BEFORE the defaults, on purpose: after them, `warnPvE`/`warnPvP` would already be born
    -- `true` and the choice of whoever had TURNED the warning OFF would be lost -- an option that comes
    -- back by itself is the worst way to break trust in an option.
    if RocketSwapDB and RocketSwapDB.warn ~= nil then
        if RocketSwapDB.warnPvE == nil then RocketSwapDB.warnPvE = RocketSwapDB.warn end
        if RocketSwapDB.warnPvP == nil then RocketSwapDB.warnPvP = RocketSwapDB.warn end
        RocketSwapDB.warn = nil
    end

    for k, v in pairs(ns.defaults) do
        if RocketSwapDB[k] == nil then
            RocketSwapDB[k] = type(v) == "table" and CopyTable(v) or v
        end
    end
    ns.db = RocketSwapDB

    -- THE LOG'S HEADER: version, language and when it started. Without it the file arrived without
    -- saying which build it is from -- and the first thing asked when reading a log is "when is
    -- this from?". `Log.Init` existed and had no caller.
    if ns.Log then ns.Log.Init() end
end

function handlers:PLAYER_LOGIN()
    ns.Minimap.Create()
    ns.Alert.Create()
    -- The secure buttons the presets' macros click are not saved: they are made again here.
    if ns.Macro then ns.Macro.Restore() end
    ns.Print(format(L["loaded. %d preset(s). Type /rs."], #ns.db.presets))
end

function handlers:PLAYER_REGEN_ENABLED()
    FlushQueue()
    if ns.Macro then ns.Macro.CombatEnded() end
end

-- Swaps made by hand (from the character sheet or the talents window) change which set is
-- active. The window has to follow, or the check mark lies.
function handlers:EQUIPMENT_SETS_CHANGED()
    ns.UI.Refresh()
    ns.Minimap.Refresh()
end
function handlers:PLAYER_EQUIPMENT_CHANGED()
    ns.UI.Refresh()
    ns.Minimap.Refresh()
end
function handlers:TRAIT_CONFIG_UPDATED() ns.UI.Refresh() end
function handlers:ACTIVE_PLAYER_SPECIALIZATION_CHANGED() ns.UI.Refresh() end

-- THE EVENTS THAT CHANGE "CAN THE SPEC BE SWITCHED NOW?".
--
-- The Load button stays dimmed while the game does not allow it, and dimmed without re-checking
-- would be worse than not dimming: the player would be left with a dead button not knowing when it
-- comes back. These three are the ones the talents window itself listens to in order to enable its
-- button again (`Blizzard_ClassSpecializationsFrame.lua:69-73`), plus the end of combat, above.
--
-- `PLAYER_SPECIALIZATION_CHANGED` besides `ACTIVE_...`: the first covers the WHOLE process of the
-- switch (Blizzard registers both, and its comment says this one "needs to always be
-- registered so that the entire spec change process is always captured").
function handlers:PLAYER_SPECIALIZATION_CHANGED() ns.UI.Refresh() end

-- Walking cancels the spec switch's cast, and `SPECIALIZATION_CHANGE_CAST_FAILED` does not cover
-- it -- which is why the native window listens to these two.
-- LEARNS THE SPEC SWITCH SPELL. There is no constant for it in the client's documentation -- what
-- there is is the predicate `IsSpecializationActivateSpell`, which the talents window uses to
-- recognise its cast. So the addon asks the game, once, and keeps it.
--
-- Without it there is no knowing when the switch becomes possible again, and the button is either
-- dimmed too little (the reported case) or too much.
function handlers:UNIT_SPELLCAST_SUCCEEDED(unit, _castGUID, spellID)
    if unit ~= "player" then return end
    ns.Data.NoteSpellCast(spellID)
    ns.UI.Refresh()
end

function handlers:UNIT_SPELLCAST_FAILED() ns.UI.Refresh() end
function handlers:UNIT_SPELLCAST_INTERRUPTED() ns.UI.Refresh() end

-- And the end of the deadline/cooldown fires no event of its own: `SPELL_UPDATE_COOLDOWN` is what
-- says some cooldown moved, and it is the hook the native frame uses to redraw the cooldown of the
-- appearance set button (`Blizzard_TransmogTemplates.lua:57-61`).
function handlers:SPELL_UPDATE_COOLDOWN() ns.UI.Refresh() end

local frame = CreateFrame("Frame", ADDON .. "EventFrame")
for event in pairs(handlers) do
    frame:RegisterEvent(event)
end
frame:SetScript("OnEvent", function(self, event, ...)
    handlers[event](self, ...)
end)

ns.frame = frame


-- (25/10) DARK EVERYWHERE (the workspace rules, visual identity: the user chose the app's look as the reference and,
-- asked, "escuro em tudo"): a window's body wears the Specialization tab's dark art (spec-background), as the
-- RocketLab's tabs. Over a template's panel stone (ButtonFrameTemplate's or DefaultPanelTemplate's `Bg`, tiled): a
-- texture of its own at the stone's place, and the stone hidden -- one texture tiled and then given an atlas shows the
-- whole atlas file (RocketLab, 13/10). `stone`: the template's stone to cover (its `Bg`, said by the caller: a frame
-- without one answers nil in the game and a function in the harness); none (a panel on TooltipBorderBackdropTemplate,
-- the game's tooltip border with an empty centre): the art 3 points in from the frame's edges, inside the border.
function ns.DarkBody(frame, alpha, stone)
    local art = frame.__dark
    if not art then
        art = frame:CreateTexture(nil, "BACKGROUND", nil, -6)
        art:SetAtlas("spec-background")
        if stone then
            art:SetAllPoints(stone)
            stone:Hide()
        else
            art:SetPoint("TOPLEFT", 3, -3)
            art:SetPoint("BOTTOMRIGHT", -3, 3)
        end
        frame.__dark = art
    end
    art:SetAlpha(alpha or 1)
    art:Show()
    return art
end
