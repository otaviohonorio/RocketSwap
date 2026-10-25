-- RocketSwap | Progress.lua
-- The swap's floating panel: it shows by itself when the swap starts, goes away by itself when it
-- ends, and **does not depend on the addon's window being open**.
--
-- WHY IT EXISTS, when the window already shows the progress in its right column. Because the user's
-- request was literal -- *"ainda sinto falta de um aviso e alguma coisa que mostre o progresso
-- melhor da troca até terminar, que visualmente o usuário entenda que ainda está trocando"* -- and
-- the panel inside the window answers only whoever has the window open. In practice the player
-- clicks Load and goes back to looking at the game: that, and not the window just left behind, is
-- where the signal has to show.
--
-- ⚑ AND IT HAS NO DATA OF ITS OWN. Everything comes from `Data.GetProgress()`, the same the window
-- reads, and each state's art comes from `ns.ProgressVisuals`, the same table the window uses. Two
-- screens with two readings of the same fact drift apart at the first change -- and then one lies.
local ADDON, ns = ...
local L = ns.L

local Progress = {}
ns.Progress = Progress

local WIDTH = 240
local PAD = 10
local ROW = ns.PROGRESS_ROW or 22
local ICON = ns.PROGRESS_ICON or 16
local ICON_GAP = ns.PROGRESS_ICON_GAP or 5
local TITLE_INK = 16
local TITLE_GAP = 13
local BAR_H = 8
local BAR_GAP = 8

-- How long the result stays on screen after the swap ends. **Three seconds, the user's choice**:
-- it goes away by itself, with no click needed, but leaves time to read what happened.
--
-- A failure does NOT count here: if any step failed, the panel stays until the player closes it.
-- What has to be read cannot have a deadline, and here the deadline would erase the one case
-- where it has something to say.
local HOLD = 3

-- THE VICTORY CRY. The user's request: in the three seconds left after the swap ends, the panel
-- stops being a report and becomes a celebration.
--
-- And it makes sense beyond the joke: at that point the list of steps has done its job -- whoever
-- was following already saw each one close. What is left to say is one thing only, and from afar:
-- **it is over, and it worked**. One big line says that better than four lines of detail.
--
-- And it is **the phrase alone**. An earlier version left "Switching to <set>" under it, and the
-- user pointed out the obvious: by then it has switched, so the line was in the wrong tense --
-- announcing as present what had just become past.
--
-- ONLY ON SUCCESS. If any step failed, the panel keeps showing the list and stays until the
-- player closes it: celebrating over a step that failed would be the worst possible ending.
--
-- It is not a translation key on purpose: it is a proper name, the same in every language.
local SHOUT = "Leroy Jeeeeeennkiiinnss!"

-- The bar's colour at each moment. Gold is "moving" -- the progress colour of the whole game.
-- Green only shows when **everything closed and it worked**, so it needs no legend: nobody
-- mistakes a full green bar for a swap halfway.
local BAR_RUNNING = { 1, 0.82, 0, 0.85 }
local BAR_DONE    = { 0.25, 0.78, 0.35, 0.90 }

local frame

--------------------------------------------------------------------------------
-- A barra
--------------------------------------------------------------------------------
-- ⚑ THE BAR MOVES BY STEP, NOT BY TIME -- and that difference is what makes it honest.
--
-- The chain does not know how long it will take: the specialization step waits for the server,
-- and the real log showed the same swap accepted in 4 seconds one time and 14 another. A bar
-- running by itself against a clock invents a forecast nobody has, and a bar stuck halfway is
-- worse than no bar -- that is why the version inside the window refused to have one.
--
-- What can be stated is **how many steps closed out of how many**. That is true at every frame,
-- it is what the player wants to know, and it needs no guessing.
--
-- And there is one fair exception: when the step under way is a real CAST (the specialization
-- switch casts spell 200749), the game says when it starts and ends, and then that step's slice
-- can move with the cast's real time. That is not a forecast: it is a measure.
local function BarFill(passos)
    if not passos or #passos == 0 then return 0 end

    local fechados, atual = 0, nil
    for i, p in ipairs(passos) do
        if p.state == "done" or p.state == "skipped" or p.state == "failed" then
            fechados = fechados + 1
        elseif p.state == "doing" and not atual then
            atual = i
        end
    end

    local fatia = 1 / #passos
    local fill = fechados * fatia

    -- The slice of the step under way only moves when there is a measured cast.
    if atual and UnitCastingInfo then
        local _, _, _, startMS, endMS = UnitCastingInfo("player")
        if startMS and endMS and endMS > startMS then
            local agora = GetTime() * 1000
            local dentro = (agora - startMS) / (endMS - startMS)
            if dentro > 0 and dentro < 1 then
                fill = fill + fatia * dentro
            end
        end
    end

    return math.min(1, fill)
