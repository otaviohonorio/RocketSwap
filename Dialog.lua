-- RocketSwap | Dialog.lua
-- The addon's own notice box: a text and a button, or a text and a link to copy.
--
-- (!) WHY THE ADDON DOES NOT USE THE GAME'S `StaticPopup_Show` (05/10/2026).
--
-- Reported by a player, and recorded by the game on the development machine too:
-- "[ADDON_ACTION_FORBIDDEN] AddOn 'RocketSwap' tried to call the protected function
-- 'IsUserOAuthed()'", with not one line of this addon in the stack -- the whole of it is the
-- game's guild control window answering an event.
--
-- The game keeps ONE list of the dialogs on screen (`shownDialogFrames`, StaticPopup.lua), and
-- a dialog opened by an addon goes into it by the addon's hand. From then on, whoever walks
-- that list is marked by the addon -- the client says so itself, in the comment above
-- `StaticPopup_CollapseTable` -- and the game walks it all the time (`StaticPopup_Hide`,
-- `StaticPopup_Visible`, `StaticPopup_FindVisible`). The guild control window calls
-- `StaticPopup_Hide` and, right after, `C_Discord.IsUserOAuthed()`, which is protected: with a
-- box of ours on screen, the game refuses its own call and blames this addon.
--
-- Measured, not guessed: the game recorded the error at 19:46:24, and the diary of the same
-- session has this addon's box shown at 19:46:19 and hidden at 19:46:28.
--
-- So the box is a frame of OURS, which never enters that list. It is drawn with the game's own
-- dialog shell (`StaticPopupBaseTemplate`: the border and the dark background of every dialog
-- of the game, GameDialog.xml), the game's button and the game's edit box, at the game's
-- measures. The harness has the guard: no file of the addon may call `StaticPopup_Show`.
local ADDON, ns = ...
local L = ns.L

local Dialog = {}
ns.Dialog = Dialog

-- The game's numbers (client 12.1.0): the dialog is 320 wide and its text 290
-- (GameDialog.xml:52, GameDialog.lua:558); a dialog with a box of 350 is 320 + (350 - 260)
-- (Mainline/GameDialog.lua, `GetInitialWidth`); the first line starts 16 below the top
-- (GameDialog.xml:89); the button is 128 wide (GameDialog.xml:4) and 22 tall
-- (`UIPanelButtonTemplate`); the box sits 45 above the bottom (GameDialog.xml:210); and the
-- first dialog of the game hangs 135 below the top of the screen (GameDialog.xml:336).
local WIDTH, TEXT_WIDTH = 320, 290
local BOX_WIDTH = 350
local WIDE = WIDTH + (BOX_WIDTH - 260)
local TOP, GAP, BOTTOM = 16, 16, 16
local BUTTON_WIDTH, BUTTON_HEIGHT = 128, 22
local BOX_HEIGHT, BOX_FROM_BOTTOM = 20, 45
local FROM_SCREEN_TOP = 135
local NAME = "RocketSwapDialog"

Dialog.MEASURES = { width = WIDTH, wide = WIDE, textWidth = TEXT_WIDTH, top = TOP, gap = GAP,
    bottom = BOTTOM, buttonWidth = BUTTON_WIDTH, buttonHeight = BUTTON_HEIGHT,
    boxWidth = BOX_WIDTH, boxHeight = BOX_HEIGHT, boxFromBottom = BOX_FROM_BOTTOM }

local frame
local current      -- the key of what is on screen
local link         -- the link in the box, while one is shown
local failed       -- the game refused the shell once: do not ask again this session

