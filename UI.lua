-- RocketSwap | UI.lua
-- The window: the list of sets on the left, the editor on the right, the state in the footer.
--
-- THIS FILE WAS REWRITTEN after the first in-game test. The print showed three defects,
-- and all three came from the same root: **I anchored content without counting on the template's art.**
-- The geometry below was measured in the source code of Blizzard's 12.1.0 UI, not estimated.
--
--   1. THE PORTRAIT OVER THE TEXT. `PortraitFrameTemplate` draws a disc of Ø58 with its
--      centre at (26, −22) of the frame. The "Conjuntos" label was at (14, −34),
--      sqrt(12² + 12²) = 17px from the centre -- that is, 12px INSIDE the disc.
--      RULE: nothing anchored on `frame` with x < 58 and y > −55. Nothing here breaks it.
--
--   2. ORPHAN LABELS. With zero sets, "Nome / Especialização / Talentos / Itens"
--      showed with no field under them: I hid the controls and forgot the labels.
--      The fix is not one more `SetShown` -- it is that **the "nothing selected" state stopped
--      existing**: with ≥1 set, the list selects the first by itself. Blizzard's
--      precedent: `ClickBindingFrameMixin:OnShow` focuses the first item.
--      And each label now lives INSIDE its group -- hiding the group hides both.
--
--   3. AN EMPTY WINDOW. 640×452 for 2 to 5 sets. Now 520×320, derived from the content, and the
--      empty state is a centred block with a phrase and a button.
--
-- THE TEMPLATE CHANGED to `ButtonFrameTemplate`: it is `PortraitFrameTemplate` plus an `Inset` already
-- placed at the official offsets (`PANEL_INSET_*` in `SharedUIPanelTemplates.lua:4-9`).
-- Anchoring on the recessed area instead of the bare frame makes bug 1 impossible to repeat.
local ADDON, ns = ...
local L = ns.L

local UI = {}
ns.UI = UI