end

--------------------------------------------------------------------------------
-- Montagem
--------------------------------------------------------------------------------
local function Build()
    -- (25/10) the game's tooltip border (TooltipBorderBackdropTemplate: its NineSlice, an empty centre) around the dark
    -- art, instead of a flat WHITE8X8 backdrop with a 1-pixel black edge (the workspace rules: no hand-painted panel)
    frame = CreateFrame("Frame", ADDON .. "Progress", UIParent, "TooltipBorderBackdropTemplate")
    frame:SetWidth(WIDTH)
    frame:SetHeight(80)
    frame:SetFrameStrata("HIGH")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetClampedToScreen(true)

    -- (13/10) THE VISUAL IDENTITY of every Rocket addon (the workspace rules, "Skin"): a panel is the
    -- game's panel stone (UI-Background-Rock, tiled, untinted -- DefaultPanelTemplate's, the RocketMeter
    -- settings window's); a LIST sits on the dark inset. This is a panel: the stone, over the backdrop's
    -- flat centre (its BACKGROUND -8), at the same 0.92, so it stays as see-through.
    -- (25/10) DARK EVERYWHERE: the user chose the app's look as the reference and "escuro em tudo" -- the panel wears
    -- the Specialization tab's dark art (spec-background), as RocketLab's tabs; an atlas, never tiled (one texture
    -- tiled and then given an atlas showed the whole atlas file: RocketLab, 13/10)
    frame.art = ns.DarkBody(frame, 0.92)

    local pos = ns.db and ns.db.progressPos
    if pos then
        frame:SetPoint(pos.point or "CENTER", UIParent, pos.point or "CENTER", pos.x or 0, pos.y or 0)
    else
        -- Above the action bar and below the centre: out of the crosshair, but in the eye's way.
        frame:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 220)
    end

    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint()
        if ns.db then ns.db.progressPos = { point = point, x = x, y = y } end
    end)

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.title:SetPoint("TOPLEFT", PAD, -PAD)
    frame.title:SetWidth(WIDTH - PAD * 2 - 40)
    frame.title:SetJustifyH("LEFT")
    frame.title:SetWordWrap(false)

    frame.clock = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.clock:SetPoint("TOPRIGHT", -PAD, -PAD - 2)
    frame.clock:SetWidth(36)
    frame.clock:SetJustifyH("RIGHT")

    -- A barra.
    local trilho = CreateFrame("Frame", nil, frame)
    trilho:SetPoint("TOPLEFT", PAD, -(PAD + TITLE_INK + BAR_GAP))
    trilho:SetSize(WIDTH - PAD * 2, BAR_H)
    trilho.bg = trilho:CreateTexture(nil, "BACKGROUND")
    trilho.bg:SetAllPoints()
    trilho.bg:SetColorTexture(1, 1, 1, 0.08)

    trilho.fill = trilho:CreateTexture(nil, "ARTWORK")
    trilho.fill:SetPoint("TOPLEFT")
    trilho.fill:SetPoint("BOTTOMLEFT")
    trilho.fill:SetWidth(1)
    trilho.fill:SetColorTexture(1, 0.82, 0, 0.85)

    -- The cuts between the slices: without them the bar becomes one block and the player loses track
    -- of how many stages there are, which is the information this bar carries.
    -- Visible from start to end: it is the only part of the progress screen that still says something
    -- after the swap ends.
    trilho:Show()
    trilho.ticks = {}
    trilho:SetScript("OnShow", function() end)
    frame.trilho = trilho

    -- The step lines, with the window's same art and states.
    frame.rows = {}
    for i = 1, 4 do
        local row = CreateFrame("Frame", nil, frame)
        row:SetSize(WIDTH - PAD * 2, ROW)
        row:SetPoint("TOPLEFT", PAD, -(PAD + TITLE_INK + BAR_GAP + BAR_H + TITLE_GAP + (i - 1) * ROW))

        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(ICON, ICON)
        row.icon:SetPoint("LEFT")

        row.dot = row:CreateTexture(nil, "ARTWORK")
        row.dot:SetSize(4, 4)
        row.dot:SetPoint("CENTER", row.icon, "CENTER")
        row.dot:SetColorTexture(1, 1, 1, 0.5)

        row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.label:SetPoint("LEFT", row.icon, "RIGHT", ICON_GAP, 0)
        row.label:SetWidth(WIDTH - PAD * 2 - ICON - ICON_GAP)
        row.label:SetJustifyH("LEFT")
        row.label:SetWordWrap(false)

        frame.rows[i] = row
    end

    -- The cry fills the whole panel when it shows, so it is born centred and hidden.
    -- The cry takes the space of the step lines, BELOW the bar -- which never leaves the screen. Two
    -- lines are allowed: in a 240-wide window the phrase does not fit whole, and shrinking the font
    -- to force one line would take from it exactly the size, which is the message.
    frame.shout = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.shout:SetPoint("TOPLEFT", frame.trilho, "BOTTOMLEFT", 0, -6)
    frame.shout:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD, PAD)
    frame.shout:SetJustifyH("CENTER")
    frame.shout:SetJustifyV("MIDDLE")
    frame.shout:SetWordWrap(true)
    frame.shout:SetTextColor(0.35, 0.90, 0.45)
    frame.shout:Hide()

    frame.close = CreateFrame("Button", nil, frame)
    frame.close:SetSize(14, 14)
    frame.close:SetPoint("TOPRIGHT", -4, -4)
    frame.close.tex = frame.close:CreateTexture(nil, "ARTWORK")
    frame.close.tex:SetAllPoints()
    if not (ns.SetAtlasSafe and ns.SetAtlasSafe(frame.close.tex, "common-icon-redx")) then
        frame.close.tex:SetTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
    end
    frame.close.tex:SetAlpha(0.5)
    frame.close:SetScript("OnClick", function() frame:Hide() end)
    frame.close:SetScript("OnEnter", function() frame.close.tex:SetAlpha(1) end)
    frame.close:SetScript("OnLeave", function() frame.close.tex:SetAlpha(0.5) end)
    frame.close:Hide()

    frame:SetScript("OnUpdate", function(self, elapsed)
        self.__acc = (self.__acc or 0) + elapsed
        if self.__acc < 0.1 then return end
        self.__acc = 0
        Progress.Refresh()
    end)

    frame:Hide()
    return frame
