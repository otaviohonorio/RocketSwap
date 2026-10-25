-- RocketSwap | Minimap.lua
-- The minimap button, with no external library.
--
-- Why not the common minimap-button library: it handles dragging, saving the angle and the
-- integration with data bars. Only the first matters here, and it fits in 30 lines -- a dependency
-- that has to be packaged and kept up to date does not pay for that.
local ADDON, ns = ...
local L = ns.L

local Minimap_ = {}
ns.Minimap = Minimap_

-- (!) THE RADIUS FOLLOWS THE MINIMAP (24/10). A player on CurseForge: *"cant move (from the center)
-- minimap ico when minimap >110%"*; the user reproduced it: with the minimap enlarged our button only
-- went round INSIDE the map, while the other addons' buttons sat on the enlarged border. The radius
-- was a fixed 80, inside a 198 map; the common minimap-button library uses half the minimap's width
-- plus 5, read at every placement. Same numbers here, and the button follows when the size changes.
local RIM = 5

local function Radius()
    return Minimap:GetWidth() / 2 + RIM
end
local button

-- Icon candidates, from the preferred one to the last resort. The CLIENT chooses, through
-- `ns.FirstIcon` -> `GetFileIDFromPath`: a texture path that does not exist fails silently,
-- and an icon name is exactly what cannot be checked on disk (the textures live in the
-- CASC, not in the addons folder).
--
-- The last one in the list is RocketMeter's -- the only name I KNOW exists in this client,
-- because the user sees it in the addon list today. If every other one fails, it falls on that.
--
-- `/rs icon` prints which ones resolved: to prefer another, change one line.
local ICON_CANDIDATES = {
    "Interface\\Icons\\INV_Misc_EnggizmosCog",
    "Interface\\Icons\\INV_Misc_Gear_01",
    "Interface\\Icons\\Trade_Engineering",
    "Interface\\Icons\\INV_Misc_Bag_08",
    "Interface\\Icons\\INV_Misc_MissileLarge_Red",
}

ns.ICON_CANDIDATES = ICON_CANDIDATES

local function Reposition()
    local angle = math.rad(ns.db.minimap and ns.db.minimap.angle or 210)
    local radius = Radius()
    button:SetPoint("CENTER", Minimap, "CENTER",
        math.cos(angle) * radius, math.sin(angle) * radius)
end

--------------------------------------------------------------------------------
-- The right-click list
--
-- (!) THE LIST IS MADE OF SECURE BUTTONS, NOT OF THE GAME'S MENU ITEMS (01/10). A user reported:
-- right click, pick a preset, and the WINDOW opened instead of the switch. Read in the saved
-- file of this machine: 11 of the 12 presets have an appearance, and a preset with appearance
-- cannot be loaded from the game's context menu (`MenuUtil.CreateContextMenu`): the outfit only
-- changes inside the player's click on a SECURE button (UI.lua, `ArmOutfit`), and a menu item is
-- not one. `ns.LoadPreset` then opened the window for the "right" click -- for every preset
-- with an appearance, which is nearly all of them. So the list is ours, each row a secure button with the
-- recipe of the window's Load button: the outfit armed in PreClick, the rest in PostClick.
--
-- THE LOOK IS THE GAME'S CONTEXT MENU (Blizzard_Menu, 12.1.0): the background is the atlas
-- `common-dropdown-bg` drawn 10 beyond the sides and 3 beyond top and bottom at 0.925
-- (`MenuStyle1Mixin:Generate`), the inset 8 / 8 / 8 / 15 (`GetInset`), each item 20 tall
-- (`MenuVariants.CreateFontString`), the highlight `UI-QuestTitleHighlight` added over it
-- (`MenuVariants.CreateHighlight`), the title in the gold of `NORMAL_FONT_COLOR`.
--------------------------------------------------------------------------------
local MENU_ITEM = 20
local MENU_INSET = { left = 8, top = 8, right = 8, bottom = 15 }
local MENU_PAD = 20            -- `GetChildExtentPadding().width`
local MENU_MIN = 120
local menu

