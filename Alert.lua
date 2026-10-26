-- RocketSwap | Alert.lua
-- Three warnings, and all three work WITHOUT the player making a set:
--
--   1. The wrong gear for the content -- PvE in an arena, PvP in a dungeon.
--   2. On the ready check, a summary of what you are using, for the group to check before pulling.
--   3. On the PvP queue's invite, the same summary -- and there it is worth more: inside the match the
--      addon restriction closes the swap from start to end, so the invite is the last window.
--
-- ⛑ WARNING 3 IS PvP ONLY, AND THE LABEL HAS TO SAY SO (22/09). It hangs on
-- `UPDATE_BATTLEFIELD_STATUS` and reads `GetBattlefieldStatus`, which cover **battleground and
-- arena, and nothing else**. The PvE queue is a whole other system (`LFG_PROPOSAL_SHOW` /
-- `GetLFGProposal`) and does not go through here.
--
-- The user asked exactly that reading "Resumo quando a fila chamar": *"é para PvP certo?
-- ou vai funcionar para outros localizadores também?"*. A label that raises that question already
-- failed -- that is why all of them now say **PvP queue**.
--
-- And the lopsidedness is no oversight: in a dungeon you CAN still switch after entering, so the
-- invite is not the last window as it is in an arena. Extending it to PvE is possible; it is just worth less.
--
-- THIS FILE'S FAILURE MODE IS NOT A LUA ERROR -- it is the user turning it off because he got fed up.
-- The acceptance criterion is: whoever did everything right for two weeks saw the addon zero times.
-- Hence the four gates before any pixel:
--
--   a) CAN IT BE FIXED? In combat, or with the restriction already on, the warning stays quiet. A
--      warning about what can no longer be fixed is pure noise.
--   b) IS THE READING RELIABLE? If every slot read came out wrong, it is the detection that failed,
--      not the player who got sixteen pieces wrong (see `Gear.LooksReliable`).
--   c) DID I ALREADY WARN ABOUT IT? Same situation, same kind: quiet.
--   d) DID THE USER SAY TO KEEP QUIET? A kept silence, per slot and per situation.
--
-- `ADDON_RESTRICTION_STATE_CHANGED` is the last call: Blizzard's documentation says it fires
-- **before** the restriction turns on. And `IsAddOnRestrictionActive` "will always return false
-- during dispatch" of that event -- so we read the payload's `state`, never the function.
local ADDON, ns = ...
local L = ns.L

local Alert = {}
ns.Alert = Alert

local frame, ui
local lastKey            -- the last situation warned about, so it does not repeat

--------------------------------------------------------------------------------
-- Contexto
--------------------------------------------------------------------------------
--- Where are we? "pvp", "pve" or nil (open world: the addon has no opinion).
function Alert.Context()
    local inInstance, instanceType = IsInInstance()
    if inInstance then
        if instanceType == "arena" or instanceType == "pvp" then return "pvp" end
        if instanceType == "party" or instanceType == "raid" then return "pve" end
        return nil
    end

    -- PvP QUEUE: any of them counts, the wait included.
    --
    -- ⚑ BEFORE, ONLY `"confirm"` AND `"active"` COUNTED, and `"confirm"` **is not the wait** -- it is the
    -- queue's call, the invite with a countdown to accept. (An encounter-alerts addon proves it: it only creates the
    -- "time left to accept a queue" bar when the status becomes `"confirm"`, measuring it with
    -- `GetBattlefieldPortExpiration`.) So, at the literal moment of the user's request -- *"quando
    -- dou fila em BG, arena"* -- the context was `nil` and the warning died before reading a piece.
    --
    -- The list is now of what does NOT count, on purpose: the literal name of the waiting status
    -- could not be proven from disk, and a positive test would depend on getting that name right.
    -- The negative one does not.
    if GetMaxBattlefieldID and GetBattlefieldStatus then
        for i = 1, (GetMaxBattlefieldID() or 0) do
            local status = GetBattlefieldStatus(i)
            if status ~= nil and status ~= "none" and status ~= "error" then
                return "pvp"
            end
        end
    end

    -- WAR MODE: the user's request -- *"inclusive quando seto para pvp, habilitando o war mode
    -- on, sem avisos"*.
    --
    -- The open world was left out on purpose ("the addon has no opinion"), and War Mode was not
    -- checked anywhere. But with it on the player is open to PvP, and that is what
    -- he meant by "seto para pvp".
    --
    -- It returns a context of ITS OWN, and not `"pvp"`, because the situation is different: with War Mode
    -- on most of the time is PvE (quests, world quests). Treating it as an arena would make the warning
    -- shout "PvE gear in a PvP match" at whoever is farming -- and the same text for two different
    -- situations is what turns a warning into noise.
    if C_PvP and C_PvP.IsWarModeDesired then
        local ok, ligado = pcall(C_PvP.IsWarModeDesired)
        if ok and ligado then return "warmode" end
    end

    return nil