end

--------------------------------------------------------------------------------
-- Desenho
--------------------------------------------------------------------------------
local function LayoutTicks(trilho, n)
    for _, t in ipairs(trilho.ticks) do t:Hide() end
    if n < 2 then return end
    local largura = trilho:GetWidth()
    for i = 1, n - 1 do
        local t = trilho.ticks[i]
        if not t then
            t = trilho:CreateTexture(nil, "OVERLAY")
            t:SetColorTexture(0, 0, 0, 0.8)
            t:SetWidth(1)
            trilho.ticks[i] = t
        end
        t:ClearAllPoints()
        t:SetPoint("TOP", trilho, "TOPLEFT", largura * (i / n), 0)
        t:SetPoint("BOTTOM", trilho, "BOTTOMLEFT", largura * (i / n), 0)
        t:Show()
    end
end

--- The panel's two faces: the report (while switching, and when it fails) and the cry (when it
--- ends well). One hides the other entirely -- laying one over the other would leave the cry
--- unreadable over the step lines.
local function ShowShout(frame_, mostrar)
    frame_.shout:SetShown(mostrar)
    -- THE BAR STAYS. It is the only thing of the progress screen that still says something after the
    -- end -- full and green, it is "all closed" as a shape, and it goes away with the panel.
    frame_.clock:SetShown(not mostrar)
    frame_.title:SetShown(not mostrar)
    for _, row in ipairs(frame_.rows) do
        if mostrar then row:Hide() end
    end

    local cor = mostrar and BAR_DONE or BAR_RUNNING
    frame_.trilho.fill:SetColorTexture(cor[1], cor[2], cor[3], cor[4])
    if mostrar then
        frame_.shout:SetText(SHOUT)
        frame_.trilho.fill:SetWidth(frame_.trilho:GetWidth())
    end