local function MenuRow(index)
    local row = menu.rows[index]
    if row then return row end
    row = CreateFrame("Button", nil, menu, "SecureActionButtonTemplate")
    row:SetHeight(MENU_ITEM)
    row:RegisterForClicks("AnyUp")
    row:SetAttribute("useOnKeyDown", false)
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightLeft")
    row.text:SetPoint("LEFT")
    row.text:SetHeight(MENU_ITEM)
    row.highlight = row:CreateTexture(nil, "BACKGROUND")
    row.highlight:SetAllPoints()
    row.highlight:SetBlendMode("ADD")
    row.highlight:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    row.highlight:Hide()
    row:SetScript("OnEnter", function(self) self.highlight:Show() end)
    row:SetScript("OnLeave", function(self) self.highlight:Hide() end)
    -- The same guard as the Load button's: a pre-flight "no" disarms the outfit before the
    -- secure action runs, so the appearance never changes alone.
    row:SetScript("PreClick", function(self)
        local preset = self.preset
        if preset and not InCombatLockdown() then
            ns.UI.ArmOutfit(self, (#ns.Data.Preflight(preset, true) == 0) and preset or nil)
        end
        -- Which control took the click (see the Load button's PreClick, UI.lua).
        ns.Log.Add("click", { where = "minimap", preset = preset and preset.name or "?",
            type = tostring(self:GetAttribute("type")), outfit = tostring(self:GetAttribute("outfit-index")),
            combat = InCombatLockdown() and true or false })
    end)
    row:SetScript("PostClick", function(self)
        local preset = self.preset
        menu:Hide()
        if not preset then return end
        -- Without a name it does not load: the window opens on it, where the name is typed.
        if not ns.Data.HasName(preset) then
            ns.LoadPreset(preset)
            return
        end
        -- Why it will not load, said in the chat: the window may be closed, and a click that
        -- does nothing and says nothing is what was reported.
        local motivo = ns.Data.LoadBlockedReason(preset)
        if motivo then ns.Print(motivo) end
        ns.UI.Load(preset)
    end)
    menu.rows[index] = row
    return row
end

local function CreateMenu()
    if menu then return menu end
    menu = CreateFrame("Frame", ADDON .. "MinimapMenu", UIParent)
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:SetClampedToScreen(true)
    menu:EnableMouse(true)
    menu:Hide()
    menu.rows = {}

    menu.bg = menu:CreateTexture(nil, "BACKGROUND")
    menu.bg:SetAtlas("common-dropdown-bg")
    menu.bg:SetPoint("TOPLEFT", -10, 3)
    menu.bg:SetPoint("BOTTOMRIGHT", 10, -3)
    menu.bg:SetAlpha(0.925)

    menu.title = menu:CreateFontString(nil, "OVERLAY", "GameFontNormalLeft")
    menu.title:SetPoint("TOPLEFT", MENU_INSET.left, -MENU_INSET.top)
    menu.title:SetHeight(MENU_ITEM)

    -- Closes as the game's menus do: a click anywhere else, Esc, and the start of a fight (a
    -- secure row cannot be touched in combat; hidden before the lockdown, nothing has to be).
    menu:RegisterEvent("GLOBAL_MOUSE_DOWN")
    menu:RegisterEvent("PLAYER_REGEN_DISABLED")
    menu:SetScript("OnEvent", function(self, event)
        if not self:IsShown() then return end
        if event == "PLAYER_REGEN_DISABLED" then self:Hide(); return end
        if self:IsMouseOver() or (button and button:IsMouseOver()) then return end
        if not InCombatLockdown() then self:Hide() end
    end)
    if UISpecialFrames and tinsert then tinsert(UISpecialFrames, menu:GetName()) end
    return menu
end

---The right-click list: the presets, by name, each a click away from the whole switch.
---
---With no preset the right click does what the left does -- opens the window. In combat the
---list does not open: nothing switches in combat, and a secure row cannot be set up there.
---Opening the list NEVER switches by itself: the switch is the click on a row.
function Minimap_.Menu(owner)
    local presets = ns.db and ns.db.presets or {}
    if #presets == 0 then
        ns.UI.Toggle()
        return false
    end
    if InCombatLockdown() then
        ns.Print(L["in combat: nothing was changed. Switch after the fight."])
        return false
    end

    CreateMenu()
    if menu:IsShown() then menu:Hide(); return false end

    menu.title:SetText(L["Switch to"])
    local width = menu.title:GetStringWidth() or 0
    for i, preset in ipairs(presets) do
        local row = MenuRow(i)
        row.preset = preset
        -- A preset of before the name was required: it says so, instead of an empty line.
        row.text:SetText(ns.Data.HasName(preset) and preset.name or L["Unnamed"])
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", MENU_INSET.left, -(MENU_INSET.top + i * MENU_ITEM))
        row:SetPoint("RIGHT", -MENU_INSET.right, 0)
        row:Show()
        local w = row.text:GetStringWidth() or 0
        if w > width then width = w end
    end
    for i = #presets + 1, #menu.rows do
        menu.rows[i].preset = nil
        menu.rows[i]:Hide()
    end
    menu:SetSize(math.max(MENU_MIN, width + MENU_PAD) + MENU_INSET.left + MENU_INSET.right,
        MENU_INSET.top + (#presets + 1) * MENU_ITEM + MENU_INSET.bottom)

    menu:ClearAllPoints()
    if owner and owner.GetCenter then
        menu:SetPoint("TOPRIGHT", owner, "BOTTOMLEFT", 0, 0)
    else
        menu:SetPoint("CENTER")
    end
    menu:Show()
    return true
end

---For the harness: the list as drawn.
function Minimap_.__menu() return menu end

function Minimap_.Create()
    if button then return button end

    button = CreateFrame("Button", ADDON .. "MinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetMovable(true)

    -- The icon IS the set you are wearing now.
    --
    -- Two reasons. The good one: the button becomes an indicator -- at a glance you can tell Frost
    -- from PvP without opening anything, which is exactly the information that gets lost. The honest
    -- one: no nice icon name could be CONFIRMED on disk (Blizzard's dump only gives
    -- `INV_Misc_QuestionMark` and `INV_Misc_Coin_17`), and an icon that does not exist fails silently.
    -- The set's icon comes from the API, so it is always real.
    -- (!) THE GAME'S RING AND THE ICON, AT THE NUMBERS EVERY OTHER BUTTON USES (06/10). Reported
    -- with a screenshot: our drawing sat off-centre inside the gold ring. The button had the ring
    -- at 53 and the icon at 19, shifted (-1, 1) -- numbers of the OLD clients. On retail the
    -- common minimap-button library (its `WOW_PROJECT_MAINLINE`
    -- branch) draws the ring at 50 from the top left, the game's dark disc at 24 and the icon at
    -- 18, both at the button's very centre. With the game's square icons nobody saw the 1.5
    -- points; with a ring of our own inside the gold one, it shows.
    button.disc = button:CreateTexture(nil, "BACKGROUND")
    button.disc:SetSize(24, 24)
    button.disc:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    button.disc:SetPoint("CENTER", button, "CENTER")

    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetSize(18, 18)
    button.icon:SetPoint("CENTER", button, "CENTER")
    button.icon:SetTexCoord(0, 1, 0, 1)
    -- Round, as the other two addons' buttons: the art is square and the ring is not.
    button.icon:SetMask("Interface\\CharacterFrame\\TempPortraitAlphaMask")

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(50, 50)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    button.border = border

    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    -- (!) THE RIGHT BUTTON LISTS THE SETS. IT SWITCHES NOTHING ON ITS OWN.
    --
    -- It called `ns.LoadLast()`, and a user reported on video that the right click "switched
    -- the spec by itself". He was right, and the code did exactly that.
    --
    -- Two reasons to take it out:
    --
    --   * A RIGHT CLICK ON A MINIMAP ICON OPENS A MENU. It is the convention of the whole game, and it
    --     is what the other two Rocket addons do (in both, the right click opens the options). This one
    --     was the only one that differed -- and the only one where the different action was destructive.
    --     Whoever clicks expecting a menu gets a switch of spec, talents and items.
    --   * THE TOOLTIP SAVES NO ONE. It said "Right click: load the last preset", but a tooltip
    --     needs hovering and reading, and nobody reads a tooltip before right-clicking.
    --
    -- WHY IT DID NOT SHOW HERE: every set of this developer has an appearance, and a set with an
    -- appearance takes the `LoadPreset` branch that OPENS THE WINDOW instead of applying.
    -- His data kept the defect from happening. The sets of the user who reported it have no
    -- appearance, so they went straight to `Data.Apply`. Confirmed in both SavedVariables.
    button:SetScript("OnClick", function(self, mouseButton)
        if mouseButton == "RightButton" then
            Minimap_.Menu(self)
        else
            ns.UI.Toggle()
        end
    end)

    button:SetScript("OnEnter", function(self)
        -- (!) THE MINIMAP TOOLTIP OF EVERY ROCKET ADDON (13/10, the visual identity): the user, *"os ícones do
        -- minimap não precisam do texto arraste para mover (...) cada um com um tempo de escrita, um com texto
        -- verde, outro cinza (...) vamos padronizar"*. The game's tooltip helpers, in one order: the title;
        -- the state, white; a blank line; one green line per action ("Click: ...", "Right-click: ...",
        -- "Shift-click: ..."), the verb in the infinitive. No "drag to move".
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip_SetTitle(GameTooltip, ns.TITLE)
        GameTooltip_AddBlankLineToTooltip(GameTooltip)
        GameTooltip_AddInstructionLine(GameTooltip, L["Click: open the window"])
        GameTooltip_AddInstructionLine(GameTooltip, L["Right-click: pick a preset"])
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", GameTooltip_Hide)

    -- Dragging: the angle comes from the cursor's position relative to the minimap's centre, which
    -- makes the button follow the edge instead of floating across the screen.
    button:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local px, py = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            px, py = px / scale, py / scale

            ns.db.minimap = ns.db.minimap or {}
            ns.db.minimap.angle = math.deg(math.atan2(py - my, px - mx))
            Reposition()
        end)
    end)
    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)

    Minimap:HookScript("OnSizeChanged", Reposition)
    Reposition()
    Minimap_.Refresh()
    return button
end

--- The button's icon: FIXED and generic.
---
--- The first version showed the worn set's icon, meant as an indicator. In practice the
--- button started to look like a class icon -- the user saw a Blood Death Knight on the
--- minimap, not the addon. An addon's button has to say WHICH addon it is; which set is
--- active the window already says, with the check mark.
function Minimap_.Refresh()
    if not button then return end
    button.icon:SetTexture(ns.LOGO_MINIMAP)
end