local function Build()
    if frame or failed then return frame end
    -- The shell is the game's. Without it there is no box at all (the callers fall back to the
    -- chat): a panel painted by hand is what the skin rule forbids.
    local ok, f = pcall(CreateFrame, "Frame", NAME, UIParent, "StaticPopupBaseTemplate")
    if not ok or not f then
        failed = true
        return nil
    end
    -- The shell is born taking the keyboard (the game's dialogs handle keys themselves); ours
    -- handles none, and a frame that takes the keyboard and does nothing with it eats every key.
    f:EnableKeyboard(false)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:Hide()

    f.text = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    f.text:SetPoint("TOP", 0, -TOP)
    f.text:SetWidth(TEXT_WIDTH)

    f.button = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.button:SetSize(BUTTON_WIDTH, BUTTON_HEIGHT)
    f.button:SetPoint("BOTTOM", 0, BOTTOM)
    f.button:SetScript("OnClick", function() f:Hide() end)

    f.box = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    f.box:SetSize(BOX_WIDTH, BOX_HEIGHT)
    f.box:SetPoint("BOTTOM", 0, BOX_FROM_BOTTOM)
    f.box:SetAutoFocus(false)
    f.box:Hide()
    f.box:SetScript("OnEscapePressed", function() f:Hide() end)
    f.box:SetScript("OnEnterPressed", function() f:Hide() end)
    f.box:SetScript("OnKeyDown", function(_, key)
        if key == "C" and IsControlKeyDown and IsControlKeyDown() then
            C_Timer.After(0.1, function()
                if frame and frame:IsShown() and link then
                    frame:Hide()
                    ns.Print(L["Link copied — paste it in your browser."])
                end
            end)
        end
    end)
    -- Typing over it would lose the link: whatever is typed, the link comes back.
    f.box:SetScript("OnTextChanged", function(b, userInput)
        if userInput and link then
            b:SetText(link)
            b:HighlightText()
        end
    end)

    f:SetScript("OnHide", function()
        current, link = nil, nil
    end)

    -- Esc closes, as in every box of the game.
    if UISpecialFrames and tinsert then tinsert(UISpecialFrames, NAME) end

    frame = f
    return f
end

---Where the box hangs: where the game's first dialog does, or under the game's dialogs when
---some are on screen. Their frames are only READ (shown or not, and where the bottom is).
local function Place(f)
    f:ClearAllPoints()
    local lowest, lowestBottom
    for i = 1, 4 do
        local g = _G["StaticPopup" .. i]
        if type(g) == "table" and g.IsShown and g:IsShown() and g.GetBottom then
            local b = g:GetBottom()
            if type(b) == "number" and (not lowestBottom or b < lowestBottom) then
                lowest, lowestBottom = g, b
            end
        end
    end
    if lowest then
        f:SetPoint("TOP", lowest, "BOTTOM", 0, 0)
    else
        f:SetPoint("TOP", UIParent, "TOP", 0, -FROM_SCREEN_TOP)
    end
end

---Shows the box.
---@param key string what this box is ("summary", "donate", "report"): `Hide(key)` closes only it
---@param text string what it says
---@param opts table|nil `url`: a link to put in the box, selected, ready to copy; `button`: the button's text
---@return boolean shown false when the game gave no shell: the caller says it some other way
function Dialog.Show(key, text, opts)
    local f = Build()
    if not f then return false end
    opts = opts or {}

    local url = type(opts.url) == "string" and opts.url or nil
    local width = url and WIDE or WIDTH
    f:SetWidth(width)
    f.text:SetWidth(width - (WIDTH - TEXT_WIDTH))
    f.text:SetText(text or "")
    f.button:SetText(opts.button or (url and CLOSE) or OKAY)

    local textHeight = f.text:GetStringHeight() or 0
    if url then
        -- text, the box, the button: the box 45 above the bottom, as in the game's dialogs.
        f:SetHeight(TOP + textHeight + GAP + BOX_HEIGHT + BOX_FROM_BOTTOM)
        f.box:Show()
    else
        f:SetHeight(TOP + textHeight + GAP + BUTTON_HEIGHT + BOTTOM)
        f.box:Hide()
    end

    current, link = key, url
    Place(f)
    f:Show()
    f:Raise()
    if url then
        f.box:SetText(url)
        f.box:HighlightText()
        f.box:SetFocus()
    end
    if PlaySound and SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPEN then
        pcall(PlaySound, SOUNDKIT.IG_MAINMENU_OPEN)
    end
    return true
end

---Closes the box, when it is the one named (or whatever is shown, with no name).
function Dialog.Hide(key)
    if frame and frame:IsShown() and (key == nil or key == current) then
        frame:Hide()
        return true
    end
    return false
end

---Is the box named on screen? (With no name: is any?)
function Dialog.IsShown(key)
    return frame ~= nil and frame:IsShown() and (key == nil or key == current)
end

-- For the harness.
function Dialog.__frame() return frame end
function Dialog.__current() return current end
function Dialog.__reset()
    if frame then frame:Hide() end
    frame, current, link, failed = nil, nil, nil, nil
end