end

function Progress.Refresh()
    if not frame then return end

    local passos, info = ns.Data.GetProgress()
    if not passos or not info then
        frame:Hide()
        return
    end

    -- The two transitions, the way the window handles them: `info.live` is now,
    -- `frame.live` is what this panel saw last.
    if info.live and not frame.live then
        frame.live, frame.holdUntil = true, nil
    elseif not info.live and frame.live then
        frame.live = false
        local falhou = false
        for _, p in ipairs(passos) do
            if p.state == "failed" then falhou = true end
        end
        -- A failure has no deadline: it stays until the player closes it.
        frame.holdUntil = falhou and math.huge or (GetTime() + HOLD)
        frame.close:SetShown(falhou)
        frame.shouting = not falhou
    end

    if not info.live and frame.holdUntil and GetTime() >= frame.holdUntil then
        frame.holdUntil = nil
        frame:Hide()
        return
    end

    -- THE HEIGHT IS THE SAME FROM START TO END. Shrinking at the end makes the panel jump on screen
    -- right when the eye comes back to it, and a layout jump reads as a defect.
    frame:SetHeight(PAD * 2 + TITLE_INK + BAR_GAP + BAR_H + TITLE_GAP + ROW * #passos)

    -- ENDED AND IT WORKED: the panel changes its content for the three seconds it has left.
    if frame.shouting then
        ShowShout(frame, true)
        if not frame:IsShown() then frame:Show() end
        return
    end

    ShowShout(frame, false)
    frame.title:SetText(format(L["Switching to %s"], info.preset and info.preset.name or "?"))

    if info.live then
        local secs = math.max(0, math.floor(GetTime() - (info.startedAt or 0)))
        frame.clock:SetText(secs .. "s")
    end

    local trilho = frame.trilho
    LayoutTicks(trilho, #passos)
    local fill = BarFill(passos)
    -- `SetWidth(0)` makes the texture vanish and the game complains; 1 px is the smallest visible.
    trilho.fill:SetWidth(math.max(1, trilho:GetWidth() * fill))

    for i, row in ipairs(frame.rows) do
        local passo = passos[i]
        row:SetShown(passo ~= nil)
        if passo then
            local visual = ns.ProgressVisuals[passo.state] or ns.ProgressVisuals.pending
            local temArte = visual.atlas and ns.SetAtlasSafe
                and ns.SetAtlasSafe(row.icon, visual.atlas) or false
            row.icon:SetShown(temArte)
            row.icon:SetAlpha(visual.alpha)
            row.dot:SetShown(not temArte)
            row.dot:SetVertexColor(1, 1, 1, visual.alpha)
            row.label:SetText(passo.label)
            row.label:SetAlpha(visual.alpha)
        end
    end

    if not frame:IsShown() then frame:Show() end
end

--- Called by the chain when a swap starts.
function Progress.Start()
    if ns.db and ns.db.hideProgress then return end
    if not frame then Build() end
    frame.live, frame.holdUntil, frame.shouting = nil, nil, nil
    frame.close:Hide()
    ShowShout(frame, false)
    Progress.Refresh()
end

function Progress.Frame()
    return frame
end

--- The bar's arithmetic, exposed for the harness.
---
--- The bar's art only shows in the game, but the ARITHMETIC is arithmetic and is checked on disk --
--- and it is what carries the promise: the bar states how many steps closed, and nothing about time.
function Progress.DebugShout()
    return SHOUT
end

function Progress.DebugBarFill(passos)
    return BarFill(passos)
end