end

--- Can it be fixed now?
local function CanFix()
    if InCombatLockdown() then return false end

    if C_RestrictedActions and C_RestrictedActions.GetAddOnRestrictionState and Enum
        and Enum.AddOnRestrictionType and Enum.AddOnRestrictionState then
        for _, kind in ipairs({ Enum.AddOnRestrictionType.PvPMatch,
                               Enum.AddOnRestrictionType.Encounter,
                               Enum.AddOnRestrictionType.ChallengeMode }) do
            local ok, state = pcall(C_RestrictedActions.GetAddOnRestrictionState, kind)
            if ok and state == Enum.AddOnRestrictionState.Active then return false end
        end
    end
    return true
end

--- EVERY GATE OF THE WARNING'S PATH, in one picture.
---
--- ⚑ WHY THIS EXISTS. The user reported, on 08/09/2026: *"o aviso de item pvp para conteudo
--- pve ta funcionando. porem o de pve no pvp, ainda nao vi funcionar, quando dou fila em BG,
--- arena, ele nao avisa nada sobre meus itens"* -- and then *"inclusive quando seto para pvp,
--- habilitando o war mode on, sem avisos"*.
---
--- The path to the warning has SIX doors, and each one closes silently:
---
---  1. `warnPvE`/`warnPvP` off           -- turned off by the player, for THIS context
---  2. `Alert.Context()` returns nil    -- the addon has no opinion here
---  3. `CanFix()` returns false         -- combat, or an addon restriction on
---  4. `Gear.PatternReady()` false      -- the detection does not work in this language
---  5. `#wrong == 0`                    -- there is nothing to warn about
---  6. `Gear.LooksReliable()` false     -- all wrong = a suspicious reading
---
--- None of them writes anything anywhere. With six silent doors, guessing which one closed costs
--- a trip to the game per guess; this picture costs one.
---
--- @return table state
function Alert.Diagnose()
    local contexto = Alert.Context()
    local inInstance, instanceType = IsInInstance()

    local filas = {}
    if GetMaxBattlefieldID then
        for i = 1, (GetMaxBattlefieldID() or 0) do
            local status, mapa = GetBattlefieldStatus(i)
            if status and status ~= "none" then
                filas[#filas + 1] = { id = i, status = status, mapa = mapa }
            end
        end
    end

    -- WAR MODE. The addon checks this nowhere today -- and that is exactly why the
    -- diagnosis does: for the picture to show what the addon is ignoring.
    local guerra
    if C_PvP and C_PvP.IsWarModeDesired then
        local ok, ativo = pcall(C_PvP.IsWarModeDesired)
        if ok then guerra = ativo end
    end

    local restricoes = {}
    if C_RestrictedActions and C_RestrictedActions.GetAddOnRestrictionState and Enum
        and Enum.AddOnRestrictionType and Enum.AddOnRestrictionState then
        for nome, kind in pairs({ PvPMatch = Enum.AddOnRestrictionType.PvPMatch,
                                  Encounter = Enum.AddOnRestrictionType.Encounter,
                                  ChallengeMode = Enum.AddOnRestrictionType.ChallengeMode }) do
            local ok, state = pcall(C_RestrictedActions.GetAddOnRestrictionState, kind)
            restricoes[nome] = ok and (state == Enum.AddOnRestrictionState.Active) or false
        end
    end

    -- BOTH DIRECTIONS, always. Asking only the current context's hides the case where the
    -- context is what is wrong -- which is exactly one of the suspects.
    local erradoPvP, lidoPvP, vestido = ns.Gear.Wrong(true, ns.db and ns.db.mutedSlots)
    local erradoPvE, lidoPvE = ns.Gear.Wrong(false, ns.db and ns.db.mutedSlots)

    return {
        contexto = contexto,
        instancia = inInstance and instanceType or nil,
        filas = filas,
        warMode = guerra,
        emCombate = InCombatLockdown() and true or false,
        restricoes = restricoes,
        podeConsertar = CanFix(),
        avisoPvE = not (ns.db and ns.db.warnPvE == false),
        avisoPvP = not (ns.db and ns.db.warnPvP == false),
        -- THE SEVENTH DOOR, and it is new: with War Mode on the warning only comes out if the player
        -- ticked the option. Without this line the picture would say "all set to warn" and the warning would
        -- not come out -- the kind of silence this diagnosis exists to avoid.
        avisoModoGuerra = ns.db and ns.db.warnWarMode == true or false,
        deteccaoViva = ns.Gear.PatternReady(),
        vestido = vestido,
        comoPvP = { errado = #erradoPvP, lido = lidoPvP,
            confiavel = ns.Gear.LooksReliable(erradoPvP, lidoPvP) },
        comoPvE = { errado = #erradoPvE, lido = lidoPvE,
            confiavel = ns.Gear.LooksReliable(erradoPvE, lidoPvE) },
    }
end

--------------------------------------------------------------------------------
-- A janela do aviso
--------------------------------------------------------------------------------
local function Build()
    if ui then return ui end

    ui = CreateFrame("Frame", ADDON .. "Alert", UIParent, "ButtonFrameTemplate")
    ui:SetSize(360, 190)
    ui:SetPoint("TOP", UIParent, "TOP", 0, -180)
    ui:SetFrameStrata("DIALOG")
    ui:SetMovable(true)
    ui:EnableMouse(true)
    ui:RegisterForDrag("LeftButton")
    ui:SetScript("OnDragStart", ui.StartMoving)
    ui:SetScript("OnDragStop", ui.StopMovingOrSizing)
    ui:Hide()

    if ui.SetTitle then ui:SetTitle(ns.NAME) end
    if ui.SetPortraitToAsset then ui:SetPortraitToAsset(ns.LOGO) end
    if ui.Inset then ui.Inset:Hide() end
    ns.DarkBody(ui, 1, ui.Bg)                       -- (25/10) the dark body, as every Rocket window (Core.lua)

    ui.headline = ui:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    ui.headline:SetPoint("TOPLEFT", 60, -30)
    ui.headline:SetPoint("RIGHT", -14, 0)
    ui.headline:SetJustifyH("LEFT")
    ui.headline:SetTextColor(1, 0.82, 0)

    ui.body = ui:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ui.body:SetPoint("TOPLEFT", 14, -64)
    ui.body:SetPoint("RIGHT", -14, 0)
    ui.body:SetJustifyH("LEFT")
    ui.body:SetSpacing(3)

    ui.fix = CreateFrame("Button", nil, ui, "UIPanelButtonTemplate")
    ui.fix:SetSize(150, 22)
    ui.fix:SetPoint("BOTTOMLEFT", 14, 8)

    ui.mute = CreateFrame("Button", nil, ui, "UIPanelButtonTemplate")
    ui.mute:SetSize(150, 22)
    ui.mute:SetPoint("BOTTOMRIGHT", -14, 8)
    ui.mute:SetText(L["Don't warn here"])
    ui.mute:SetScript("OnClick", function()
        if lastKey then
            ns.db.muted = ns.db.muted or {}
            ns.db.muted[lastKey] = true
        end
        ui:Hide()
    end)

    tinsert(UISpecialFrames, ui:GetName())
    return ui
end

--- Is the warning on screen? And what is it saying?
---
--- ⚑ THEY EXIST BECAUSE THE TEST BEFORE TESTED NOTHING. It asserted
--- `ns.Alert.__shown ~= true` -- and `__shown` was never written in `Alert`, only in the
--- simulator's frames. The comparison was `nil ~= true`, always true: the check passed with the warning
--- showing or not. A test that cannot fail is a comment with a test's syntax.
function Alert.__Shown()
    return ui ~= nil and ui:IsShown() and true or false
end

---O botao de consertar esta oferecido? E o que separa "o addon avisou" de "o addon avisou E
---consegue resolver" -- as duas coisas deixaram de andar juntas.
function Alert.__FixShown()
    return ui ~= nil and ui.fix ~= nil and ui.fix:IsShown() and true or false
end

function Alert.__Headline()
    return ui and ui.headline and ui.headline:GetText() or nil
end

function Alert.Hide()
    if ui then ui:Hide() end
end

--------------------------------------------------------------------------------
-- Aviso de equipamento errado
--------------------------------------------------------------------------------
--- A set that fits the context, if the player made one. It is what turns
--- the warning from "you got it wrong" into "shall I fix it?". Without sets, the warning only points.
--- Does this context ask for PvP gear?
---
--- There are THREE contexts now ("pvp", "warmode", "pve") and two of them ask for PvP. Asking
--- `context == "pvp"` in each place would quietly leave War Mode on the PvE side -- the
--- opposite of what it means.
local function WantsPvP(context)
    return context == "pvp" or context == "warmode"
end

local function PresetFor(context)
    for _, preset in ipairs(ns.db.presets or {}) do
        if preset.gear then
            local wrong, read = ns.Gear.Wrong(WantsPvP(context))
            -- A set fits if, applied, it would solve it: we use its very name as a
            -- clue when simulating is not possible (it is not -- the set's pieces are not
            -- worn). A name is a heuristic, which is why it is only a button suggestion, never an
            -- automatic action.
            local name = (preset.name or ""):lower()
            local looksPvP = name:find("pvp") or name:find("arena") or name:find("bg")
                or name:find("campo")
            if WantsPvP(context) == (looksPvP ~= nil) then
                return preset, wrong, read
            end
        end
    end
    return nil
end

--- Is the equipment warning on FOR THIS context?
---
--- (!) One key per context since 0.35.0. Whoever does mythic+ every night and PvP now and then
--- wants the warning on in one and quiet in the other; with a single `warn` he had to pick both together.
--- War Mode is the open world with PvP on, so it follows the PvP key -- plus its own
--- gate (`warnWarMode`), which is opt-in by the request of 12/09.
local function WarnEnabled(context)
    if context == "pve" then return ns.db.warnPvE ~= false end
    if context == "pvp" or context == "warmode" then return ns.db.warnPvP ~= false end
    return false
end

function Alert.Check(reason)
    if not ns.db then return end

    local context = Alert.Context()
    if not context then return end
    if not WarnEnabled(context) then return end

    -- ⚑ THE WAR MODE WARNING IS OPT-IN (`warnWarMode`, off by default). The request of 12/09:
    -- *"tira o alerta dos itens de pvp em mundo aberto no war mode, ou transforma em opção por
    -- padrão desmarcada"*.
    --
    -- THE GATE STAYS HERE, AND NOT IN `Alert.Context()`, on purpose: the context is still
    -- "warmode" for `/rs gear` (the diagnosis has to say where the player is) and for the ready check's
    -- summary. What goes quiet is the warning, which is what bothered him. Touching the context would
    -- also erase the two things nobody asked to erase.
    if context == "warmode" and ns.db.warnWarMode ~= true then return end

    -- ⚑ IN COMBAT THE WARNING STAYS QUIET, and only in combat. The gate used to be `CanFix()`, which also
    -- closes when the **addon restriction** is on -- and this client's API documentation
    -- (12.1.0.69587) defines `Enum.AddOnRestrictionType.PvPMatch` as *"the player is in an
    -- active and incomplete PvP match"*: a window closed from the start to the end of the match.
    --
    -- That turned the warning off during EVERY arena and EVERY battleground, and it is part of the
    -- lopsidedness the user reported: in PvE the matching restrictions (`Encounter`, `ChallengeMode`)
    -- leave free windows -- a dungeon outside an encounter, a raid between bosses -- while a
    -- PvP match leaves none.
    --
    -- And the dependency was wrong from the start: **knowing does not depend on being able to fix**. Whoever
    -- finds out mid-match that he is in PvE gear at least leaves and comes back right. What depends on
    -- being able to fix is the BUTTON, and it already knows how to hide.
    if InCombatLockdown() then return end

    local wrong, read = ns.Gear.Wrong(WantsPvP(context), ns.db.mutedSlots)
    if #wrong == 0 then
        Alert.Hide()
        return
    end
    if not ns.Gear.LooksReliable(wrong, read) then return end

    local key = context .. ":" .. (#wrong > 0 and "gear" or "")
    if ns.db.muted and ns.db.muted[key] then return end
    if key == lastKey and ui and ui:IsShown() then return end
    lastKey = key

    -- The game's text, in the game's place: a yellow warning below the centre. It is where Blizzard
    -- puts a message of this kind, and the helper already handles colour and repetition.
    -- THE WORDING IS THE CONTEXT'S, and War Mode has its own.
    --
    -- With War Mode on most of the time is PvE -- quests, world quests, farming. Saying
    -- "PvE gear in a PvP match" there would be false (there is no match) and would become noise
    -- for whoever only wants the experience bonus. The text warns that he is EXPOSED, which is the fact.
    local titulo = L["PvP gear in PvE content."]
    if context == "pvp" then
        titulo = L["PvE gear in a PvP match."]
    elseif context == "warmode" then
        titulo = L["PvE gear with War Mode on."]
    end

    if UIErrorsFrame and UIErrorsFrame.AddExternalWarningMessage then
        pcall(UIErrorsFrame.AddExternalWarningMessage, UIErrorsFrame, titulo)
    end

    Build()

    ui.headline:SetText(titulo)

    local lines = {}
    for i = 1, math.min(#wrong, 6) do
        lines[#lines + 1] = "• " .. ns.Gear.SlotName(wrong[i].slot) .. "   " .. wrong[i].link
    end
    if #wrong > 6 then
        lines[#lines + 1] = format(L["...and %d more."], #wrong - 6)
    end
    ui.body:SetText(table.concat(lines, "\n"))

    -- The BUTTON, yes, depends on being able to fix: offering "Load <set>" in the middle of a
    -- match, where the swap is refused, would be a button that does nothing.
    local preset = CanFix() and PresetFor(context) or nil
    if preset then
        ui.fix:SetText(format(L["Load %s"], preset.name))
        ui.fix:SetScript("OnClick", function()
            ns.Data.Apply(preset, function(text) ns.Print(text) end)
            ui:Hide()
        end)
        ui.fix:Show()
    else
        ui.fix:Hide()
    end

    ui:SetHeight(120 + math.min(#wrong, 7) * 14)
    ui:Show()
end

--------------------------------------------------------------------------------
-- Ready check: o resumo antes de puxar
--------------------------------------------------------------------------------
--- What you are using now: the three fields, each with its LABEL.
---
--- It is not a warning and judges nothing: it is the check the leader asks for with the ready check.
---
--- THE LABELS ARE THE ADDON'S OWN WINDOW'S -- `Especialização`, `Talentos`, `Itens` -- and that is the
--- reason they are these and no others. The player who opens `/rs` reads exactly these three
--- words next to the three combos; a summary using others would make him learn two
--- vocabularies for the same thing. No new key: `L["Specialization"]`, `L["Talents"]` and
--- `L["Gear"]` already exist and are already what the editor shows.
---
--- And that is why the third does NOT come from the game. The first two do (`SPECIALIZATION` and
--- `TALENTS`, through `FROM_GAME`), but for items there is no clean global and there is a trap recorded
--- in `Locales/enUS.lua`: in pt-BR the game calls a **talent loadout** "equipamento" and an
--- **equipment set** "conjunto". This addon avoids both on purpose, because it exists
--- precisely for whoever already mixes the two things up -- and the request that brought these labels
--- ("não sei o que é o que") is that confusion in person.
---
--- @param separator string|nil `nil` = one line (chat); `"\n"` = one per line (box)
function Alert.Summary(separator)
    local parts = {}

    --- One field of the summary. `label: value`, and the label is the editor's.
    ---
    --- EMPTY IS `(nenhum)`, and no longer "(sem conjunto de itens)". The long phrases existed because
    --- **they were the only context** -- with no label, "(sem conjunto de itens)" was the only way to
    --- know which field it was. With the label in front they started to repeat their own
    --- tag ("Itens: (sem conjunto de itens)") and still dragged two words this addon
    --- avoids: **"loadout"**, which the client translates as "equipamento" in pt-BR, and **"conjunto"**,
    --- which here is the name of the PRESETS (`L["Presets"] = "Conjuntos"`) -- the field and the container
    --- came to share the name.
    ---
    --- `L["(none)"]` already exists and is already what the editor's combos show in the same case. Same
    --- vocabulary, again.
    local function Add(label, value)
        parts[#parts + 1] = label .. ": " .. value
    end

    local specIndex = ns.Data.GetCurrentSpecIndex()
    local spec = ns.Data.GetSpecByIndex(specIndex)
    if spec then Add(L["Specialization"], spec.name) end

    if spec then
        local configID = ns.Data.GetActiveLoadoutID(spec.id)
        local name = configID and ns.Data.LoadoutName(spec.id, configID)
        Add(L["Talents"], name or L["(none)"])
    end

    -- ⚑ `(nenhum)` ONLY WHEN THERE IS NOTHING. `isEquipped` is all-or-nothing: swapping ONE piece of a
    -- 14-piece set clears the flag, and the summary said "Itens: (nenhum)" to whoever had the
    -- set almost whole on. The user's report: *"fica com a mensagem de (nenhum), uma
    -- mensagem errada, porque ele tá com os itens só que um ou mais não estão salvos"*.
    --
    -- Saying the name with the count is what tells apart the two cases the old phrase merged: whoever
    -- forgot to load any set and whoever swapped a piece and did not save. The first has to
    -- load; the second has to SAVE -- and it is the second that shows on the ready check.
    local setID = ns.Data.GetEquippedSetID()
    if setID then
        Add(L["Gear"], ns.Data.GearSetName(setID))
    else
        local _, vestidas, itens, nome = ns.Data.PartialGearSet()
        if nome then
            Add(L["Gear"], format(L["%s (%d of %d pieces)"], nome, vestidas, itens))
        else
            Add(L["Gear"], L["(none)"])
        end
    end

    -- ONE FUNCTION ONLY, with a separator, and not two functions. The rule comes from our own stumble in
    -- this project: two sources of truth for the same information drift apart at the first change --
    -- that is how the configurator's list of outlines lost the "medium".
    return table.concat(parts, separator or "  ·  ")
end

--------------------------------------------------------------------------------
-- A fila chamou: o resumo antes de aceitar
--------------------------------------------------------------------------------
--- The PvP queue's invite -- the moment when it can be fixed, and the last one.
---
--- The user's request (18/09/2026): *"quando chama para entrar na arena após ter esperado na fila,
--- tem como dar o aviso de qual build tá setado?"*.
---
--- It is the ready check's same question, at a moment when it is worth more: inside the arena the
--- talent swap is refused by the addon restriction, and the whole match is a closed window (see
--- the comment of `Alert.Check`). Whoever finds out after accepting finds out late.
---
--- `GetBattlefieldStatus(i)` returns `"confirm"` exactly while the invite is on screen
--- (documented in client 12.1.5). The 2nd return is the map's name and the 3rd, the arena team's
--- size -- 0 in a battleground.
---
--- ONCE PER INVITE. `UPDATE_BATTLEFIELD_STATUS` fires several times with the same `"confirm"`
--- (the invite's clock moves), and the box waits for OK: without a lock, each firing would stack the
--- same box over the one before.
local queueShown = false

function Alert.OnQueuePop()
    if not GetBattlefieldStatus then return end

    -- `GetMaxBattlefieldID` says how many queues exist. Without it, two -- the historical
    -- ceiling.
    local quantas = (GetMaxBattlefieldID and GetMaxBattlefieldID()) or 2

    local mapa, teamSize
    for i = 1, quantas do
        local ok, status, m, t = pcall(GetBattlefieldStatus, i)
        if ok and status == "confirm" then
            mapa, teamSize = m, t
            break
        end
    end

    -- ⚑ ONE WARNING WHILE THERE IS AN INVITE, and not one per queue. The summary is about YOUR build, which is
    -- the same for both queues -- with a lock per index, two queues calling together opened the
    -- same box twice, and the second only replaced the first (the dialog's key is one only).
    --
    -- And once per invite, not per firing: `UPDATE_BATTLEFIELD_STATUS` fires several times
    -- with the same invite on screen, because its clock moves.
    if mapa ~= nil or teamSize ~= nil then
        if not queueShown and ns.db and ns.db.queuePop ~= false then
            queueShown = true
            Alert.ShowQueueSummary(mapa, teamSize)
        end
    elseif queueShown then
        -- Left the invite (accepted, declined or expired): the box loses its subject and goes away, and the
        -- lock frees the next invite. Without this, the box would hang inside the match,
        -- where it is no use any more.
        queueShown = false
        if ns.Dialog then ns.Dialog.Hide("summary") end
        ns.Log.Add("popup", { which = "queue", action = "hide" })
    end
end

--- The invite's box. The same shape as the ready check's -- one label per line, waiting for OK.
---
--- THE TITLE SAYS THE MAP when the game tells it: "Nagrand Arena" answers *why did this show up* without
--- spending a phrase explaining. Without the name, the generic phrase.
function Alert.ShowQueueSummary(mapa, teamSize)
    local resumo = Alert.Summary()
    local titulo = L["PvP queue is up — check before you enter"]
    if type(mapa) == "string" and mapa ~= "" then
        if type(teamSize) == "number" and teamSize > 0 then
            titulo = format("%s (%dv%d)", mapa, teamSize, teamSize)
        else
            titulo = mapa
        end
    end

    ns.Print(L["PvP queue is up:"] .. " " .. resumo)

    -- The box is OURS, not the game's `StaticPopup` (05/10: a box of the game opened by an addon
    -- marks the game's own dialog code, and the game then refuses a protected call of its own
    -- and blames the addon -- `Dialog.lua` has the whole story).
    local ok, shown = pcall(ns.Dialog.Show, "summary", titulo .. "\n\n" .. Alert.Summary("\n"))
    ok = ok and shown == true
    ns.Log.Add("popup", { which = "queue", action = "show", ok = ok })
    if not ok and RaidWarningUtil and RaidWarningUtil.AddMessage then
        pcall(RaidWarningUtil.AddMessage, resumo, NORMAL_FONT_COLOR, 5)
    end
end

-- THE SUMMARY'S CONFIRMATION BOX.
--
-- The summary was chat + a raid warning, and both GO AWAY by themselves. The user's request: *"como mostra
-- o aviso e some, o usuário pode nem ver"*. He is right, and the ready check is exactly the moment
-- when the person is looking at something else -- at the "Ready" button.
--
-- It waits for an OK, and that is the point: the box stays until someone closes it, so the summary does
-- not depend on the player looking at the right time.
--
-- `timeout = 0` -- it does not close by itself, for the same reason it exists.
-- `whileDead = 1` -- dead mid-attempt is exactly when a ready check is asked for.
-- `hideOnEscape = 1` -- Esc closes, as in every box of the game; forcing the click would be spite.
--
-- The name has the addon's prefix because `StaticPopupDialogs` is a GLOBAL table, shared with
-- the game and every addon: a generic key would overwrite another's.
-- Inside the `if`: `StaticPopupDialogs` is a game global and always exists, but indexing a nil global
-- at FILE scope brings the whole addon down at load -- and losing the addon over
-- a warning box is a bad trade.
-- (05/10) The definition of a game dialog that was here is gone: the box is the addon's own
-- (`Dialog.lua`), with the same behaviour -- it waits for the OK, shows while dead, Esc closes.

function Alert.OnReadyCheck()
    if not ns.db or ns.db.readyCheck == false then return end

    local resumo = Alert.Summary()
    ns.Print(L["ready check:"] .. " " .. resumo)

    -- THE BOX IS THE MAIN ONE, and the chat becomes the record. The raid warning went: it also goes away, and
    -- added to the box it would be the same information in two places, one of them useless.
    --
    -- `pcall` because `StaticPopup_Show` **raises an error** when the dialog does not exist
    -- (`StaticPopup.lua:302-304`, `error("Dialog "..which.." does not exist.")`) -- and not existing is
    -- possible if another addon clears the global table.
    -- (05/10) The box is now the addon's own (`Dialog.lua`); the net below stays.
    do
        -- ONE LINE PER FIELD in the box, and all in one in the chat. The box has free height and the
        -- chat does not; and the box is where the player stops to read.
        -- A TITLE WITHOUT A COLON. `L["ready check:"]` is a chat line's PREFIX, and there the
        -- colon is right; as a box's title, followed by a blank line, it hangs
        -- loose. The chat line got to have three: "RocketSwap: conferência: Especialização:
        -- Gelido".
        --
        -- AND THE TITLE NAMES THE CONTENT, not the ritual. The chat's prefix still says
        -- "conferência" on purpose: there it answers *why the addon spoke by itself* -- someone
        -- called the ready check -- and that is the doubt of whoever reads a line that showed up in the middle of the
        -- conversation. In the box, the player already knows why it opened; what he needs in half
        -- a second is to know **what he is looking at**.
        local ok, shown = pcall(ns.Dialog.Show, "summary",
            L["What you are using"] .. "\n\n" .. Alert.Summary("\n"))
        ok = ok and shown == true
        ns.Log.Add("popup", { which = "readycheck", action = "show", ok = ok })
        if not ok and RaidWarningUtil and RaidWarningUtil.AddMessage then
            -- Only then the warning in the middle of the screen, as a net: a warning that goes away beats nothing.
            pcall(RaidWarningUtil.AddMessage, resumo, NORMAL_FONT_COLOR, 5)
        end
    end

    -- And on top: if the gear is wrong for the content, this is the time to know.
    Alert.Check("readycheck")
end

--------------------------------------------------------------------------------
-- Gatilhos
--------------------------------------------------------------------------------
function Alert.Create()
    if frame then return frame end

    -- ⚑ WHEN THE ITEM'S DATA ARRIVES, THE SUM IS REDONE. `Gear` asks for the load of what it read as
    -- "I do not know" and tells us here; without this subscription the request would be for nothing -- the warning
    -- would stay with the incomplete reading until the next trigger, which may never come.
    --
    -- `lastKey = nil` because the warning refuses to repeat the same key while on screen: without
    -- clearing it, the new evaluation would be thrown away exactly when it has something new to say.
    ns.Gear.onItemLoaded = function()
        lastKey = nil
        Alert.Check("item carregado")
    end

    frame = CreateFrame("Frame", ADDON .. "AlertEvents")

    -- Entering an instance: `PLAYER_ENTERING_WORLD` alone is too early -- the gear
    -- is not loaded yet. Two seconds give that margin.
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    frame:RegisterEvent("UPDATE_BATTLEFIELD_STATUS")
    frame:RegisterEvent("READY_CHECK")
    -- These only CANCEL: they can hide a warning, never create one.
    frame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    frame:RegisterEvent("EQUIPMENT_SWAP_FINISHED")
    if C_EventUtils and C_EventUtils.IsEventValid
        and C_EventUtils.IsEventValid("ADDON_RESTRICTION_STATE_CHANGED") then
        frame:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED")
    end

    frame:SetScript("OnEvent", function(_, event, a, b)
        if event == "READY_CHECK" then
            Alert.OnReadyCheck()

        elseif event == "UPDATE_BATTLEFIELD_STATUS" then
            -- TWO THINGS ON THE SAME EVENT, and in the right order: first the invite's summary, which is
            -- immediate and has a deadline (the invite expires), and only then the gear check, which
            -- waits the usual 2 seconds because it depends on the tooltip having loaded.
            Alert.OnQueuePop()
            C_Timer.After(2, function() Alert.Check(event) end)

        elseif event == "PLAYER_EQUIPMENT_CHANGED" or event == "EQUIPMENT_SWAP_FINISHED" then
            ns.Gear.ClearCache()
            lastKey = nil
            Alert.Hide()

            -- The gear changed: asks for what is missing. Without this, a freshly equipped piece stays
            -- without data until someone hovers it -- and that is how the warning of 13/09 accused
            -- two PvP pieces of being PvE.
            for _, slot in ipairs(ns.Gear.SLOTS) do
                ns.Gear.RequestLoad(slot)
            end

        elseif event == "ADDON_RESTRICTION_STATE_CHANGED" then
            -- `b` is the state. `Activating` is the last call: it can still be switched.
            if Enum and Enum.AddOnRestrictionState and b == Enum.AddOnRestrictionState.Activating then
                Alert.Check("restriction")
            end

        else
            C_Timer.After(2, function() Alert.Check(event) end)
        end
    end)

    return frame
end