-- Every number has an origin. Where there is a quote, it is from a file of client 12.1.0.
-- The height went from 420 to 452 when the War Mode sub-option came into the Warnings strip
-- (12/09). The sum is closed, not aesthetic: the strip starts at −304, three boxes end at −112
-- inside it (142 tall), and the footer `ButtonFrameTemplate` reserves eats 26 px of the bottom
-- ⇒ 304 + 142 + 26 = 472, plus the same 4 px of slack the 420 window already had.
-- (It was 118/452 with three boxes; the queue invite's, 18/09, brought the fourth.)
-- (!) THE WIDTH WENT FROM 520 TO 620 and then to 680 (22/09), and the gain goes ENTIRELY to the
-- list both times. The right column stays pixel for pixel as it was: `FIELD_W` and `NAME_W`
-- are absolute measures aligned with the edge, and since `COL_X` moves along with `WIDTH`, the art
-- still ends 20 px from the right (500 with a 520 window, 660 with a 680 one).
--
-- Splitting the gain between the two columns would force recomputing both, and the right one was never
-- tight -- what is tight is the list, which became cards and carries a label on each line.
-- (25/10) 680 -> 720, the 40 to the editor's column this time: a loadout Rocket SBA Lab makes has up to 30 letters,
-- "Rocket SBA Lab: M+ Moldachamas" is 201 px in GameFontHighlight, and the combo of 200 shows 166 (the ruler)
local WIDTH = 720
local HEIGHT
local LIST_W = 420            -- largura externa do inset da lista: x 4..424
local GUTTER = 20             -- calha entre colunas (MountJournal)
local COL_X = 444             -- borda esquerda da ARTE da coluna direita
local ROW_SPACING = 2

-- ⛑ THE ROW BECAME A CARD, and so its height stopped being constant.
--
-- The user's request: *"Spec: Tal (quebra linha) Talento: tal (quebra linha) Equipamento: tal"*.
-- Before, all that was ONE line with dots between -- `Sangue · Blood M+ · Blood · Dark` -- and
-- on it the player had to know by heart which value was which. With a label per line, there is nothing
-- to know: it is written.
--
-- The height follows what the set defines. Reserving four lines always would leave three empty
-- on an items-only set, and space kept for content that does not exist is what most makes a
-- window look broken -- the same rule `Data.GetProgress` already follows when filtering steps.
local CARD_PAD = 8            -- breathing room above the name and below the last line
local CARD_NAME_INK = 16      -- `GameFontNormal` a 13pt, arredondado pela caixa da fonte
local CARD_LINE = 15          -- passo entre linhas de detalhe (11pt de tinta + 4 de respiro)
local CARD_WARN = 24          -- the warning's plate: a button's height (22) plus 2 of slack
-- THE CARD'S DESIGN, chosen by the user after two wrong attempts of mine:
--
--   Tank                        [ Carregar ]     <- the title alone, at the margin
--   (icon)   Especializacao: Sangue              <- the icon to the left of the BLOCK of fields
--            Talentos: Blood M+
--            Equipamento: Blood
--
-- 0.34.1 had put the icon at the top as a badge and the title under it. Rejected on the
-- spot: *"ficou ruim o titulo, eu gostei do icone ao lado no comeco"*. The icon goes back to the
-- side -- only beside the FIELDS, not the title, which is what frees the title's line.
-- (!) THE ICON FILLS THE BLOCK OF FIELDS. The request: *"aumentar o icone para preencher o espaco
-- que falta das 4 linhas escritas"*. At a fixed 32 it took half the height beside four
-- lines, and left a gap under it -- a gap beside content is what makes the list
-- look half built.
--
-- It takes the block's size: 60 with four fields, and the FLOOR of 32 with one, because a line
-- measures 15 and an icon of 15 cannot be seen.
--
-- (!) BUT THE TEXT'S INDENT DOES NOT FOLLOW, and that is the decision holding the design. If it
-- followed, a card of four fields and one of one would start their text at different X's, and the
-- alignment BETWEEN cards is what makes a list look like a list. So the indent is fixed, at the
-- size of the biggest icon, and a smaller icon centres in that column.
local CARD_ICON_MIN = 32
local CARD_ICON_MAX = CARD_LINE * 4       -- 60: a altura de quatro campos
local CARD_ICON_X = 6                     -- margem esquerda da coluna do icone
local CARD_LEFT = CARD_ICON_X + CARD_ICON_MAX + 8
local CARD_NAME_GAP = 4       -- entre o titulo e a primeira linha de campo

-- THE TEXT'S WIDTH CEILING. The other complaint about 0.34.1 was *"ficou muito comprido as linhas"*:
-- in a 620 window they crossed from edge to edge.
--
-- The number is DERIVED, not chosen: it is what is left of the list's width after the fields'
-- indent and the scroll bar. A fixed ceiling bigger than that would shorten nothing -- it would only
-- let the text overflow the row, which is worse than the long line.
local CARD_TEXT_W = LIST_W - CARD_LEFT - 30

-- ⛑ HOW MANY WHOLE CARDS HAVE TO FIT WITHOUT SCROLLING. The user's request: three.
--
-- The list's inset had a FIXED height (from -60 to -300, 240 px) and did not follow the window -- that
-- is why raising `HEIGHT` in the round before gave not one pixel more of list. The height is now
-- DERIVED from the tallest card, the four-field one, and the rest of the window moves down with it.
local CARDS_VISIVEIS = 3
-- The FOUR-FIELD card, without the warning strip -- and the choice is deliberate. With the strip it
-- measures 116, and sizing the window by it would make it 72 px taller **for everyone, all the
-- time**, because of a state that is an error and meant to last little. With a missing piece in all
-- three sets, the list scrolls a bit; and the right thing is the player fixing it, not the window growing.
-- The block of fields' height is the BIGGER of the lines and the icon: with one field only, the lines
-- measure 15 and the icon 32, and without this max it would leak out of the card.
-- The block of fields' height, which is also the icon's SIZE: the two are the same measure
-- since the icon started filling the block.
local function FieldsHeight(n)
    return math.max(CARD_LINE * n, CARD_ICON_MIN)
end
local CARD_TOP = CARD_PAD + CARD_NAME_INK + CARD_NAME_GAP   -- onde o bloco de campos comeca
local CARD_MAX = CARD_TOP + FieldsHeight(4) + CARD_PAD
local LIST_TOP = -60
local LIST_H = CARD_MAX * CARDS_VISIVEIS + ROW_SPACING * (CARDS_VISIVEIS - 1) + 6  -- 6 = 3+3 do inset
local LIST_BOTTOM = LIST_TOP - LIST_H
-- The Warnings strip starts right below the inset, with the same 4 of slack it always had.
local WARN_STRIP_Y = LIST_BOTTOM - 4

-- The window's closed sum, inherited from the version before and now anchored on the list:
-- the Warnings strip (142 of content) + the 26 footer `ButtonFrameTemplate` reserves,
-- plus the 4 of slack the window always had.
local WARN_STRIP_H = 130
local TEMPLATE_FOOTER = 26
-- + the support line at the very bottom (Donate.lua, `DONATE_ROW`, 27/09).
local DONATE_ROW = ns.DONATE_ROW or 0
HEIGHT = -WARN_STRIP_Y + WARN_STRIP_H + TEMPLATE_FOOTER + 4 + DONATE_ROW
local FIELD_W = 240           -- combos: the widest loadout name the lab makes (201 px) + the combo's 34 of art
local NAME_W = 251            -- EditBox: its art ends where the combos' does
local GROUP_STEP = 50         -- label (15) + combo (25) + breathing room (10)
local ATTIC_Y = -30           -- the band between the title and the inset
-- The editor column, top to bottom (27/09): the two buttons to the game's windows, the title of the
-- name box, the box, the divider and the fields. Same rhythm as a field group: title 12 + 3 above
-- its box, 10 between blocks, and the 16/10 around the divider that the column already had.
local EDITOR_TOP = -60                           -- level with the list's inset (`LIST_TOP`)
local TOOL_W = 122                               -- two of them + 7 of gap = NAME_W
local NAME_TITLE_Y = EDITOR_TOP - 22 - 10        -- button (22) + gap
local NAME_Y = NAME_TITLE_Y - 15                 -- title (12) + 3, like `Group`
local DIVIDER_Y = NAME_Y - 22 - 16
local FIELDS_Y = DIVIDER_Y - 10
local CHILD_INDENT = 15       -- a child option's indent (`Blizzard_SettingControls.lua:1`)

local frame, editor, selection
local lastFilledRow      -- so para o harness: ver `UI.DebugLastRow`

-- The set being edited, kept HERE and not asked of the ScrollBox.
--
-- Two reasons, both found in the first in-game test:
--
--   1. `SelectionBehaviorMixin:GetSelectedElementData()` returns a **LIST**, not an
--      element (`ScrollUtil.lua:434`). An empty list is TRUE in Lua, so the editor
--      thought a set was selected -- a set with no spec, no talents and no
--      items. That was the "combo de talentos não traz nada": with no spec, `GetLoadouts(nil)`
--      returns an empty list. And that was the "a deleção não funcionou": `UI.Delete` looked for
--      an empty table in the list and did not find it.
--   2. `SetDataProvider` **erases the selection** (`OnScrollBoxDataProviderReassigned`,
--      `ScrollUtil.lua:413`). Without keeping it outside, any gear swap in the game
--      would redraw the list and throw the selection back to the first set.
local current

--------------------------------------------------------------------------------
local function Presets()
    return ns.db and ns.db.presets or {}
end

--- The row's support text: "Gélido · SBA ST · Frost". Only what the set defines goes in -- a
--- set that does not touch talents must not suggest that it does.
--- The card's lines, each with its own label, in the order the swap happens.
---
--- Only what the set defines goes in -- the same rule as the progress panel. An items-only
--- set shows one line, and not four, three of which would say "(nenhum)".
local function CardLines(preset)
    local linhas = {}

    local spec = ns.Data.GetSpecByIndex(preset.spec)
    if spec then
        linhas[#linhas + 1] = { L["Specialization"], spec.name }
    end
    if preset.talent then
        linhas[#linhas + 1] = { L["Talents"],
            ns.Data.LoadoutName(spec and spec.id, preset.talent) or ("#" .. preset.talent) }
    end
    if preset.gear then
        linhas[#linhas + 1] = { L["Gear"],
            ns.Data.GearSetName(preset.gear) or ("#" .. preset.gear) }
    end
    if preset.transmog then
        linhas[#linhas + 1] = { L["Appearance"],
            ns.Data.OutfitName(preset.transmog) or ("#" .. preset.transmog) }
    end

    return linhas
end

--- How tall this card is. The list asks this per element, and not one fixed height for all.
local function CardHeight(preset)
    local n = #CardLines(preset)
    local altura = CARD_TOP + FieldsHeight(n) + CARD_PAD
    if preset.gear and ns.Data.GearSetProblem(preset.gear) then
        altura = altura + CARD_WARN
    end
    return altura
end

local function Subtitle(preset)
    local parts = {}

    local spec = ns.Data.GetSpecByIndex(preset.spec)
    if spec then parts[#parts + 1] = spec.name end

    if preset.talent then
        parts[#parts + 1] = ns.Data.LoadoutName(spec and spec.id, preset.talent)
            or ("#" .. preset.talent)
    end
    if preset.gear then
        parts[#parts + 1] = ns.Data.GearSetName(preset.gear) or ("#" .. preset.gear)
    end
    if preset.transmog then
        parts[#parts + 1] = ns.Data.OutfitName(preset.transmog) or ("#" .. preset.transmog)
    end

    return table.concat(parts, "  ·  ")
end

--------------------------------------------------------------------------------
-- A linha da lista
--------------------------------------------------------------------------------
--- Builds the row once. The ScrollBox reuses the same frame for different data, so
--- everything that depends on the set goes in `Fill`, not here.
local function BuildRow(row)
    if row.built then return end
    row.built = true

    -- The real height comes from `CardHeight`, per element; this is only the starting one.
    row:SetHeight(CARD_PAD * 2 + CARD_NAME_INK + CARD_LINE)

    -- No background of its own: the inset's marble gives the background. The row only paints itself when
    -- it is under the mouse or selected -- the pattern of the game's Options panel.
    --
    -- The old alphas (0.12 on selection, 0.07 on hover) were 3 to 6× weaker than the native ones
    -- and without `ADD`: that is why the selection did not show. These two textures and these
    -- numbers are copied from `GearSetButtonTemplate`, Blizzard's own list of equipment
    -- sets. `TexCoord 0.2..0.8` cuts the ends so it stretches without deforming.
    row.selected = row:CreateTexture(nil, "OVERLAY")
    row.selected:SetAllPoints()
    row.selected:SetTexture("Interface\\FriendsFrame\\UI-FriendsFrame-HighlightBar")
    row.selected:SetTexCoord(0.2, 0.8, 0, 1)
    row.selected:SetBlendMode("ADD")
    row.selected:SetAlpha(0.4)
    row.selected:Hide()

    row:SetHighlightTexture("Interface\\FriendsFrame\\UI-FriendsFrame-HighlightBar-Blue")
    local highlight = row:GetHighlightTexture()
    if highlight then
        highlight:SetTexCoord(0.2, 0.8, 0, 1)
        highlight:SetBlendMode("ADD")
        highlight:SetAlpha(0.4)
    end

    row.icon = row:CreateTexture(nil, "ARTWORK")
    -- Tamanho e posicao sao reacertados em `FillRow`: os dois dependem de quantos campos o
    -- conjunto define.
    row.icon:SetSize(CARD_ICON_MIN, CARD_ICON_MIN)
    row.icon:SetPoint("TOPLEFT", CARD_ICON_X, -CARD_TOP)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.name:SetPoint("TOPLEFT", 8, -CARD_PAD)
    -- The title stops before the button, so it does not use `CARD_TEXT_W`: here the limit is not
    -- for reading, it is for collision.
    row.name:SetPoint("RIGHT", row, "RIGHT", -86, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    -- ONE LINE PER FIELD, each with a label. Four fixed slots because there are four possible
    -- fields; the ones left over stay hidden, and it is the card's HEIGHT that follows (`CardHeight`).
    row.lines = {}
    for i = 1, 4 do
        local fs = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        fs:SetPoint("TOPLEFT", CARD_LEFT, -(CARD_TOP + CARD_LINE * (i - 1)))
        fs:SetWidth(CARD_TEXT_W)
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(false)
        row.lines[i] = fs
    end

    -- THE WARNING STRIP. Red alone, in 11pt text among other 11pt texts,
    -- is too weak a signal -- and this project's skill is explicit: emphasis comes from adding weak
    -- signals. Here there are three: a red plate behind, the "!" and the text's colour.
    row.warn = CreateFrame("Frame", nil, row)
    row.warn:SetHeight(CARD_WARN - 2)
    row.warn:SetPoint("LEFT", CARD_LEFT, 0)
    row.warn:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    row.warn.bg = row.warn:CreateTexture(nil, "BACKGROUND")
    row.warn.bg:SetAllPoints()
    row.warn.bg:SetColorTexture(0.75, 0.15, 0.15, 0.20)

    row.warn.text = row.warn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.warn.text:SetPoint("LEFT", 6, 0)
    row.warn.text:SetJustifyH("LEFT")
    row.warn.text:SetWordWrap(false)
    row.warn.text:SetTextColor(1, 0.45, 0.42)

    -- THE FIX HAS A BUTTON OF ITS OWN, and does not take Load's place. The user was explicit
    -- (*"se tiver com erro de equipamentos, o botão de carregar fica indisponível para trocar"*),
    -- and it is the same rule he had already given for the specialization restriction: a button that
    -- takes the click and then answers "it did not work" is worse than a dimmed button.
    row.fix = CreateFrame("Button", nil, row.warn, "UIPanelButtonTemplate")
    row.fix:SetSize(112, 20)
    row.fix:SetPoint("RIGHT", -2, 0)
    row.fix:SetScript("OnClick", function(self)
        local preset = row.preset
        if self.action == "save" then
            local problema = preset and preset.gear and ns.Data.GearSetProblem(preset.gear)
            if problema and problema.consertavel and ns.Data.SaveGearSet(preset.gear) then
                ns.Print(format(L["%s updated with what you are wearing."], problema.nome or "?"))
            end
            UI.Refresh()
        else
            ns.Data.OpenEquipmentManager()
        end
    end)
    row.warn:Hide()

    -- The button and the check mark share the same slot: the row does not reflow when the set comes to
    -- be applied, because the text reserves the 86px both ways.
    -- A SECURE BUTTON, and not on a whim: **switching an appearance set is protected**. The two
    -- functions that do it (`ChangeToOutfit` and `ChangeDisplayedOutfit`) do not answer addon
    -- code -- they return success and do nothing, which was the "não troca e não gera nenhum erro"
    -- reported three times. Patch 12.0.5 added a secure action `"outfit"` exactly because of
    -- that.
    --
    -- So what switches the appearance is the PLAYER'S CLICK on this button, not our code. The
    -- other three steps (spec, talents, items) stay ours and run in `PostClick`.
    --
    -- `PostClick`, and not `OnClick`: on a secure button `OnClick` runs inside the protected path
    -- and what we do there taints the rest. `PostClick` runs after, outside it.
    row.load = CreateFrame("Button", nil, row,
        "UIPanelButtonTemplate, SecureActionButtonTemplate")
    row.load:SetSize(74, 22)
    -- ON THE ICON'S LINE: the only band of the card with no text, and so the button stops competing
    -- for height with the title. On top, it sits in the corner where the eye already looks for an action.
    row.load:SetPoint("RIGHT", -6, 0)
    row.load:SetText(L["Load"])
    row.load:RegisterForClicks("AnyUp")
    row.load:SetAttribute("useOnKeyDown", false)
    -- The same guard as the macro's (Macro.lua): a pre-flight "no" disarms the outfit before the
    -- secure action runs, so the appearance never changes alone.
    --
    -- (!) `UI.ArmOutfit`, NOT `ArmOutfit` (28/09). The local function is declared BELOW this one,
    -- so here the bare name was a global that does not exist: a Lua error on every click of Load
    -- out of combat, 12 of them in the error log, and it went out in the 0.38.0. The harness only
    -- clicked the macro's button, never this one.
    row.load:SetScript("PreClick", function(self)
        local p = self:GetParent().preset
        if p and not InCombatLockdown() then
            UI.ArmOutfit(self, (#ns.Data.Preflight(p, true) == 0) and p or nil)
        end
        -- (06/10) WHICH control took the click, and what was armed on it. The game recorded
        -- "RocketSwap tried to call the protected function 'ChangeToOutfit()'" from inside the
        -- secure click, once, and the diary could not say whether the click was on this button,
        -- on the minimap list or on a macro.
        ns.Log.Add("click", { where = "window", preset = p and p.name or "?",
            type = tostring(self:GetAttribute("type")), outfit = tostring(self:GetAttribute("outfit-index")),
            combat = InCombatLockdown() and true or false })
    end)
    row.load:SetScript("PostClick", function(self)
        UI.Load(self:GetParent().preset)
    end)

    -- A DIMMED BUTTON HAS TO SAY WHY, or it is just a broken button. The reason comes from the
    -- game, already translated (`CanPlayerUseTalentSpecUI` returns `canUse, failureReason`).
    row.load:SetScript("OnEnter", function(self)
        if not self.blockedReason then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["Load"], 1, 1, 1)
        GameTooltip:AddLine(self.blockedReason, 1, 0.5, 0.4, true)
        GameTooltip:Show()
    end)
    row.load:SetScript("OnLeave", GameTooltip_Hide)
    -- A button that is off says why only if the mouse still reaches it.
    row.load:SetMotionScriptsWhileDisabled(true)

    row.check = row:CreateTexture(nil, "OVERLAY")
    row.check:SetSize(16, 16)
    row.check:SetPoint("RIGHT", -8, 0)
    row.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    row.check:Hide()

    -- THE ROW'S CLICK. It did not exist: I swapped the manual `OnClick` for
    -- `AddSelectionBehavior` thinking the behaviour captured the click too. It only
    -- manages the selection's STATE -- whoever clicks is who selects. That was the "não consigo clicar
    -- em outros conjuntos".
    row:RegisterForClicks("LeftButtonUp")
    row:SetScript("OnClick", function(self)
        if selection and self.GetElementData then
            selection:Select(self)
        end
    end)
    -- Dragged, the card becomes its macro on the cursor (UI.DragPreset).
    row:RegisterForDrag("LeftButton")
    row:SetScript("OnDragStart", function(self) UI.DragPreset(self.preset) end)

    row:SetScript("OnEnter", function(self)
        if not self.preset then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local named = ns.Data.HasName(self.preset)
        GameTooltip:SetText(named and self.preset.name or L["Unnamed"], 1, 1, 1)
        GameTooltip:AddLine(Subtitle(self.preset), 0.7, 0.7, 0.7, true)
        if named then
            GameTooltip:AddLine(L["Drag to an action bar to make it a button."], 0.5, 0.8, 1, true)
        else
            GameTooltip_AddErrorLine(GameTooltip, L["Give the preset a name first."])
        end

        -- THE WHY OF THE RED. Without this line the person sees "1 item missing" and concludes the wrong
        -- thing -- that the swap will be incomplete. The real damage is another: the slot keeps
        -- the piece that was already there, which may be the previous role's.
        local problema = self.preset.gear and ns.Data.GearSetProblem(self.preset.gear)
        if problema then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(format(L["%s is missing %d item(s): the slot keeps what you are wearing, which may be wrong. Save the set first."],
                problema.nome or "?", problema.perdidas), 1, 0.35, 0.35, true)
            if problema.slots then
                GameTooltip:AddLine(table.concat(problema.slots, ", "), 0.8, 0.6, 0.6, true)
            end
            GameTooltip:AddLine(problema.consertavel
                and L["You are already wearing the rest of it — use /rs fix to update the set."]
                or L["Open the equipment manager, fix the set and save it, then switch."],
                0.7, 0.7, 0.7, true)
        end

        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", GameTooltip_Hide)
end

--- Arms (or disarms) the secure appearance action on a button.
---
--- `action = "change"` and not `"toggle"`: in `SECURE_ACTIONS.outfit` `"toggle"` becomes
--- `allowRemoveOutfit = true`, and then asking for the appearance already on is treated as **clearing**
--- (`SlashCommands.lua:1714`) -- loading the same set twice WOULD TAKE the outfit off the second time.
---
--- IN COMBAT A SECURE FRAME'S ATTRIBUTE IS NOT TOUCHED. Leaving without doing anything is right: the
--- attribute already there still holds, and `Data.Apply` refuses to apply in combat anyway.
local function ArmOutfit(button, preset)
    if InCombatLockdown() then return end

    -- (!) A BROKEN SET DOES NOT ARM THE SECURE ACTION. The `outfit` action runs INSIDE the click, before
    -- any Lua of ours -- so refusing the swap in `Data.Apply` would come too late for it, and the
    -- player would end up with the outfit switched and nothing else. Disarming here is the only point
    -- where the appearance can be kept from going alone.
    local quebrado = preset and preset.gear and ns.Data.GearSetProblem(preset.gear)

    local index = not quebrado and preset and preset.transmog
        and ns.Data.OutfitIndex(preset.transmog)
    if index then
        button:SetAttribute("type", "outfit")
        button:SetAttribute("outfit-index", index)
        button:SetAttribute("action", "change")
    else
        -- No appearance in the set (or the appearance was deleted from the game): the button goes back to being
        -- a plain button. Leaving `type` armed with a nil index would make the click fall into the
        -- `SECURE_ACTIONS.outfit` branch and do nothing, silently.
        button:SetAttribute("type", nil)
        button:SetAttribute("outfit-index", nil)
        button:SetAttribute("action", nil)
    end
end

-- The macro's button arms the outfit the same way (Macro.lua).
UI.ArmOutfit = ArmOutfit

--- Fills the row with a set.
-- (!) TURNING A BUTTON ON AND OFF IS PROTECTED (`SetEnabled`, `IsProtectedFunction` in the
-- client's SimpleButtonAPIDocumentation.lua, 12.1.0), and Load is a secure button: in combat the
-- game blocks the call. The reason is kept at once -- the tooltip is ours -- and the button is
-- set when the combat ends (`UI.SyncLoadButtons`, from the window's clock).
local loadStatePending = false
local function SetLoadState(row, preset)
    local motivo = ns.Data.LoadBlockedReason(preset)
    row.load.blockedReason = motivo
    if InCombatLockdown() then
        loadStatePending = true
        return
    end
    row.load:SetEnabled(motivo == nil)
end

-- (!) WHAT A ROW SHOWS THAT IS THE GAME'S TO CHANGE (28/09): how many pieces the gear set has
-- lost, and why Load is off. The user's print had "PvP: 1 item missing" on our row while the
-- game's own equipment manager, open beside it, showed the same set with nothing missing. Both
-- read the same number (`numLost`); the game's list draws again on BAG_UPDATE
-- (`PaperDollEquipmentManagerPane_OnEvent`, 12.1.0.69933) and ours did not listen to the bags, so
-- a row could keep a number read in the middle of a swap. Instead of guessing which event was
-- missing, the row keeps what it was drawn from and the window's clock compares it with the
-- game (`UI.SyncLoadButtons`).
--
-- "In use" goes along, for the same reason: the diary of 07/09 has EQUIPMENT_SWAP_FINISHED
-- arriving with `true` while the set still read as not worn. What is read at the event is not
-- always what is true a moment later.
local function RowState(preset)
    local problema = preset.gear and ns.Data.GearSetProblem(preset.gear)
    return (problema and problema.perdidas or 0)
        .. "|" .. (ns.Data.IsLoaded(preset) and "in use" or "")
        .. "|" .. (ns.Data.LoadBlockedReason(preset) or "")
end

-- The diary says WHEN a set began to miss a piece and when it stopped, with the game's count
-- and whether a switch was running: it is what tells a number of the middle of a swap from a
-- piece that is really gone. One line per change, not per drawing.
local lostSeen = {}
local function NoteLost(preset, problema)
    local id = preset.gear
    if id == nil then return end
    local agora = problema and problema.perdidas or 0
    if (lostSeen[id] or 0) == agora then return end
    lostSeen[id] = agora
    ns.Log.Add("falta", {
        conjunto = id,
        estado = ns.Data.DescribeGearSet(id),
        slots = problema and problema.slots and table.concat(problema.slots, ", ") or nil,
        trocando = ns.Data.IsApplying(),
    })
end

local function FillRow(row, preset)
    BuildRow(row)
    row.preset = preset
    ArmOutfit(row.load, preset)

    -- Without a name the row says so in the game's red, like a broken set in its equipment
    -- manager: it is a preset that asks for something before it can be used.
    row.name:SetText(ns.Data.HasName(preset) and preset.name
        or RED_FONT_COLOR:WrapTextInColorCode(L["Unnamed"]))

    local linhas = CardLines(preset)
    for i, fs in ipairs(row.lines) do
        local linha = linhas[i]
        fs:SetShown(linha ~= nil)
        if linha then
            -- LABEL and VALUE on the same line, the label dimmed: the eye scans the values
            -- vertically and only reads the label when it needs to. Two brightnesses, no new colour.
            fs:SetText("|cff9a9a9e" .. linha[1] .. ":|r  " .. (linha[2] or "?"))
        end
    end
    -- THE ICON TAKES THE BLOCK OF FIELDS' HEIGHT, and touches the title. It was once centred
    -- vertically, which with four fields pushed it 14 px down and left it floating beside
    -- the second line; anchored at the top, it sits right under the title with any number of
    -- fields.
    --
    -- HORIZONTALLY it centres in the column, which has a fixed width: that is what keeps the text
    -- of every card starting at the same X, whatever number of fields each has.
    local blocoH = FieldsHeight(#linhas)
    row.icon:SetSize(blocoH, blocoH)
    row.icon:ClearAllPoints()
    row.icon:SetPoint("TOPLEFT",
        CARD_ICON_X + math.floor((CARD_ICON_MAX - blocoH) / 2), -CARD_TOP)

    row:SetHeight(CardHeight(preset))
    lastFilledRow = row

    local _, icon = ns.Data.GearSetName(preset.gear)
    row.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")

    -- ONE channel per fact: the gold bar says "selected", the button's slot says "applied".
    -- The version before also tinted the name, and gold-against-almost-white is a distinction
    -- nobody reads -- two signals for the same fact fighting with the selection bar.
    -- A broken set announces itself ON THE ROW, before any click: it is the same signal the
    -- game's equipment manager gives (the name in red), and it is the warning the user asked for
    -- -- *"a gente consegue antes de trocar, avisar isso"*.
    -- THE WARNING STRIP, anchored below the last line that showed.
    local problema = preset.gear and ns.Data.GearSetProblem(preset.gear)
    NoteLost(preset, problema)
    row.warn:SetShown(problema ~= nil)
    if problema then
        row.warn:ClearAllPoints()
        row.warn:SetPoint("LEFT", CARD_LEFT, 0)
        row.warn:SetPoint("RIGHT", row, "RIGHT", -6, 0)
        row.warn:SetPoint("TOP", row, "TOP", 0, -(CARD_TOP + FieldsHeight(#linhas) + 2))
        row.warn.text:SetText("|cffff5a52!|r  " .. format(L["%s: %d item(s) missing"],
            problema.nome or "?", problema.perdidas))
        row.fix.action = ns.Data.GearFixAction(preset)
        row.fix:SetText(row.fix.action == "save" and L["Save set"] or L["Equipment Manager"])
    end

    local loaded = ns.Data.IsLoaded(preset)
    row.check:SetShown(loaded)
    row.load:SetShown(not loaded)

    -- A BUTTON DISABLED WHEN THE GAME DOES NOT ALLOW, and the idea is the user's: *"se houver isso, tem
    -- que desabilitar os botões de carregar preset até que possa ser feito"*. He is right --
    -- a button that takes the click and then answers "it did not work" is worse than a dimmed button.
    --
    -- IT ONLY APPLIES TO A SET THAT SWITCHES SPEC. A set that only touches items has no reason to
    -- be blocked by a specialization restriction, and disabling them all would punish the
    -- innocent -- the rule is the SAME the step applies, and so the two cannot drift apart.
    -- WITH A PIECE MISSING, LOAD STAYS DIMMED. The chain refuses anyway, and the rule
    -- is the same that already holds for the specialization restriction: a button that takes the click
    -- and then answers "it did not work" is worse than a dimmed button. The red strip's button acts.
    -- Both reasons to dim the button come from the SAME function (`Data.LoadBlockedReason`), which
    -- is where the harness reaches. What is left here is the drawing: dimming and keeping the tooltip's phrase.
    SetLoadState(row, preset)
    row.drawn = RowState(preset)

    row.selected:SetShown(selection ~= nil and selection:IsElementDataSelected(preset))
end

--------------------------------------------------------------------------------
-- Os campos do editor
--------------------------------------------------------------------------------
--- A label + combo in a CONTAINER. Hiding the group hides both -- it is what keeps the orphan
--- label from coming back in the next field someone adds.
---
--- The label sits by its bottom on the combo's top, +3: so it does not depend on the font's size.
---
--- `emptyText` is what the field shows when nothing is picked and `clearText` the menu entry that
--- clears it (both "(none)" by default). An optional field can show nothing and name the clear
--- entry by what the preset then does (21/10, Appearance).
local function Group(parent, labelText, yTop, items, get, set, emptyText, clearText)
    emptyText = emptyText or L["(none)"]
    clearText = clearText or L["(none)"]
    local group = CreateFrame("Frame", nil, parent)
    group:SetSize(FIELD_W + 16, 40)
    group:SetPoint("TOPLEFT", parent, "TOPLEFT", COL_X, yTop)

    -- +8 compensa o transbordo da arte do combo, para ela cair exatamente na coluna.
    local dd = CreateFrame("DropdownButton", nil, group, "WowStyle1DropdownTemplate")
    dd:SetSize(FIELD_W, 25)
    dd:SetPoint("BOTTOMLEFT", group, "BOTTOMLEFT", 8, 0)

    local label = group:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    label:SetPoint("BOTTOMLEFT", dd, "TOPLEFT", 3, 3)
    label:SetJustifyH("LEFT")
    label:SetText(labelText)

    --- Rebuilds the menu from the current state.
    ---
    --- `SetDefaultText` is only for "nothing selected" -- the mark of the chosen item comes free
    --- from `CreateRadio`'s `IsSelected`. The version before used the default as the "selected's
    --- text", which is what Blizzard's own comment advises against.
    function group.Sync()
        local list = items()

        -- The name typed goes to the preset BEFORE the choice: the box only saves when it loses
        -- the focus, and a click on a field does not take the focus from it.
        dd:SetupMenu(function(_, root)
            root:CreateButton(clearText, function() UI.SaveName(); set(nil); UI.AfterEdit() end)
            if #list > 0 then root:CreateDivider() end

            for _, item in ipairs(list) do
                local entry = root:CreateRadio(item.text,
                    function() return get() == item.value end,
                    function() UI.SaveName(); set(item.value); UI.AfterEdit() end,
                    item.value)

                -- The equipment set already has an icon; showing it in the menu costs five lines and
                -- is what makes choosing "Frost" possible without reading.
                if item.icon and entry.AddInitializer then
                    entry:AddInitializer(function(button)
                        local tex = button:AttachTexture()
                        tex:SetSize(19, 19)
                        tex:SetPoint("LEFT")
                        tex:SetTexture(item.icon)
                        if button.fontString then
                            button.fontString:SetPoint("LEFT", tex, "RIGHT", 3, 0)
                        end
                    end)
                end
            end

            -- With nothing to choose, the combo stays dimmed instead of opening a menu of one
            -- item only -- the real case of a spec with no saved loadout.
            -- LOCKED stays off: the game runs this again on every show and every opening
            -- (`DropdownButton.lua:117,246`, 12.1.0). Off, its dropdown does not open (`:109`).
            if root.HasElements then dd:SetEnabled(group.locked == nil and root:HasElements()) end
        end)

        local current, text = get(), nil
        for _, item in ipairs(list) do
            if item.value == current then text = item.text end
        end
        dd:SetDefaultText(text or emptyText)
    end

    ---Turns the field off with a reason, or back on with `nil`. The reason is what the tooltip
    ---says: a field that is off and does not say why is just a broken field.
    function group.SetLocked(reason)
        if group.locked == reason then return end
        group.locked = reason
        if reason then
            dd:SetEnabled(false)
        else
            dd:SetEnabled(true)
            if group:IsShown() then group.Sync() end
        end
    end
    dd:SetMotionScriptsWhileDisabled(true)
    dd:HookScript("OnEnter", function(self)
        if not group.locked then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip_SetTitle(GameTooltip, labelText)
        GameTooltip_AddErrorLine(GameTooltip, group.locked)
        GameTooltip:Show()
    end)
    dd:HookScript("OnLeave", function() if group.locked then GameTooltip:Hide() end end)

    group.dropdown = dd
    return group
end

local function BuildEditor()
    editor = {}

    -- TWO BUTTONS TO THE GAME'S WINDOWS (27/09), at the top of the column. The user first asked for
    -- *"algum botão para ir para o gerenciador de equipamentos e para os talentos"*; a small text
    -- link over each field came first, and the user preferred *"dois botões mesmo acima de onde
    -- coloca o nome"*. They open the places where a loadout and a gear set are MADE -- the fields
    -- below only pick one.
    local function Tool(text, tooltip, fn, x)
        local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        b:SetSize(TOOL_W, 22)
        b:SetPoint("TOPLEFT", frame, "TOPLEFT", x, EDITOR_TOP)
        b:SetText(text)
        b:SetScript("OnClick", fn)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(text, 1, 1, 1)
            GameTooltip:AddLine(tooltip, 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return b
    end
    editor.openTalents = Tool(L["Talents"], L["Opens the game's talent window, to create or edit a loadout."],
        function() UI.OpenTalents() end, COL_X + 5)
    editor.openGear = Tool(L["Equipment"], L["Opens the character sheet on the equipment manager, to create or save a set."],
        function() ns.Data.OpenEquipmentManager() end, COL_X + 5 + TOOL_W + 7)

    -- THE NAME HAS A TITLE (27/09). It used to live only inside the box as the instruction text,
    -- and the user: *"falta ter um titulo ali, pro usuário saber que é o nome do preset que tá
    -- salvando"* -- once typed, the instruction is gone and nothing says what the box is. The word
    -- is the one the list, "+ New preset" and every message already use ("conjunto" in ptBR), so
    -- the player never meets two names for the same thing. Placed like a `Group` label.
    editor.nameTitle = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    editor.nameTitle:SetPoint("TOPLEFT", frame, "TOPLEFT", COL_X + 11, NAME_TITLE_Y)
    editor.nameTitle:SetWidth(NAME_W - 6)
    editor.nameTitle:SetJustifyH("LEFT")
    -- One line, always: with "(required)" after it the title is 184 wide in Portuguese, of the
    -- 205 it has (measured with the game's font at the 12 of `GameFontNormal`). A longer
    -- translation is cut instead of falling over the box.
    editor.nameTitle:SetWordWrap(false)
    editor.nameTitle:SetText(L["Preset name"])

    editor.name = CreateFrame("EditBox", nil, frame, "InputBoxInstructionsTemplate")
    editor.name:SetSize(NAME_W, 22)
    editor.name:SetPoint("TOPLEFT", frame, "TOPLEFT", COL_X + 5, NAME_Y)
    editor.name:SetAutoFocus(false)
    editor.name:SetMaxLetters(31)
    if editor.name.Instructions then
        -- Without this the instruction text is born 16px to the right of the typed text.
        editor.name.Instructions:SetAllPoints()
        -- With a title above, repeating it inside the box says nothing: show an example instead.
        editor.name.Instructions:SetText(L["e.g. Raid, M+, Arena"])
    end
    editor.name:SetScript("OnEscapePressed", editor.name.ClearFocus)
    editor.name:SetScript("OnEnterPressed", editor.name.ClearFocus)
    -- Leaving the box saves. The "Salvar" button went away: the combos already write straight to the
    -- set, so it only confirmed the name -- and its existence raised the doubt "did the
    -- combo's choice save?".
    editor.name:SetScript("OnEditFocusLost", function() UI.SaveName() end)
    -- (!) THE NAME IS REQUIRED (30/09), and the column says so AS IT IS TYPED: with the box empty
    -- the title carries "(required)" in the game's red and the four fields below are off; the
    -- first letter turns them on. `HookScript`, not `SetScript`: the template has its own
    -- OnTextChanged, the one that hides the example text.
    editor.name:HookScript("OnTextChanged", function() UI.RefreshNameState() end)

    editor.divider = frame:CreateTexture(nil, "ARTWORK")
    editor.divider:SetSize(FIELD_W + 16, 1)
    editor.divider:SetPoint("TOPLEFT", frame, "TOPLEFT", COL_X, DIVIDER_Y)
    if not ns.SetAtlasSafe or not ns.SetAtlasSafe(editor.divider, "Options_HorizontalDivider") then
        editor.divider:SetColorTexture(1, 1, 1, 0.12)
    end

    local function Current() return UI.Selected() end

    editor.spec = Group(frame, L["Specialization"], FIELDS_Y,
        function()
            local out = {}
            for _, s in ipairs(ns.Data.GetSpecs()) do
                out[#out + 1] = { value = s.index, text = s.name, icon = s.icon }
            end
            return out
        end,
        function() local p = Current(); return p and p.spec end,
        -- Switching the spec clears the loadout: a Frost loadout does not exist in Unholy, and
        -- offering it would be offering the impossible.
        function(v) local p = Current(); if p then p.spec = v; p.talent = nil end end)

    editor.talent = Group(frame, L["Talents"], FIELDS_Y - GROUP_STEP,
        function()
            local p = Current()
            local spec = p and ns.Data.GetSpecByIndex(p.spec)
            local out = {}
            for _, l in ipairs(ns.Data.GetLoadouts(spec and spec.id)) do
                out[#out + 1] = { value = l.configID, text = l.name }
            end
            return out
        end,
        function() local p = Current(); return p and p.talent end,
        function(v) local p = Current(); if p then p.talent = v end end)

    editor.gear = Group(frame, L["Gear"], FIELDS_Y - GROUP_STEP * 2,
        function()
            local out = {}
            for _, s in ipairs(ns.Data.GetGearSets()) do
                out[#out + 1] = { value = s.setID, text = s.name, icon = s.icon }
            end
            return out
        end,
        function() local p = Current(); return p and p.gear end,
        function(v) local p = Current(); if p then p.gear = v end end)

    -- Appearance is OPTIONAL on purpose: empty, the set does not touch the outfit. Whoever does not use
    -- transmog does not even notice the field exists.
    -- (21/10) EMPTY, THE FIELD IS BLANK. The user: *"quando não é selecionado a aparência fica
    -- (none), tem que melhorar o texto"*, then *"ou deixa vazio mesmo"* -- "(nenhum)" read as "no
    -- appearance", and in Portuguese it did not even agree with "Aparência". The menu entry that
    -- clears it still needs words, and says what the preset then does: "Keep current".
    editor.transmog = Group(frame, L["Appearance"], FIELDS_Y - GROUP_STEP * 3,
        function()
            local out = {}
            for _, o in ipairs(ns.Data.GetOutfits()) do
                out[#out + 1] = { value = o.outfitID, text = o.name, icon = o.icon }
            end
            return out
        end,
        function() local p = Current(); return p and p.transmog end,
        function(v) local p = Current(); if p then p.transmog = v end end,
        "", L["Keep current"])

end

---DRAG A PRESET TO THE ACTION BAR (26/09). The user: *"ao invés do botão, seria possível arrastar o
---icone dele para a barra?"* -- the preset's card is dragged like a spell from the spellbook: its
---macro goes to the cursor (`PickupMacro`, made or remade first) and the player drops it on the
---slot they want. The click on the card still selects it: a drag only starts when the mouse moves.
---The game's talent window on the talent tab (`PlayerSpellsUtil.lua:31`, Blizzard_FrameXMLUtil;
---it loads the window on demand).
function UI.OpenTalents()
    if PlayerSpellsUtil and PlayerSpellsUtil.OpenToClassTalentsTab then
        pcall(PlayerSpellsUtil.OpenToClassTalentsTab)
    elseif ToggleTalentFrame then
        pcall(ToggleTalentFrame)
    end
end

function UI.DragPreset(preset)
    if not preset then return end
    local ok, why
    ns.Macro.WithoutAutoPlace(function() ok, why = ns.Macro.PickUp(preset) end)
    if ok then
        UI.SetStatus(L["Drop the macro on an action bar slot."], false)
    elseif why == "noname" then
        UI.SetStatus(L["Give the preset a name first."], true)
    elseif why == "combat" then
        UI.SetStatus(L["in combat: will apply when the fight ends."], true)
    else
        UI.SetStatus(L["Could not make the macro (this character's macros may be full)."], true)
    end
end

--------------------------------------------------------------------------------
-- O progresso da troca
--------------------------------------------------------------------------------
-- WHY THIS EXISTS. The report was: *"quando clica para carregar, ele demora para iniciar o
-- 'cast', o usuário vai pensar que nada aconteceu"* -- and the request with it, *"algo animado e bem
-- didático que o usuário entenda"* that the swap *"é um processo de troca por etapas"*.
--
-- **And it is not a progress bar.** The chain does not know how long it will take: the
-- specialization step waits for the server and insists every 4 seconds, and the real log showed the
-- same swap accepted in 4 seconds one time and 14 another. A bar that moves by itself invents a
-- forecast nobody has, and a bar stuck halfway is worse than no bar. What can be shown
-- honestly -- and it is what the person wants to know -- are four things true at every
-- frame: **what the stages are**, **which one we are in**, **which have closed** and **for how
-- long**. The first three come from `Data.GetProgress()`; the fourth is a clock.
--
-- WHERE: in the right column, in the editor's place. During the swap the editor is not usable -- changing
-- the set being applied is moving the floor mid-step --, so the space is
-- free. And it is where the set's fields already live: the labels here are **the same** as the editor's
-- (`Especialização`, `Talentos`, `Itens`, `Aparência`) and **in the same order**. Whoever just read
-- those names beside the combos recognises the list with no legend needed -- that is what makes
-- the screen teach, and not a text explaining what it is.
--
-- And **only the stages the set asks for** go in (`Data.GetProgress` filters): an items-only
-- set shows one line, not four, three of which would say "nothing to change".

local PROGRESS_ROW = 22       -- ritmo de LISTA (`Blizzard_CategoryList.xml:51` + `.lua:214`)
local PROGRESS_ICON = 16      -- o tamanho do ✓ nativo (`Blizzard_UIWidgetTemplateBase.xml:185`)
local PROGRESS_ICON_GAP = 5   -- icon -> small label (`Blizzard_AutoCompletePopupList.xml:32`,
                              -- which is icon + `GameFontHighlightSmall`, the same pair as here)
local PROGRESS_TITLE_GAP = 13 -- below the title, as in a section header: block 45, title at
                              -- y=-16 e 16 de tinta ⇒ 45 − 16 − 16 (`Blizzard_SettingControls.xml:14,19`)
local PROGRESS_TITLE_INK = 16 -- `GameFontNormal` a 14pt, arredondado pela caixa da fonte
local PROGRESS_CLOCK_W = 70

-- HOW LONG THE RESULT STAYS ON SCREEN after the swap ends. Without this pause the panel goes away
-- the instant it finally has something to say -- which step was skipped, which failed -- and the
-- player would be left only with the status line down below, which is exactly the warning that
-- *"mostra e some, o usuário pode nem ver"*.
local PROGRESS_HOLD = 5

-- One signal per state, and none of them made up: the three atlases were checked in the
-- 12.1.0 source (`common-icon-checkmark` in 7 files, `common-icon-redx` in 3, `common-icon-forwardarrow`
-- in 3). The workspace's skill is explicit about the rest: a class colour is reserved vocabulary,
-- so emphasis comes from adding **weak signals** -- here, art + brightness + the pulse.
--
-- `skipped` IS NOT A FAILURE and must not look like one: no ✗, no red. It gets the same
-- neutral dot as one that has not started yet, plus the reason written in the label itself.
-- Exported in `ns.ProgressVisuals` right below: the floating panel (`Progress.lua`) draws
-- the SAME states, and two art tables would drift apart at the first change.
local PROGRESS_STATE = {
    pending = {                                     alpha = 0.40 },
    doing   = { atlas = "common-icon-forwardarrow", alpha = 1.00 },
    done    = { atlas = "common-icon-checkmark",    alpha = 0.85 },
    skipped = {                                     alpha = 0.45 },
    failed  = { atlas = "common-icon-redx",         alpha = 0.90 },
}

-- The floating panel (`Progress.lua`) draws the SAME states. Two art tables
-- would drift apart at the first change, so there is only one and it lives here.
ns.ProgressVisuals = PROGRESS_STATE
ns.PROGRESS_ROW = PROGRESS_ROW
ns.PROGRESS_ICON = PROGRESS_ICON
ns.PROGRESS_ICON_GAP = PROGRESS_ICON_GAP

---Fecha o painel e devolve a coluna ao editor.
local function ConcludeProgress(panel)
    if not panel:IsShown() then return end
    panel:Hide()
    for _, row in ipairs(panel.rows) do
        if row.__pulsing then
            row.pulse:Stop()
            row:SetAlpha(1)
            row.__pulsing = false
        end
    end
    UI.RefreshEditor()
end

--- Builds the panel once; `UI.RefreshProgress` is what writes on it.
local function BuildProgress()
    local panel = CreateFrame("Frame", nil, frame)
    panel:SetPoint("TOPLEFT", frame, "TOPLEFT", COL_X, -60)
    panel:SetPoint("RIGHT", frame, "RIGHT", -20, 0)
    panel:Hide()

    -- The clock to the right of the title. It is what answers *"did anything happen?"* before
    -- any step closes: a number moving second by second proves the addon is
    -- alive, even in the 4 seconds when it is waiting on purpose for the game to allow it.
    panel.clock = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    panel.clock:SetPoint("TOPRIGHT", 0, 0)
    panel.clock:SetWidth(PROGRESS_CLOCK_W)
    panel.clock:SetJustifyH("RIGHT")
    panel.clock:SetWordWrap(false)

    panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    panel.title:SetPoint("TOPLEFT", 0, 0)
    panel.title:SetPoint("RIGHT", panel.clock, "LEFT", -PROGRESS_ICON_GAP, 0)
    panel.title:SetJustifyH("LEFT")
    panel.title:SetWordWrap(false)

    panel.rows = {}
    for i = 1, 4 do
        local row = CreateFrame("Frame", nil, panel)
        row:SetHeight(PROGRESS_ROW)
        if i == 1 then
            row:SetPoint("TOPLEFT", panel.title, "BOTTOMLEFT", 0, -PROGRESS_TITLE_GAP)
        else
            row:SetPoint("TOPLEFT", panel.rows[i - 1], "BOTTOMLEFT", 0, 0)
        end
        row:SetPoint("RIGHT", panel, "RIGHT", 0, 0)

        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(PROGRESS_ICON, PROGRESS_ICON)
        row.icon:SetPoint("LEFT", 0, 0)

        -- THE WAITING DOT. In the states with no art (its turn has not come, and the skipped) the icon's
        -- column cannot stay empty: a hole in the middle of a list makes it look broken, and
        -- the label loses the margin the other three have. A neutral dot holds the column, and it
        -- vanishes under the ✓ or the ✗ when they come in.
        row.dot = row:CreateTexture(nil, "ARTWORK")
        row.dot:SetSize(4, 4)
        row.dot:SetPoint("CENTER", row.icon, "CENTER", 0, 0)
        row.dot:SetColorTexture(1, 1, 1, 1)

        -- Width by anchoring on both sides, and not by a guessed `SetWidth`: the label has to
        -- fit in German and Russian, where it grows by itself.
        row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.label:SetPoint("LEFT", row.icon, "RIGHT", PROGRESS_ICON_GAP, 0)
        row.label:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        row.label:SetJustifyH("LEFT")
        row.label:SetWordWrap(false)

        -- THE PULSE, and it is the screen's only animation. It is for the "indeterminate" case: nobody
        -- knows how much is left, so what is animated is the step's presence, not a progress.
        -- Alpha and not rotation -- a pulse competes with nothing for attention, and needs no new art.
        row.pulse = row:CreateAnimationGroup()
        row.pulse:SetLooping("BOUNCE")
        local fade = row.pulse:CreateAnimation("Alpha")
        fade:SetFromAlpha(1)
        fade:SetToAlpha(0.4)
        fade:SetDuration(0.7)

        panel.rows[i] = row
    end

    panel:SetHeight(PROGRESS_ROW * 4 + PROGRESS_TITLE_GAP + PROGRESS_TITLE_INK)
    frame.progress = panel
end

--- Redraws the progress. It runs in the window's `OnUpdate`, throttled -- the clock is in whole
--- seconds, so ten frames a second is plenty.
function UI.RefreshProgress()
    if not frame or not frame.progress then return end
    local panel = frame.progress

    local passos, info = ns.Data.GetProgress()
    if not passos then
        ConcludeProgress(panel)     -- there was never a swap in this session
        return
    end

    -- THE TWO TRANSITIONS. `info.live` says whether the swap is happening NOW; `panel.live` is what
    -- the window saw last time. The difference between the two is what marks start and end -- and it is
    -- the end that needs the pause, so the result is read before the editor comes back.
    if info.live and not panel.live then
        panel.live, panel.holdUntil = true, nil
    elseif not info.live and panel.live then
        panel.live, panel.holdUntil = false, GetTime() + PROGRESS_HOLD
    end

    -- The picture of a swap that already ended and was already shown (or that happened with the window
    -- closed): it does not open the panel. Progress is about now.
    if not info.live and (not panel.holdUntil or GetTime() >= panel.holdUntil) then
        panel.holdUntil = nil
        ConcludeProgress(panel)
        return
    end

    if not panel:IsShown() then
        panel:Show()
        UI.RefreshEditor()          -- a coluna passa a ser do progresso
    end

    -- THE HEIGHT FOLLOWS HOW MANY STAGES THE SET ASKS FOR. Reserving the four slots always leaves
    -- a gap under the panel of an items-only set -- and space kept for content
    -- that does not exist is what most makes a window look broken.
    panel:SetHeight(PROGRESS_ROW * #passos + PROGRESS_TITLE_GAP + PROGRESS_TITLE_INK)

    panel.title:SetText(format(L["Switching to %s"],
        info.preset and info.preset.name or "?"))

    -- ONLY THE SECONDS, and nothing about attempts.
    --
    -- An earlier version swapped the clock for "attempt 2 of 8" while the game refused the
    -- spec switch. The user asked to take it out, and he is right: the number of attempts is the
    -- addon's internal mechanics -- the player decides nothing with it, cannot speed it up nor
    -- interrupt it, and seeing a counter go up suggests a problem where there is only a normal wait. What
    -- he needs to know is that **something is happening**, and the clock alone already handles that.
    --
    -- The insisting is still recorded where it serves: in the log (`/rs log`).
    --
    -- And it STOPS when the swap stops -- leaving it running during the pause would make the number count the
    -- reading time as if it were swap time.
    if info.live then
        local secs = math.max(0, math.floor(GetTime() - (info.startedAt or 0)))
        panel.clock:SetText(secs .. "s")
    end

    for i, row in ipairs(panel.rows) do
        local passo = passos[i]
        row:SetShown(passo ~= nil)
        if passo then
            local visual = PROGRESS_STATE[passo.state] or PROGRESS_STATE.pending
            local temArte = visual.atlas and ns.SetAtlasSafe(row.icon, visual.atlas) or false

            row.icon:SetShown(temArte)
            row.icon:SetAlpha(visual.alpha)
            row.dot:SetShown(not temArte)
            row.dot:SetVertexColor(1, 1, 1, visual.alpha)

            -- THE SKIPPED ONE SAYS WHY IT WAS SKIPPED, in the label itself. Without that it looks like a
            -- step that has not started yet, and the player ends the swap not knowing whether the appearance
            -- was applied or forgotten.
            row.label:SetText(passo.state == "skipped"
                and format(L["%s — nothing to change"], passo.label)
                or passo.label)
            row.label:SetAlpha(visual.alpha)

            -- The pulse follows the step under way, and only while the swap is alive: it is
            -- re-anchored instead of re-created, because an animation started again at every frame does not
            -- animate anything -- it blinks.
            local deve = passo.state == "doing" and info.live
            if deve and not row.__pulsing then
                row.pulse:Play()
                row.__pulsing = true
            elseif not deve and row.__pulsing then
                row.pulse:Stop()
                row:SetAlpha(1)
                row.__pulsing = false
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Estado vazio
--------------------------------------------------------------------------------
--- A centred block. Blizzard has no empty screen with art: in ~20 systems the pattern is
--- a centred FontString plus, when there is something to do, a button.
---
--- The text answers the question the button raises ("will I have to fill everything?"), instead of
--- describing the product. And the answer is true in the code: `UI.New` is already born filled.
local function BuildEmptyState()
    local empty = CreateFrame("Frame", nil, frame)
    empty:SetAllPoints()

    empty.title = empty:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    empty.title:SetPoint("CENTER", frame, "CENTER", 0, 55)
    empty.title:SetText(L["No presets yet"])

    empty.body = empty:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    empty.body:SetPoint("TOP", empty.title, "BOTTOM", 0, -10)
    empty.body:SetWidth(320)
    empty.body:SetJustifyH("CENTER")
    empty.body:SetText(L["The first one starts with the spec, talents and gear you have right now."])

    empty.button = CreateFrame("Button", nil, empty, "UIPanelButtonTemplate")
    empty.button:SetSize(180, 22)
    empty.button:SetPoint("TOP", empty.body, "BOTTOM", 0, -20)
    empty.button:SetText(L["Create the first preset"])
    empty.button:SetScript("OnClick", function() UI.New() end)

    frame.emptyState = empty
end

--------------------------------------------------------------------------------
--- The "Avisos" section, in the footer and full width.
---
--- It is ALWAYS visible -- including with zero sets, the case that started it. The two
--- warnings are what the addon does for whoever will never make a set; leaving them only in
--- `/rs warn` and `/rs ready` is the same as not having them, because nobody discovers a command.
---
--- On by default, and so the label is affirmative: the ticked box describes what is already
--- happening, not a promise.
local function BuildToggles()
    local strip = CreateFrame("Frame", nil, frame)
    strip:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, WARN_STRIP_Y)
    strip:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -14, WARN_STRIP_Y)
    -- 142 = the last box ends at −136, plus 6 of breathing room. It was 86 with two boxes, 118 with
    -- the War Mode sub-option (12/09) and 142 with the queue invite's (18/09). A fixed height that
    -- does not follow the content is the defect an overflowing strip would have produced silently.
    -- The strip shrank from 142 to 106 when the four boxes became two columns of two:
    -- title (-10, 16 of ink) + column title (-34, 14) + two boxes of 24 from
    -- -52 => the last ends at -100, plus 6 of breathing room. The number lives in `WARN_STRIP_H`,
    -- because the window's height comes from it.
    strip:SetHeight(WARN_STRIP_H)

    strip.divider = strip:CreateTexture(nil, "ARTWORK")
    strip.divider:SetPoint("TOPLEFT", 0, 0)
    strip.divider:SetPoint("TOPRIGHT", 0, 0)
    strip.divider:SetHeight(1)
    if not ns.SetAtlasSafe or not ns.SetAtlasSafe(strip.divider, "Options_HorizontalDivider") then
        strip.divider:SetColorTexture(1, 1, 1, 0.12)
    end

    strip.title = strip:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    strip.title:SetPoint("TOPLEFT", 0, -10)
    strip.title:SetText(L["Warnings"])
    strip.title:SetTextColor(1, 0.82, 0)

    -- The "?" beside the title, and not on each box: what needs explaining is the FEATURE
    -- (that the warnings work without a set, and when they stay quiet), not each line alone.
    --
    -- `Interface\common\help-i` is the art Blizzard uses in the HelpPlate
    -- (`Blizzard_HelpPlate.xml:382`). A texture path fails SILENTLY, so it goes
    -- through `ns.FirstIcon`, which asks `GetFileIDFromPath` -- and the last resort is drawing a
    -- text "?", which cannot fail to show.
    local help = CreateFrame("Button", nil, strip)
    help:SetSize(18, 18)
    help:SetPoint("LEFT", strip.title, "RIGHT", 6, 0)

    local art, verified = ns.FirstIcon({ "Interface\\common\\help-i" })
    if verified then
        help.icon = help:CreateTexture(nil, "ARTWORK")
        help.icon:SetAllPoints()
        help.icon:SetTexture(art)
    else
        help.label = help:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        help.label:SetAllPoints()
        help.label:SetText("?")
        help.label:SetTextColor(1, 0.82, 0)
    end
    help:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight")

    help:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["Warnings"], 1, 1, 1)
        GameTooltip:AddLine(L["These two work without any preset — they are what the addon does on the day you install it."],
            0.8, 0.8, 0.8, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["Wrong gear:"], 1, 0.82, 0)
        GameTooltip:AddLine(L["In an arena or battleground it flags every slot WITHOUT the PvP item level line; in a dungeon or raid, every slot WITH it. It names the slots, and offers to load a preset if you have one that fits."],
            0.8, 0.8, 0.8, true)
        GameTooltip:AddLine(L["In the open world with War Mode on it stays quiet unless you tick the second box: out there most of the time is questing, not fighting players."],
            0.8, 0.8, 0.8, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["Ready check:"], 1, 0.82, 0)
        GameTooltip:AddLine(L["When the leader starts one, it prints your specialization, talent loadout and gear set — so you can confirm before the pull."],
            0.8, 0.8, 0.8, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["PvP queue pop:"], 1, 0.82, 0)
        GameTooltip:AddLine(L["When the arena or battleground invite shows up, it prints the same summary — the last moment when you can still fix the build."],
            0.8, 0.8, 0.8, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["It stays quiet in combat, once the gates are open, and whenever the reading is not reliable. Type /rs gear to see what it reads on each slot."],
            0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end)
    help:SetScript("OnLeave", GameTooltip_Hide)

    --- A box with its own label. `UICheckButtonTemplate` has a built-in `.text`, but it
    --- depends on the frame having a name -- and a named frame becomes a global. Our own FontString avoids
    --- both.
    local function Toggle(y, label, key, indent)
        local box = CreateFrame("CheckButton", nil, strip, "UICheckButtonTemplate")
        box:SetSize(24, 24)
        box:SetPoint("TOPLEFT", indent or 0, y)

        local text = strip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        text:SetPoint("LEFT", box, "RIGHT", 2, 0)
        text:SetText(label)

        box:SetScript("OnClick", function(self)
            ns.db[key] = self:GetChecked() and true or false
            if UI.RefreshToggles then UI.RefreshToggles() end
        end)

        -- THE TOOLTIP SAYS WHY IT IS DIMMED. Without it the grey box is just a broken box.
        box:SetScript("OnEnter", function(self)
            if self:IsEnabled() then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(label, 1, 1, 1)
            GameTooltip:AddLine(L["Turn on the wrong gear warning first."], 1, 0.5, 0.4, true)
            GameTooltip:Show()
        end)
        box:SetScript("OnLeave", GameTooltip_Hide)

        box.key = key
        box.label = text
        return box
    end

    -- (!) TWO COLUMNS, AND THE TITLES TELL THE TRUTH ABOUT WHAT EACH ONE IS (22/09).
    --
    -- The request was *"de um lado avisos de PVE e do outro lado avisos de PVP"*. Checking in
    -- `Alert.lua` what each box does, the PvE/PvP split does not exist:
    --
    --   `warn`        fires in BOTH contexts (PvP gear in a dungeon, and the reverse)
    --   `readyCheck`  holds in any group
    --   `warnWarMode` extends the one above to the open world with War Mode -- PvP
    --   `queuePop`    only battleground and arena -- PvP
    --
    -- That is: two are universal, two are PvP, and **none is PvE only**. A "PvE" column
    -- would be born empty or lying, and a label that lies is worse than no column. So the titles
    -- are the ones the code holds up, and the request's intent -- seeing at a glance what is specific
    -- to PvP -- is met just the same.
    local COL2 = math.floor((WIDTH - 28) / 2)

    local function ColumnTitle(x, texto)
        local fs = strip:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("TOPLEFT", x, -34)
        fs:SetText(texto)
        fs:SetTextColor(0.75, 0.75, 0.78)
        return fs
    end

    strip.colPvE = ColumnTitle(0, L["PvE"])
    strip.colPvP = ColumnTitle(COL2, L["PvP"])

    -- THE TWO COLUMNS ARE REAL SINCE 0.35.0. Before, the equipment warning was a single key for
    -- both contents, so the titles had to be "In any content" and "Only in PvP" --
    -- honest, but not what the user wanted. With the key split per context, PvE and PvP
    -- become real columns, each with its own equipment warning.
    strip.warnPvE = Toggle(-52, L["Warn about wrong gear"], "warnPvE")
    strip.ready = Toggle(-76, L["Show my setup on Ready Check"], "readyCheck")

    strip.warnPvP = Toggle(-52, L["Warn about wrong gear"], "warnPvP", COL2)
    -- (!) THE SUB-OPTION IS A CHILD AGAIN, and now with its parent in the SAME column: War Mode is the
    -- open world with PvP on, so it belongs to this column and this warning. The 15 px
    -- indent says the dependency again, and the dimmed state still says it too -- the two
    -- signals added, which is what this project's skill says to do.
    strip.warMode = Toggle(-76, L["Warn with War Mode on too"], "warnWarMode", COL2 + CHILD_INDENT)
    strip.queue = Toggle(-100, L["Show my setup when a PvP queue pops"], "queuePop", COL2)

    frame.toggles = strip
end

--- Sets the boxes' state: ticked/unticked and, for the child, dimmed or not.
---
--- (!) THE DEPENDENCY STOPPED BEING A DRAWING AND BECAME BEHAVIOUR. While the two lived in the
--- same stack, the 15 px indent said "this one depends on the one above". In different columns the indent
--- says nothing any more, so the state says it: with the equipment warning off, the War Mode
--- one stays dimmed, and the tooltip explains.
function UI.RefreshToggles()
    local strip = frame and frame.toggles
    if not strip then return end

    strip.warnPvE:SetChecked(ns.db.warnPvE ~= false)
    strip.warnPvP:SetChecked(ns.db.warnPvP ~= false)
    strip.ready:SetChecked(ns.db.readyCheck ~= false)
    strip.queue:SetChecked(ns.db.queuePop ~= false)

    -- `== true`, and not `~= false`: this one is born UNTICKED, so the absence of a value is "no".
    -- Copying the neighbours' `~= false` would leave it ticked for whoever never saw it -- the opposite of
    -- what was asked on 12/09.
    strip.warMode:SetChecked(ns.db.warnWarMode == true)

    -- The child depends on the PvP warning, which is its parent now (War Mode is the world with PvP).
    local ligado = ns.db.warnPvP ~= false
    if strip.warMode then
        strip.warMode:SetEnabled(ligado)
        if strip.warMode.label then
            strip.warMode.label:SetTextColor(ligado and 1 or 0.5, ligado and 1 or 0.5,
                ligado and 1 or 0.5)
        end
    end
end

local function Create()
    if frame then return frame end

    -- Template inheritance only at creation.
    frame = CreateFrame("Frame", ADDON .. "Frame", UIParent, "ButtonFrameTemplate")
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("HIGH")
    -- IN FRONT WHEN OPENED OR CLICKED (27/09). Every Rocket window shares the HIGH strata, and
    -- inside a strata the order is the frame LEVEL: without this, the rows of a window opened
    -- earlier (deeper children, higher levels) drew over the background of the one opened on
    -- top -- the user's print had RocketMount's list showing through RocketSwap. `toplevel`
    -- raises on click; `Raise` on show.
    frame:SetToplevel(true)
    frame:HookScript("OnShow", function(self) self:Raise() end)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        ns.db.pos = { point = point, relPoint = relPoint, x = x, y = y }
    end)
    frame:Hide()

    if frame.SetTitle then frame:SetTitle(ns.NAME) end
    if frame.SetPortraitToAsset then
        frame:SetPortraitToAsset(ns.LOGO)
    end
    tinsert(UISpecialFrames, frame:GetName())
    ns.DarkBody(frame, 1, frame.Bg)                    -- (25/10) the dark body, as every Rocket window (Core.lua); the list keeps the inset

    -- The template's inset covers the whole width; here it comes to cover only the list's column.
    -- The right column sits on the window's background on purpose: the inset's marble is a LIST's
    -- background, and under a form it competes with the combos' art.
    if frame.Inset then
        frame.Inset:ClearAllPoints()
        frame.Inset:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, LIST_TOP)
        frame.Inset:SetPoint("BOTTOMRIGHT", frame, "TOPLEFT", 4 + LIST_W, LIST_BOTTOM)
    end
    local host = frame.Inset or frame

    -- No "Conjuntos" label: the inset already bounds the list, and it was exactly that label that
    -- sat under the portrait.
    frame.list = CreateFrame("Frame", nil, host, "WowScrollBoxList")
    frame.listBar = CreateFrame("EventFrame", nil, host, "MinimalScrollBar")
    frame.listBar:SetPoint("TOPRIGHT", host, "TOPRIGHT", -3, -3)
    frame.listBar:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -3, 3)

    local view = CreateScrollBoxListLinearView(0, 0, 0, 0, ROW_SPACING)
    view:SetVirtualized(false)          -- 2 to 5 items: creates them all, does not recycle
    -- HEIGHT PER ELEMENT, and not one for all: each card measures what its fields ask for.
    view:SetElementExtentCalculator(function(_, preset)
        return CardHeight(preset)
    end)
    view:SetElementInitializer("Button", FillRow)
    ScrollUtil.InitScrollBoxListWithScrollBar(frame.list, frame.listBar, view)

    ScrollUtil.AddManagedScrollBarVisibilityBehavior(frame.list, frame.listBar,
        { CreateAnchor("TOPLEFT", host, "TOPLEFT", 3, -3),
          CreateAnchor("BOTTOMRIGHT", host, "BOTTOMRIGHT", -17, 3) },
        { CreateAnchor("TOPLEFT", host, "TOPLEFT", 3, -3),
          CreateAnchor("BOTTOMRIGHT", host, "BOTTOMRIGHT", -3, 3) })

    -- The selection keeps the set's TABLE, not the index. With the index, `table.remove` in
    -- Delete shifted everything and the selection came to point at another set.
    selection = ScrollUtil.AddSelectionBehavior(frame.list)
    selection:RegisterCallback(SelectionBehaviorMixin.Event.OnSelectionChanged,
        function(_, elementData, isSelected)
            local row = frame.list:FindFrame(elementData)
            if row and row.selected then row.selected:SetShown(isSelected) end
            if isSelected then
                current = elementData
                UI.RefreshEditor()
            elseif current == elementData then
                current = nil
            end
        end, UI)

    -- The attic: the band between the title and the inset, to the right of the portrait (x ≥ 58).
    frame.new = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.new:SetSize(140, 22)
    frame.new:SetPoint("TOPLEFT", frame, "TOPLEFT", 60, ATTIC_Y)
    frame.new:SetText("+ " .. L["New preset"])
    frame.new:SetScript("OnClick", function() UI.New() end)

    -- (25/10) the Rocket SBA Lab's builds as presets: shown only when the game has a pair of its talents and items
    frame.fromLab = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.fromLab:SetSize(160, 22)
    frame.fromLab:SetText(L["From Rocket SBA Lab"])
    frame.fromLab:SetScript("OnClick", function() UI.FromRocketLab() end)
    frame.fromLab:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
        GameTooltip_SetTitle(GameTooltip, L["From Rocket SBA Lab"])
        GameTooltip_AddNormalLine(GameTooltip, L["Rocket SBA Lab saves each build's talents and items in the game, under the build's name. This joins the two of each one into a preset here."], true)
        GameTooltip_AddBlankLineToTooltip(GameTooltip)
        for _, p in ipairs(ns.Data.RocketPairs()) do
            GameTooltip_AddHighlightLine(GameTooltip, p.name .. ": " .. p.loadoutName .. " + " .. p.setName)
        end
        GameTooltip_AddBlankLineToTooltip(GameTooltip)
        GameTooltip_AddInstructionLine(GameTooltip, L["Click: create or update the presets"])
        GameTooltip:Show()
    end)
    frame.fromLab:SetScript("OnLeave", GameTooltip_Hide)


    -- The footer: the band the template already reserves (y 4..26).
    frame.delete = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.delete:SetSize(100, 22)
    frame.delete:SetPoint("BOTTOMRIGHT", -6, 4 + DONATE_ROW)
    frame.delete:SetText(L["Delete"])
    frame.delete:SetScript("OnClick", function() UI.Delete() end)

    -- "Support the project" (27/09): a line of its own at the very bottom (Donate.lua).
    frame.donate = ns.DonateFooter(frame)

    frame.status = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.status:SetPoint("BOTTOMLEFT", 10, 8 + DONATE_ROW)
    frame.status:SetPoint("RIGHT", frame.delete, "LEFT", -8, 0)
    frame.status:SetJustifyH("LEFT")
    frame.status:SetWordWrap(false)

    -- THE WINDOW'S CLOCK. It is the addon's only `OnUpdate`, and it only runs with the window open --
    -- throttled to 0.1 s because what it draws changes second by second.
    --
    -- It sits on the window, and not on the panel, on purpose: a hidden frame's `OnUpdate` does not run,
    -- and the panel starts hidden. Tied to it, the progress would never show by itself.
    frame.__tick = 0
    frame:SetScript("OnUpdate", function(self, elapsed)
        self.__tick = self.__tick + (elapsed or 0)
        if self.__tick < 0.1 then return end
        self.__tick = 0
        UI.SyncLoadButtons()
        UI.RefreshProgress()
    end)

    BuildEditor()
    BuildProgress()
    BuildEmptyState()
    BuildToggles()
    return frame
end

--------------------------------------------------------------------------------
--- The set being edited. It is the set's TABLE, not an index -- `table.remove` in Delete
--- shifts the indices, and a kept index would come to point at another set.
--- Access to the list, only so the harness can fire a row's click. Without it the test
--- that locks the bug "não consigo clicar em outros conjuntos" could not exist.
function UI.DebugFrame()
    return frame
end

function UI.DebugList()
    return frame and frame.list
end

--- Access to the warnings strip, so the harness can click the boxes.
--- The progress panel, so the test can look at what the window shows. Without this door the
--- harness could only state that "there was no error" -- which is what it already said while the
--- skipped step showed the same as a step not started.
function UI.DebugProgress()
    return frame and frame.progress, editor
end

--- The panel's measures. What is locked here is the RATIO between the gaps, not the raw number: the
--- numbers change when the screen changes; the ratio is what cannot break again.
function UI.DebugMetrics()
    return {
        row = PROGRESS_ROW,
        icon = PROGRESS_ICON,
        iconGap = PROGRESS_ICON_GAP,
        titleGap = PROGRESS_TITLE_GAP,
        hold = PROGRESS_HOLD,
        states = PROGRESS_STATE,
    }
end

--- How tall a set's card is. Geometry is arithmetic and is checked on disk -- two
--- rounds of in-game testing were already spent in this project on position and width, and both were
--- checkable from here.
function UI.DebugCardHeight(preset)
    return CardHeight(preset)
end

--- THE LAST ROW `FillRow` filled, so the harness asks a real widget for its
--- POSITION.
---
--- (!) The first version of this returned the constant `CARD_TOP` instead of reading the frame. The test
--- then compared the constant with itself and always passed -- exactly the defect that had already
--- shown up three times in this session. A "debug" that answers from memory is no
--- witness: it has to look at the thing.
function UI.DebugLastRow()
    return lastFilledRow
end

function UI.DebugCardMetrics()
    return {
        pad = CARD_PAD, name = CARD_NAME_INK, line = CARD_LINE, warn = CARD_WARN,
        icon = CARD_ICON_MIN, iconMax = CARD_ICON_MAX, iconX = CARD_ICON_X,
        nameGap = CARD_NAME_GAP, left = CARD_LEFT,
        top = CARD_TOP, textW = CARD_TEXT_W, listW = LIST_W,
        cardMax = CARD_MAX, visiveis = CARDS_VISIVEIS, spacing = ROW_SPACING,
        listH = LIST_H, listTop = LIST_TOP, listBottom = LIST_BOTTOM,
        stripY = WARN_STRIP_Y, stripH = WARN_STRIP_H, footer = TEMPLATE_FOOTER, donateRow = DONATE_ROW,
        height = HEIGHT, width = WIDTH, colX = COL_X, fieldW = FIELD_W, nameW = NAME_W,
    }
end

function UI.DebugToggles()
    return frame and frame.toggles
end

function UI.Selected()
    return current
end

--- Selects a set through the window, as if the player had clicked its row.
---
--- It exists for the minimap shortcut: a set with an appearance cannot be applied from there (the
--- appearance swap needs the click on the secure button), so the shortcut opens the window **with it already
--- selected** -- one click more, and the right click.
---
--- `Refresh` re-anchors the selection from `current`, so pointing it and redrawing is enough.
function UI.Select(preset)
    if not preset then return end
    current = preset
    UI.Refresh()
    UI.RefreshEditor()
end

--- Is the window open?
---
--- It exists because `Toggle` toggles, and toggling forces the caller to know the state before. In
--- the harness that becomes an ORDER dependency between test blocks: a block that opens without closing
--- inverts the behaviour of all the following ones, and the defect shows far from where it was born --
--- which is exactly what happened when writing the tests of 0.10.0.
function UI.IsShown()
    return frame ~= nil and frame:IsShown() and true or false
end

function UI.SetStatus(text, isError)
    if not frame then return end
    frame.status:SetText(text or "")
    if isError then
        frame.status:SetTextColor(1, 0.5, 0.4)
    else
        frame.status:SetTextColor(0.75, 0.78, 0.82)
    end
end

---Is the name missing, as the player sees it NOW? With the focus in the box it is what is typed
---that counts (the preset only gets it when the box is left); without it, what the preset has.
local function NameMissing(preset)
    if not preset then return false end
    if editor.name:HasFocus() then
        return not ((editor.name:GetText() or ""):find("%S") ~= nil)
    end
    return not ns.Data.HasName(preset)
end

---The title of the box and the lock of the fields, from the name. The way the game does it in
---its own forms: what comes after the name stays off until there is one (the button of the
---talent loadout dialog, `Blizzard_ClassTalentLoadoutCreateDialog.lua:12`, 12.1.0).
function UI.RefreshNameState()
    if not frame or not editor then return end
    local missing = NameMissing(UI.Selected())
    if missing then
        editor.nameTitle:SetText(L["Preset name"] .. " "
            .. RED_FONT_COLOR:WrapTextInColorCode(L["(required)"]))
    else
        editor.nameTitle:SetText(L["Preset name"])
    end
    local reason = missing and L["Give the preset a name first."] or nil
    for _, group in ipairs({ editor.spec, editor.talent, editor.gear, editor.transmog }) do
        group.SetLocked(reason)
    end
end

--- The editor only. Called when the selection changes or when a combo writes.
function UI.RefreshEditor()
    if not frame or not editor then return end

    local preset = UI.Selected()

    -- THE EDITOR GIVES UP THE COLUMN WHILE THE PROGRESS IS IN IT. It is not only to avoid overlapping: changing
    -- the combos of a set being applied moves the target midway, and the chain has already read
    -- what it was going to read. Making the fields vanish is the most direct way to say "not
    -- now" -- more than disabling each of them.
    local has = preset ~= nil and not (frame.progress and frame.progress:IsShown())

    editor.name:SetShown(has)
    editor.nameTitle:SetShown(has)
    editor.openTalents:SetShown(has)
    editor.openGear:SetShown(has)

    -- The box first: the lock of the fields is read from it.
    if has and not editor.name:HasFocus() then
        editor.name:SetText(preset.name or "")
        if editor.name.Instructions and InputBoxInstructions_OnTextChanged then
            InputBoxInstructions_OnTextChanged(editor.name)
        end
    end
    if has then UI.RefreshNameState() end

    for _, group in ipairs({ editor.spec, editor.talent, editor.gear, editor.transmog }) do
        -- `SetupMenu` only builds the menu with the frame visible: show BEFORE syncing.
        group:SetShown(has)
        if has then group.Sync() end
    end
    editor.divider:SetShown(has)
end

function UI.Refresh()
    if not frame or not frame:IsShown() then return end

    local presets = Presets()
    local total = #presets
    local empty = total == 0

    -- The boxes stay out of the hide/show game on purpose: they hold in both
    -- states, and the empty state is exactly where they matter most.
    -- ONE PLACE ONLY sets the boxes' state (`UI.RefreshToggles`). This block repeated the same
    -- rule its function already had, and the sabotage gave it away: turning off its `SetEnabled`
    -- failed nothing, because the copy here kept setting the state. Two parts of the
    -- addon knowing the same thing is the drift of the next change with a date set.
    UI.RefreshToggles()

    frame.emptyState:SetShown(empty)
    if frame.Inset then frame.Inset:SetShown(not empty) end
    frame.list:SetShown(not empty)
    frame.new:SetShown(not empty)
    frame.delete:SetShown(not empty)
    frame.fromLab:SetShown(#ns.Data.RocketPairs() > 0)
    frame.fromLab:ClearAllPoints()
    if empty then
        frame.fromLab:SetPoint("TOPLEFT", frame, "TOPLEFT", 60, ATTIC_Y)
    else
        frame.fromLab:SetPoint("LEFT", frame.new, "RIGHT", 8, 0)
    end

    if empty then
        -- NO LIST, NO CURRENT. Without this line, `current` kept pointing at the last
        -- set selected even after it left the list -- and `UI.Selected()` returned a
        -- set that no longer exists, which is what `UI.Load` and `UI.Delete` consume.
        --
        -- The editor vanishes anyway right below, so none of it showed on screen; the test
        -- that covered it passed by an accident of order, because whoever ran before it left
        -- `current` nil. A new test block changed the order and the defect showed up.
        current = nil

        editor.name:Hide()
        editor.nameTitle:Hide()
        editor.openTalents:Hide()
        editor.openGear:Hide()
        editor.divider:Hide()
        for _, group in ipairs({ editor.spec, editor.talent, editor.gear, editor.transmog }) do
            group:Hide()
        end
        return
    end

    -- `SetDataProvider` erases the behaviour's selection; that is why the current set is
    -- kept outside and re-anchored right below.
    local wanted = current
    frame.list:SetDataProvider(CreateDataProvider(presets), true)

    local stillThere = false
    for i = 1, total do
        if presets[i] == wanted then stillThere = true end
    end

    -- Automatic selection: it is what keeps the "nothing selected" state from existing, and with it
    -- the orphan labels and the stuck text. It is not a patch -- it is the removal of the state.
    selection:SelectElementData(stillThere and wanted or presets[1])

    UI.RefreshEditor()
end

--- After a combo changes: the row's text changed, the count did not. Re-initialising is
--- cheaper than swapping the data provider, and does not lose the scroll.
function UI.AfterEdit()
    if frame and frame.list and frame.list.ReinitializeFrames then
        frame.list:ReinitializeFrames()
    end
    UI.RefreshEditor()
    -- The preset's macro follows it: made the first time it has a name, renamed and re-iconed
    -- after (Macro.lua).
    if ns.Macro then ns.Macro.Sync(UI.Selected()) end
end

--------------------------------------------------------------------------------
function UI.New()
    local presets = Presets()

    -- ONE WITHOUT A NAME AT A TIME. "+ New preset" with one still unnamed goes to it instead of
    -- piling another "Unnamed" on the list.
    for _, p in ipairs(presets) do
        if not ns.Data.HasName(p) then
            current = p
            UI.Refresh()
            editor.name:SetFocus()
            UI.SetStatus(L["Give the preset a name first."], true)
            return
        end
    end

    -- The new set is born with what holds NOW. It is the real use case: you
    -- just arranged spec, talents and gear for a dungeon -- now you only want to give
    -- it a name. Starting empty would force retyping the obvious.
    local specIndex = ns.Data.GetCurrentSpecIndex()
    local spec = ns.Data.GetSpecByIndex(specIndex)

    local preset = {
        name = "",
        spec = specIndex,
        talent = spec and ns.Data.GetActiveLoadoutID(spec.id) or nil,
        gear = ns.Data.GetEquippedSetID(),
    }
    presets[#presets + 1] = preset

    current = preset
    UI.Refresh()
    editor.name:SetFocus()
end

---(25/10) Makes or updates a preset for each Rocket SBA Lab build the game has (Data.RocketPairs): the preset with the
---same items set and specialization, else the one of the same name, gets the build's talents; none, a new one.
function UI.FromRocketLab()
    local presets = Presets()
    local made, updated, same = 0, 0, 0
    local last
    for _, pair in ipairs(ns.Data.RocketPairs()) do
        local found
        for _, p in ipairs(presets) do
            if p.gear == pair.gear and p.spec == pair.spec then found = p; break end
        end
        if not found then
            for _, p in ipairs(presets) do
                if p.name == pair.name then found = p; break end
            end
        end
        if found then
            if found.talent == pair.talent and found.gear == pair.gear and found.spec == pair.spec then
                same = same + 1
            else
                found.spec, found.talent, found.gear = pair.spec, pair.talent, pair.gear
                updated = updated + 1
            end
            last = found
        else
            last = { name = pair.name, spec = pair.spec, talent = pair.talent, gear = pair.gear }
            presets[#presets + 1] = last
            made = made + 1
        end
        if ns.Macro then ns.Macro.Sync(last) end
    end
    if not last then
        UI.SetStatus(L["The game has no talents and items of Rocket SBA Lab yet."], true)
        return
    end
    current = last
    UI.Refresh()
    if made + updated == 0 then
        UI.SetStatus(L["The Rocket SBA Lab presets are already up to date."], false)
    else
        UI.SetStatus(L["Rocket SBA Lab: %d preset(s) created, %d updated."]:format(made, updated), false)
    end
end

function UI.SaveName()
    local preset = UI.Selected()
    if not preset then return end

    local name = editor.name:GetText() or ""
    name = name:match("^%s*(.-)%s*$")
    -- THE NAME IS REQUIRED: erased, the one the preset had comes back, and the window says so.
    -- A preset that never had one stays as it is, asking for it. Before the "nothing changed"
    -- below: an empty box on a preset without a name changed nothing and still has to say it.
    if name == "" then
        if ns.Data.HasName(preset) then
            editor.name:SetText(preset.name)
            if editor.name.Instructions and InputBoxInstructions_OnTextChanged then
                InputBoxInstructions_OnTextChanged(editor.name)
            end
            UI.SetStatus(L["A preset needs a name: the previous one was kept."], true)
        else
            UI.SetStatus(L["Give the preset a name first."], true)
        end
        UI.RefreshNameState()
        return
    end
    if name == preset.name then return end

    preset.name = name
    UI.SetStatus("", false)
    UI.AfterEdit()
end

function UI.Delete()
    local preset = UI.Selected()
    if not preset then return end

    if ns.Macro then ns.Macro.Remove(preset) end
    local presets = Presets()
    for i = 1, #presets do
        if presets[i] == preset then
            table.remove(presets, i)
            break
        end
    end

    current = nil
    if selection and selection.ClearSelections then selection:ClearSelections() end
    UI.SetStatus(L["preset deleted."], false)
    UI.Refresh()
end

--- Called from the secure button's `PostClick`, and so the third argument is `true`: the
--- appearance action WAS already fired by the click, and the appearance step has to WAIT for the
--- server's answer instead of checking on the spot and flagging a failure on a swap on its way.
--- The rows follow the game. Each row keeps what it was drawn from (`RowState`), and this compares
--- it with what the game says now: a switch that began or ended (in the window or outside it: a
--- macro, the minimap menu, the queue alert), a piece that left or came back to the bags. A
--- change that fell in combat is done when the combat ends. Called by the window's clock, and by
--- the click, which cannot wait for the clock.
function UI.SyncLoadButtons()
    if not frame or not frame.list then return end
    local velha = loadStatePending and not InCombatLockdown()
    if not velha and frame.list.ForEachFrame then
        frame.list:ForEachFrame(function(row)
            if row.preset and row.drawn ~= RowState(row.preset) then velha = true end
        end)
    end
    if not velha then return end
    loadStatePending = false
    if frame.list.ReinitializeFrames then frame.list:ReinitializeFrames() end
end

function UI.Load(preset)
    if not preset then return end
    ns.db.last = preset.name
    ns.Data.Apply(preset, UI.SetStatus, true)
    -- In the same frame as the click: the other buttons go off before a second click can land.
    UI.SyncLoadButtons()
    -- IN THE SAME FRAME AS THE CLICK. `OnUpdate` would bring the panel within 0.1 s, but the defect
    -- this panel fixes is exactly the feeling that the click did nothing -- so it cannot
    -- be the first thing to arrive late.
    UI.RefreshProgress()
end

--------------------------------------------------------------------------------
function UI.Toggle()
    Create()
    if frame:IsShown() then
        frame:Hide()
        return
    end

    if ns.db.pos then
        frame:ClearAllPoints()
        frame:SetPoint(ns.db.pos.point, UIParent, ns.db.pos.relPoint, ns.db.pos.x, ns.db.pos.y)
    end

    frame:Show()
    UI.SetStatus("", false)
    UI.Refresh()
end

function UI.Show()
    Create()
    if not frame:IsShown() then UI.Toggle() end
end
