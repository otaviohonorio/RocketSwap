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

--- Does the preset's name say PvP? A set fits if, applied, it would solve it: we use its very name as a clue when
--- simulating is not possible (it is not -- the set's pieces are not worn). A name is a heuristic, which is why it is
--- only a button suggestion, never an automatic action.
local function LooksPvP(preset)
    local name = (preset.name or ""):lower()
    return (name:find("pvp") or name:find("arena") or name:find("bg") or name:find("campo")) ~= nil
end

local function PresetFor(context)
    for _, preset in ipairs(ns.db.presets or {}) do
        if preset.gear then
            local wrong, read = ns.Gear.Wrong(WantsPvP(context))
            if WantsPvP(context) == LooksPvP(preset) then
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

--- The warning's headline. THE WORDING IS THE CONTEXT'S, and War Mode has its own: with War Mode on most of the time is
--- PvE -- quests, world quests, farming. Saying "PvE gear in a PvP match" there would be false (there is no match) and
--- would become noise for whoever only wants the experience bonus. The text warns that he is EXPOSED, which is the fact.
local function Headline(context)
    if context == "pvp" then return L["PvE gear in a PvP match."] end
    if context == "warmode" then return L["PvE gear with War Mode on."] end
    return L["PvP gear in PvE content."]
end

--- The wrong-content gear with every gate of the warning (on for this context, War Mode opt-in, a reliable reading,
--- not muted): the headline and the pieces, or nil. (26/10) The summary card says it on its gear row, with the same
--- gates -- a card that warned where the warning keeps quiet would undo every "don't warn here".
local function GearIssue(context)
    if not ns.db or not context or not WarnEnabled(context) then return nil end
    if context == "warmode" and ns.db.warnWarMode ~= true then return nil end
    local wrong, read = ns.Gear.Wrong(WantsPvP(context), ns.db.mutedSlots)
    if #wrong == 0 or not ns.Gear.LooksReliable(wrong, read) then return nil end
    if ns.db.muted and ns.db.muted[context .. ":gear"] then return nil end
    return Headline(context), wrong
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

    -- (26/10) THE SUMMARY CARD ON SCREEN SAYS IT, on its gear row: a second box over the first (and the yellow line in
    -- the middle of the screen) would be the same news three times. The card is redrawn with the new reading -- this
    -- runs 2 s after the queue's invite and when an item's data arrives, both later than the card.
    if Alert.CardShown() then
        Alert.RefreshCard()
        return
    end

    -- The game's text, in the game's place: a yellow warning below the centre. It is where Blizzard
    -- puts a message of this kind, and the helper already handles colour and repetition.
    local titulo = Headline(context)

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
-- O cartao do resumo: uma linha por campo
--------------------------------------------------------------------------------
-- (26/10) THE SUMMARY AS A CARD. The user, looking at the text box: *"tem como deixar mais bonito? e mais claro para que
-- o jogador entenda de fato o que tá usando?"*, and on the mockup (`mockup/PREVIA aviso do RocketSwap na conferencia e
-- na fila de PvP`): *"pode fazer, gostei"*. What the text box could not say, the card says:
--   * one row per field: the game's icon (the spec's, the hero tree's, the gear set's own), the label in the secondary
--     grey, the value in white, and a mark at the right -- right, warning, wrong;
--   * the talents carry the HERO TREE (`C_ClassTalents.GetActiveHeroTalentSpec` + `C_Traits.GetSubTreeInfo`, whose
--     `TraitSubTreeInfo` has `name` and `iconElementID`, an atlas -- the 12.1.5 API documentation);
--   * a gear set with a piece swapped says WHICH slot is not the set's, and what to do if it was on purpose;
--   * the fields are compared with the player's preset that matches best (in the PvP queue, the PvP one): a field that
--     differs says what the preset uses, and the button loads it;
--   * the wrong-content gear warning is a note of the gear row, not a second box over the first.
--
-- WHERE (the user's choice, 26/10: "colado embaixo"): right under the game's own box of the moment -- the ready
-- check's, the PvP queue's --, never replacing it. Answering the ready check is `C_PartyInfo.ConfirmReadyCheck`, which
-- the 12.1.5 documentation marks `HasRestrictions` (refused while an addon restriction is on), and hiding a frame of
-- the game is the kind of touch that once got this addon blamed for a protected call (Dialog.lua). The card reads
-- where the game's box is (its edges) and never anchors to it. It closes when the player answers or the check ends.
--
-- THE SHELL is the one of the addon's box (`StaticPopupBaseTemplate`: the game's dialog border, never the game's
-- dialog LIST -- see Dialog.lua), with the dark body of every Rocket window (`ns.DarkBody`, 25/10).

-- The game's measures where it has them: the dialog's 16 above and below and its 22-tall button (Dialog.lua); the
-- Settings panel's 25 to the left of its content is too wide for a card, the game's own dialogs use 20 at the sides
-- (EditModeDialogs.xml:260). The row: a 32 icon (the size of the talent loadout's icon in the game's dropdown), 10 to
-- the text, the mark at 18 (`common-icon-checkmark` is 22, drawn smaller to sit beside a 12 text).
local CARD = { width = 360, side = 20, top = 16, bottom = 16, icon = 32, iconGap = 10, mark = 18, markGap = 6,
               rowGap = 10, button = 22, fixWidth = 150, okWidth = 128, buttonGap = 10, fromScreenTop = 135 }
CARD.text = CARD.width - 2 * CARD.side - CARD.icon - CARD.iconGap - CARD.mark - CARD.markGap
Alert.CARD = CARD

-- The marks: the game's own (checked with tools/ver_atlas.py, 12.1.5): the check of the game's lists, the small
-- warning sign of the Trading Post, the red X of the game's close buttons.
-- (one name per line and the brace at the start: the shape tools/ver_atlas.py --check reads as a table of atlases)
local MARK_ATLAS = {
    ok = "common-icon-checkmark", warn = "perks-warning-small", bad = "common-icon-redx",
}
local WORSE = { ok = 1, warn = 2, bad = 3 }
-- The talents with no hero tree yet (below its level): the talents' micro-menu art, the game's picture of "talents"
local TALENT_ICON_ATLAS = "ui-hud-micromenu-spectalents-up-2x"
-- No gear set: the empty chest slot of the character sheet
local NO_GEAR_TEXTURE = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Chest"
local DIVIDER_ATLAS = "options_horizontaldivider"    -- the Settings panel's divider: white fading at the ends

local card, cardKind, cardInitiatorIsMe, cardRefreshing

-- A colour object of the game, with its method (`ColorMixin:WrapTextInColorCode`); plain text if it is missing.
local function Wrap(colour, text)
    if colour and colour.WrapTextInColorCode then return colour:WrapTextInColorCode(text) end
    return text
end
local function White(text) return Wrap(HIGHLIGHT_FONT_COLOR, text) end

--- The active hero tree: { name, atlas } or nil (below its level, or the API not there).
local function HeroTree()
    if not (C_ClassTalents and C_ClassTalents.GetActiveHeroTalentSpec and C_ClassTalents.GetActiveConfigID
        and C_Traits and C_Traits.GetSubTreeInfo) then return nil end
    local ok, subTreeID = pcall(C_ClassTalents.GetActiveHeroTalentSpec)
    if not ok or type(subTreeID) ~= "number" then return nil end
    local okC, configID = pcall(C_ClassTalents.GetActiveConfigID)
    if not okC or type(configID) ~= "number" then return nil end
    local okI, info = pcall(C_Traits.GetSubTreeInfo, configID, subTreeID)
    if not okI or type(info) ~= "table" or type(info.name) ~= "string" or info.name == "" then return nil end
    return { name = info.name, atlas = info.iconElementID }
end
Alert.HeroTree = HeroTree

--- The slots whose piece is not the set's: what the set saved (`C_EquipmentSet.GetItemIDs`, by slot) against what is
--- worn (`GetInventoryItemID`). A slot the set ignores (`GetIgnoredSlots`, by slot, as PaperDollFrame.lua reads it) or
--- keeps empty does not count. The id is compared, not the copy: two copies of the same item in the bags read as the
--- set's -- then the count says a piece is off and no slot is named, which is the honest answer.
function Alert.OffSetSlots(setID)
    local out = {}
    if not (setID and C_EquipmentSet and C_EquipmentSet.GetItemIDs and GetInventoryItemID) then return out end
    local ok, ids = pcall(C_EquipmentSet.GetItemIDs, setID)
    if not ok or type(ids) ~= "table" then return out end
    local ignored
    if C_EquipmentSet.GetIgnoredSlots then
        local okI, t = pcall(C_EquipmentSet.GetIgnoredSlots, setID)
        if okI and type(t) == "table" then ignored = t end
    end
    for _, slot in ipairs(ns.Gear.SLOTS) do
        local want = ids[slot]
        -- 0, 1 and -1 are the set's marks for an empty, an ignored and a lost slot, not items
        if type(want) == "number" and want > 1 and not (ignored and ignored[slot]) then
            if GetInventoryItemID("player", slot) ~= want then out[#out + 1] = slot end
        end
    end
    return out
end

local function Current()
    local cur = { specIndex = ns.Data.GetCurrentSpecIndex() }
    cur.spec = ns.Data.GetSpecByIndex(cur.specIndex)
    if cur.spec then cur.talent = ns.Data.GetActiveLoadoutID(cur.spec.id) end
    cur.gearSet = ns.Data.GetEquippedSetID()
    if not cur.gearSet then
        cur.partialSet, cur.worn, cur.items = ns.Data.PartialGearSet()
    end
    return cur
end

--- THE PRESET TO COMPARE WITH. In the PvP queue: a PvP one (by its name, as the fix button always did), the one of the
--- current spec first. On the ready check: among the presets of the current spec, the one that matches most of what is
--- on (talents, gear -- a gear set almost on counts); none matching anything, or a tie, and there is no comparison --
--- picking "the first" would be drawing lots for which name the player reads (the rule of `Data.PartialGearSet`).
function Alert.ComparePreset(cur, kind)
    local best, bestScore, tie = nil, 0, false
    for _, preset in ipairs(ns.db and ns.db.presets or {}) do
        if preset.talent or preset.gear then
            local sameSpec = preset.spec == nil or preset.spec == cur.specIndex
            local score = 0
            if sameSpec and preset.talent and preset.talent == cur.talent then score = score + 1 end
            if preset.gear and (preset.gear == cur.gearSet or preset.gear == cur.partialSet) then score = score + 1 end
            if kind == "queue" then
                if LooksPvP(preset) then
                    score = score + (sameSpec and 10 or 5)
                    if score > bestScore then best, bestScore = preset, score end
                end
            elseif sameSpec and score > 0 then
                if score > bestScore then best, bestScore, tie = preset, score, false
                elseif score == bestScore then tie = true end
            end
        end
    end
    if tie then return nil end
    return best
end

local function Uses(preset, value)
    return format(L["The preset %s uses: %s"], White(preset.name or "?"), White(value or L["(none)"]))
end

--- What the card shows, as data (the harness reads it; the drawing only lays it out).
--- @param kind string "readycheck" or "queue"
--- @return table { rows = { {label, value, extra, icon, atlas, state, notes} x3 }, verdict = {state, text}|nil,
---               preset = the compared preset|nil, fix = the preset of the button|nil }
function Alert.CardModel(kind)
    local context = kind == "queue" and "pvp" or Alert.Context()
    local cur = Current()
    local preset = Alert.ComparePreset(cur, kind)
    local differs = false

    -- 1. THE SPECIALIZATION, with the class beside it: "Gélido" is a Mage's and a Death Knight's.
    local spec = cur.spec
    local specRow = { label = L["Specialization"], value = spec and spec.name or L["(none)"], icon = spec and spec.icon,
                      notes = {} }
    if UnitClass then
        local okC, className = pcall(UnitClass, "player")
        if okC and type(className) == "string" then specRow.extra = className end
    end
    if preset and preset.spec then
        if preset.spec == cur.specIndex then
            specRow.state = "ok"
        else
            specRow.state, differs = "bad", true
            local want = ns.Data.GetSpecByIndex(preset.spec)
            specRow.notes[#specRow.notes + 1] = Uses(preset, want and want.name)
        end
    end

    -- 2. THE TALENTS: the loadout's name and the hero tree, with the hero tree's own art.
    local hero = HeroTree()
    local talentRow = { label = L["Talents"], notes = {},
                        value = spec and ns.Data.LoadoutName(spec.id, cur.talent) or L["(none)"],
                        extra = hero and hero.name, atlas = hero and hero.atlas or TALENT_ICON_ATLAS }
    if preset and preset.talent then
        if preset.talent == cur.talent and (preset.spec == nil or preset.spec == cur.specIndex) then
            talentRow.state = "ok"
        else
            talentRow.state, differs = "bad", true
            local wantSpec = ns.Data.GetSpecByIndex(preset.spec or cur.specIndex)
            talentRow.notes[#talentRow.notes + 1] = Uses(preset, wantSpec and ns.Data.LoadoutName(wantSpec.id, preset.talent))
        end
    end

    -- 3. THE GEAR: the set, its count, the piece that is off -- and the wrong-content warning.
    local gearRow = { label = L["Gear"], notes = {} }
    if cur.gearSet then
        local name, icon = ns.Data.GearSetName(cur.gearSet)
        gearRow.value, gearRow.icon, gearRow.state = name or "?", icon, "ok"
        local c = ns.Data.GearSetCounts(cur.gearSet)
        if c and type(c.vestidas) == "number" and type(c.itens) == "number" and c.itens > 0 then
            gearRow.extra = format(L["%d of %d pieces"], c.vestidas, c.itens)
        end
    elseif cur.partialSet then
        local name, icon = ns.Data.GearSetName(cur.partialSet)
        gearRow.value, gearRow.icon, gearRow.state = name or "?", icon, "warn"
        gearRow.extra = format(L["%d of %d pieces"], cur.worn, cur.items)
        local names = {}
        for _, slot in ipairs(Alert.OffSetSlots(cur.partialSet)) do names[#names + 1] = White(ns.Gear.SlotName(slot)) end
        if #names > 0 then gearRow.notes[#gearRow.notes + 1] = format(L["Not the set's: %s"], table.concat(names, ", ")) end
        -- the game's own name for the window where a set is saved
        local manager = type(EQUIPMENT_MANAGER) == "string" and EQUIPMENT_MANAGER or L["Equipment Manager"]
        gearRow.notes[#gearRow.notes + 1] = format(L["Swapped on purpose? Save the gear set in the %s."], manager)
    else
        gearRow.value, gearRow.texture = L["(none)"], NO_GEAR_TEXTURE
    end
    if preset and preset.gear and preset.gear ~= cur.gearSet and preset.gear ~= cur.partialSet then
        gearRow.state, differs = "bad", true
        gearRow.notes[#gearRow.notes + 1] = Uses(preset, ns.Data.GearSetName(preset.gear))
    end
    local issue = GearIssue(context)
    if issue then
        gearRow.state = "bad"
        table.insert(gearRow.notes, 1, Wrap(RED_FONT_COLOR, issue))
    end

    local rows = { specRow, talentRow, gearRow }
    local worst
    for _, r in ipairs(rows) do
        if r.state and (not worst or WORSE[r.state] > WORSE[worst]) then worst = r.state end
    end

    -- THE VERDICT, one line: against the preset when there is one; and in the queue, that the match closes the swap.
    local verdict
    local presetName = preset and White(preset.name or "?")
    if kind == "queue" and worst == "bad" then
        verdict = { state = "bad", text = L["Inside the match you can't switch."] }
    elseif preset and differs then
        verdict = { state = "bad", text = format(L["Does not match the preset %s."], presetName) }
    elseif preset and worst == "warn" then
        verdict = { state = "warn", text = format(L["The preset %s: the gear is not complete."], presetName) }
    elseif preset and worst ~= "bad" then
        verdict = { state = "ok", text = format(L["Matches the preset %s."], presetName) }
    end

    -- THE BUTTON: the compared preset when it is not all on; with none, the one that fixes the wrong-content gear (the
    -- warning's own button). Only when it can be done now -- a button that does nothing is worse than none.
    local fix
    if preset and not ns.Data.IsLoaded(preset) then
        fix = preset
    elseif issue and not preset then
        fix = PresetFor(context)
    end
    if fix and not CanFix() then fix = nil end

    return { rows = rows, verdict = verdict, preset = preset, fix = fix, context = context }
end

local function NewRow(f)
    local r = {}
    r.icon = f:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(CARD.icon, CARD.icon)
    r.label = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    r.label:SetTextColor(LIGHTGRAY_FONT_COLOR:GetRGB())
    r.label:SetJustifyH("LEFT")
    r.label:SetWidth(CARD.text)
    r.value = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    r.value:SetJustifyH("LEFT")
    r.value:SetWidth(CARD.text)
    r.notes = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    r.notes:SetTextColor(LIGHTGRAY_FONT_COLOR:GetRGB())
    r.notes:SetJustifyH("LEFT")
    r.notes:SetWidth(CARD.text)
    r.notes:SetSpacing(2)
    r.mark = f:CreateTexture(nil, "ARTWORK")
    return r
end

local function BuildCard()
    if card then return card end
    local ok, f = pcall(CreateFrame, "Frame", ADDON .. "SummaryCard", UIParent, "StaticPopupBaseTemplate")
    if not ok or not f then return nil end
    f:EnableKeyboard(false)            -- the shell is born taking the keyboard (Dialog.lua)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetWidth(CARD.width)
    f:Hide()
    ns.DarkBody(f, 1, f.BG and f.BG.Bottom)

    f.brand = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    f.brand:SetJustifyH("LEFT")
    f.brand:SetWidth(CARD.width - 2 * CARD.side)
    f.title = f:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    f.title:SetJustifyH("LEFT")
    f.title:SetWidth(CARD.width - 2 * CARD.side)
    f.lines = {}
    for i = 1, 2 do
        local d = f:CreateTexture(nil, "ARTWORK")
        d:SetAtlas(DIVIDER_ATLAS)
        d:SetHeight(1)
        f.lines[i] = d
    end
    f.rows = { NewRow(f), NewRow(f), NewRow(f) }
    f.verdictMark = f:CreateTexture(nil, "ARTWORK")
    f.verdict = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    f.verdict:SetJustifyH("LEFT")
    f.verdict:SetWidth(CARD.width - 2 * CARD.side - 20)

    f.fix = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.fix:SetSize(CARD.fixWidth, CARD.button)
    f.ok = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.ok:SetSize(CARD.okWidth, CARD.button)
    f.ok:SetText(OKAY)
    f.ok:SetScript("OnClick", function() f:Hide() end)
    f:SetScript("OnHide", function() cardKind = nil end)

    if UISpecialFrames and tinsert then tinsert(UISpecialFrames, f:GetName()) end
    card = f
    return f
end

local function SetMark(tex, state, size)
    if not state then tex:Hide() return end
    tex:SetAtlas(MARK_ATLAS[state])
    -- the warning sign is 22 x 20, the others square
    tex:SetSize(size, state == "warn" and math.floor(size * 20 / 22 + 0.5) or size)
    tex:Show()
end

local function DrawCard(f, model, title, subtitle)
    local x, y = CARD.side, CARD.top
    f.brand:SetText(ns.TITLE .. Wrap(LIGHTGRAY_FONT_COLOR, "  ·  " .. subtitle))
    f.brand:ClearAllPoints()
    f.brand:SetPoint("TOPLEFT", x, -y)
    y = y + f.brand:GetStringHeight() + 4
    f.title:SetText(title)
    f.title:ClearAllPoints()
    f.title:SetPoint("TOPLEFT", x, -y)
    y = y + f.title:GetStringHeight() + 10

    local function Line(i)
        local d = f.lines[i]
        d:ClearAllPoints()
        d:SetPoint("TOPLEFT", 14, -y)
        d:SetPoint("TOPRIGHT", -14, -y)
        d:Show()
    end
    Line(1)
    y = y + 1 + 12

    local tx = x + CARD.icon + CARD.iconGap
    for i, data in ipairs(model.rows) do
        local r = f.rows[i]
        local top = y
        if data.atlas then
            r.icon:SetAtlas(data.atlas)
            r.icon:SetTexCoord(0, 1, 0, 1)              -- after SetAtlas: the whole art (ui-design skill)
        else
            r.icon:SetTexture(data.icon or data.texture or NO_GEAR_TEXTURE)
            -- a spell/item icon carries a 8% frame of its own; the game's lists cut it
            if data.icon then r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) else r.icon:SetTexCoord(0, 1, 0, 1) end
        end
        r.icon:ClearAllPoints()
        r.icon:SetPoint("TOPLEFT", x, -top)
        r.label:SetText(data.label)
        r.label:ClearAllPoints()
        r.label:SetPoint("TOPLEFT", tx, -top)
        local ty = top + r.label:GetStringHeight() + 2
        r.value:SetText(data.extra and (data.value .. Wrap(LIGHTGRAY_FONT_COLOR, "  ·  " .. data.extra)) or data.value)
        r.value:ClearAllPoints()
        r.value:SetPoint("TOPLEFT", tx, -ty)
        ty = ty + r.value:GetStringHeight()
        if #data.notes > 0 then
            r.notes:SetText(table.concat(data.notes, "\n"))
            r.notes:ClearAllPoints()
            r.notes:SetPoint("TOPLEFT", tx, -(ty + 4))
            r.notes:Show()
            ty = ty + 4 + r.notes:GetStringHeight()
        else
            r.notes:Hide()
        end
        SetMark(r.mark, data.state, CARD.mark)
        r.mark:ClearAllPoints()
        r.mark:SetPoint("TOPRIGHT", -CARD.side, -(top + 7))
        y = math.max(top + CARD.icon, ty) + CARD.rowGap
    end

    if model.verdict then
        Line(2)
        y = y + 1 + 10
        SetMark(f.verdictMark, model.verdict.state, 14)
        f.verdictMark:ClearAllPoints()
        f.verdictMark:SetPoint("TOPLEFT", x, -(y + 1))
        f.verdict:SetText(model.verdict.text)
        f.verdict:ClearAllPoints()
        f.verdict:SetPoint("TOPLEFT", x + 20, -y)
        f.verdict:Show()
        y = y + f.verdict:GetStringHeight() + 14
    else
        f.lines[2]:Hide()
        f.verdictMark:Hide()
        f.verdict:Hide()
        y = y + 4
    end

    f.ok:ClearAllPoints()
    if model.fix then
        -- THE PRESET'S NAME IS THE PLAYER'S, of any length, and a button cuts with "..." (no text cut, CLAUDE.md): the
        -- button grows with its text as the game's do (text + 40, SecureUIPanelTemplates.xml), up to what the row has;
        -- past that it says only "Load" -- the verdict line above already names the preset.
        local room = CARD.width - 2 * CARD.side - CARD.okWidth - CARD.buttonGap
        f.fix:SetText(format(L["Load %s"], model.fix.name or "?"))
        local tw = f.fix.GetTextWidth and f.fix:GetTextWidth()
        tw = type(tw) == "number" and tw or 0
        if tw + 40 > room then
            f.fix:SetText(L["Load"])
            tw = f.fix:GetTextWidth()
            tw = type(tw) == "number" and tw or 0
        end
        local fixWidth = math.min(room, math.max(CARD.fixWidth, tw + 40))
        f.fix:SetWidth(fixWidth)
        local preset = model.fix
        f.fix:SetScript("OnClick", function()
            ns.Data.Apply(preset, function(text) ns.Print(text) end)
        end)
        local total = fixWidth + CARD.buttonGap + CARD.okWidth
        f.fix:ClearAllPoints()
        f.fix:SetPoint("TOPLEFT", (CARD.width - total) / 2, -y)
        f.ok:SetPoint("LEFT", f.fix, "RIGHT", CARD.buttonGap, 0)
        f.fix:Show()
    else
        f.fix:Hide()
        f.ok:SetPoint("TOP", 0, -y)
    end
    f:SetHeight(y + CARD.button + CARD.bottom)
    f.__title, f.__subtitle = title, subtitle
end

--- Under the game's box of the moment, read from its edges (never anchored to it); else where the game's first dialog
--- hangs.
local function PlaceCard(f, kind)
    f:ClearAllPoints()
    local game = kind == "readycheck" and _G.ReadyCheckListenerFrame or _G.PVPReadyDialog
    local ok, bottom, cx, s = false, nil, nil, nil
    if type(game) == "table" and game.IsShown and game:IsShown() then
        ok, bottom = pcall(game.GetBottom, game)
        local okC, centerX = pcall(game.GetCenter, game)
        local okS, scale = pcall(game.GetEffectiveScale, game)
        if ok and okC and okS then cx, s = centerX, scale end
    end
    if type(bottom) == "number" and type(cx) == "number" and type(s) == "number" then
        local mine = UIParent:GetEffectiveScale()
        f:SetPoint("TOP", UIParent, "BOTTOMLEFT", cx * s / mine, bottom * s / mine - 4)
    else
        f:SetPoint("TOP", UIParent, "TOP", 0, -CARD.fromScreenTop)
    end
end

--- Opens the card. @return boolean shown
function Alert.ShowCard(kind, title, subtitle)
    local f = BuildCard()
    if not f then return false end
    local ok, model = pcall(Alert.CardModel, kind)
    if not ok or not model then
        ns.Log.Add("popup", { which = kind, action = "model", erro = tostring(model) })
        return false
    end
    local okD, err = pcall(DrawCard, f, model, title, subtitle)
    if not okD then
        ns.Log.Add("popup", { which = kind, action = "draw", erro = tostring(err) })
        return false
    end
    cardKind = kind
    f.__model = model
    PlaceCard(f, kind)
    -- AND AGAIN ON THE NEXT FRAME. The game's box opens on the same event as ours (READY_CHECK, UPDATE_BATTLEFIELD_STATUS),
    -- in an order nobody promises: read first, it is not on screen yet, and the card goes to the fallback spot -- which
    -- for the queue is exactly where the game hangs its invite (`StaticPopupSpecial_Show`, PVPHelper.lua).
    C_Timer.After(0, function()
        if Alert.CardShown(kind) then PlaceCard(f, kind) end
    end)
    f:Show()
    f:Raise()
    if PlaySound and SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPEN then pcall(PlaySound, SOUNDKIT.IG_MAINMENU_OPEN) end
    return true
end

--- Redraws what is on screen with what is on now (after a swap, a loaded item, the 2 s gear reading). Coalesced:
--- a swap fires a burst of events.
function Alert.RefreshCard()
    if not Alert.CardShown() or cardRefreshing then return end
    cardRefreshing = true
    C_Timer.After(0.3, function()
        cardRefreshing = false
        if not Alert.CardShown() then return end
        local kind, f = cardKind, card
        local ok, model = pcall(Alert.CardModel, kind)
        if ok and model and pcall(DrawCard, f, model, f.__title, f.__subtitle) then f.__model = model end
    end)
end

function Alert.HideCard(kind)
    if card and card:IsShown() and (kind == nil or kind == cardKind) then
        card:Hide()
        return true
    end
    return false
end

function Alert.CardShown(kind)
    return card ~= nil and card:IsShown() and (kind == nil or kind == cardKind)
end

function Alert.__card() return card end

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
        Alert.HideCard("queue")
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

    -- (26/10) THE CARD, under the game's invite: the map in gold, the moment in the line above it.
    local cardTitle = titulo ~= L["PvP queue is up — check before you enter"] and titulo or L["What you are using"]
    local ok = Alert.ShowCard("queue", cardTitle, L["PvP queue is up"])
    local shownCard = ok
    if not ok then
        -- The box is OURS, not the game's `StaticPopup` (05/10: a box of the game opened by an addon
        -- marks the game's own dialog code, and the game then refuses a protected call of its own
        -- and blames the addon -- `Dialog.lua` has the whole story).
        local okD, shown = pcall(ns.Dialog.Show, "summary", titulo .. "\n\n" .. Alert.Summary("\n"))
        ok = okD and shown == true
    end
    ns.Log.Add("popup", { which = "queue", action = "show", ok = ok, card = shownCard })
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
        -- (26/10) THE CARD, under the game's "Ready Check" box, and its subtitle is the game's own name for the moment
        -- (READY_CHECK: "Todos prontos?" in pt-BR). The wrong-content gear is a row of the card now, not a second box.
        local ok = Alert.ShowCard("readycheck", L["What you are using"], L["Ready check"])
        local shownCard = ok
        if not ok then
            local okD, shown = pcall(ns.Dialog.Show, "summary",
                L["What you are using"] .. "\n\n" .. Alert.Summary("\n"))
            ok = okD and shown == true
        end
        ns.Log.Add("popup", { which = "readycheck", action = "show", ok = ok, card = shownCard })
        if not ok and RaidWarningUtil and RaidWarningUtil.AddMessage then
            -- Only then the warning in the middle of the screen, as a net: a warning that goes away beats nothing.
            pcall(RaidWarningUtil.AddMessage, resumo, NORMAL_FONT_COLOR, 5)
        end
        -- Without the card, the gear warning still comes on top, as before.
        if not shownCard then Alert.Check("readycheck") end
    end
end

--- The ready check's card closes with the check: when it ends, and when the player answers it (`READY_CHECK_CONFIRM`
--- for "player"). The leader who started it is counted ready by the game at once -- for him only the end closes it.
function Alert.OnReadyCheckEvent(event, unit)
    if event == "READY_CHECK_FINISHED" then
        Alert.HideCard("readycheck")
    elseif event == "READY_CHECK_CONFIRM" and not cardInitiatorIsMe and type(unit) == "string"
        and UnitIsUnit and UnitIsUnit(unit, "player") then
        Alert.HideCard("readycheck")
    end
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
    frame:RegisterEvent("READY_CHECK_CONFIRM")
    frame:RegisterEvent("READY_CHECK_FINISHED")
    -- Only to redraw the summary card while it is on screen.
    for _, e in ipairs({ "TRAIT_CONFIG_UPDATED", "ACTIVE_PLAYER_SPECIALIZATION_CHANGED" }) do
        if not C_EventUtils or not C_EventUtils.IsEventValid or C_EventUtils.IsEventValid(e) then
            frame:RegisterEvent(e)
        end
    end
    -- These only CANCEL: they can hide a warning, never create one.
    frame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    frame:RegisterEvent("EQUIPMENT_SWAP_FINISHED")
    if C_EventUtils and C_EventUtils.IsEventValid
        and C_EventUtils.IsEventValid("ADDON_RESTRICTION_STATE_CHANGED") then
        frame:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED")
    end

    frame:SetScript("OnEvent", function(_, event, a, b)
        if event == "READY_CHECK" then
            -- `a` is the initiator's name (PartyInfoDocumentation, 12.1.5), read as the game's own box reads it
            cardInitiatorIsMe = type(a) == "string" and UnitIsUnit and UnitIsUnit("player", a) or false
            Alert.OnReadyCheck()

        elseif event == "READY_CHECK_CONFIRM" or event == "READY_CHECK_FINISHED" then
            Alert.OnReadyCheckEvent(event, a)

        elseif event == "TRAIT_CONFIG_UPDATED" or event == "ACTIVE_PLAYER_SPECIALIZATION_CHANGED" then
            -- the talents or the spec changed (the card's button, or by hand): the card shows what is on now
            Alert.RefreshCard()

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
            Alert.RefreshCard()

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
