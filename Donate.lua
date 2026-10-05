-- RocketSwap | Donate.lua
-- The support line at the bottom of every window, the same in every Rocket addon: the "Donate"
-- link and, beside it, "Report a problem".
--
-- The user (26/09): *"tem vários addons que sempre tem algum menu nele em algum canto com link de
-- donate usando paypal"*, then *"vamos fazer sim"* -- knowing Blizzard's add-on policy (rule 5)
-- asks for donation requests to stay off the game; it is his call.
--
-- An addon cannot open a browser. So, as Baganator does (`Core/Dialogs.lua:40-70`), the link goes in
-- a box, already selected: Ctrl+C copies it, and the dialog closes by itself after the copy, as in
-- ArchonTooltip (`Utils.lua:225-260`). The box is the game's own popup (`StaticPopup` with an edit
-- box, reached through `GetEditBox()` in 12.x, as BugSack does).
--
-- Currency: BRL when the game is in Portuguese (Brazil), USD everywhere else (user's rule).
local ADDON, ns = ...
local L = ns.L

local BASE = "https://www.paypal.com/donate/?business=HH4PHH48DPG9J&no_recurring=0&currency_code="

function ns.DonateURL()
    local brl = GetLocale and GetLocale() == "ptBR"
    return BASE .. (brl and "BRL" or "USD")
end

---The box with a link in it, already selected: the addon's own (`Dialog.lua`), not the game's
---`StaticPopup` -- a game dialog opened by an addon marks the game's dialog code (05/10).
---Without the box (the game gave no shell), the link goes to the chat.
local function CopyBox(key, text, url)
    if ns.Dialog then
        local ok, shown = pcall(ns.Dialog.Show, key, text, { url = url })
        if ok and shown then return true end
    end
    ns.Print(url)
    return false
end

function ns.ShowDonate()
    CopyBox("donate",
        L["Thank you for supporting Rocket Swap! Press Ctrl+C to copy the link, then paste it in your browser."],
        ns.DonateURL())
end

--------------------------------------------------------------------------------
-- "Report a problem"
--------------------------------------------------------------------------------
-- (!) WHERE A PROBLEM IS REPORTED (asked on 27/09, asked again on 28/09). The user: *"nos addons
-- precisamos ter um lugar onde o usuário posso reportar um bug, que jogue para o cursefoge ou
-- github, o usuário escolhe, pode ficar junto com o apoiar projeto"*.
--
-- The places, in the order of the menu. GitHub takes it in the repository's issues. CurseForge
-- has no tracker of its own (looked at on 28/09: the project page has Description, Comments,
-- Files, Gallery and Relations, and its "Report" button reports the PROJECT to moderation): there
-- a problem is told in the comments.
--
ns.REPORT = {
    { name = "GitHub", url = "https://github.com/otaviohonorio/RocketSwap/issues" },
    { name = "CurseForge", url = "https://www.curseforge.com/wow/addons/rocketswap/comments" },
}

-- The place chosen, for the dialog that is open.
local reporting

---The addon's version, which is the first thing a report needs.
function ns.ReportVersion()
    local v = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version")
    return type(v) == "string" and v ~= "" and v or "?"
end

---The box with the link of one place, ready to copy.
function ns.ShowReport(site)
    if not site then return end
    reporting = site
    -- `|n` is the game's line break in a dialog definition; the box is ours and takes a real one.
    local texto = string.format(
        L["Rocket Swap %s — report a problem on %s.|n|nPress Ctrl+C to copy the link, then paste it in your browser. Say what you were doing and what happened."],
        ns.ReportVersion(), site.name)
    CopyBox("report", (texto:gsub("|n", "\n")), site.url or "")
end

---The player chooses where: the game's menu with the places. With one place only, or on a
---client without the menu, the box opens at once.
function ns.ReportMenu(owner)
    if #ns.REPORT < 2 or not (MenuUtil and MenuUtil.CreateContextMenu) then
        return ns.ShowReport(ns.REPORT[1])
    end
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle(L["Report a problem on"])
        for _, site in ipairs(ns.REPORT) do
            root:CreateButton(site.name, function() ns.ShowReport(site) end)
        end
    end)
end

--------------------------------------------------------------------------------
-- The links
--------------------------------------------------------------------------------
---THE DISCREET LINK (27/09). The user: *"os comandos não precisa (...) tem que ser na janela do addon
---mesmo, em algum canto ou menu (...) um pouco mais discreto sem chamar atenção"*. A small word in
---the game's disabled grey (`GameFontDisableSmall`) -- "Support the project", not
---"Donate" (the user, 27/09: *"doar é feio"*) -- that lights up on hover, with a tooltip saying
---what it does -- no button art, nothing competing with the addon's own controls.
---The PayPal monogram (27/09, the user: *"poderia ter um logo do paypal"*). A PNG in the addon's
---own `Textures/` -- the retail client loads PNG, as Details (`images/patreon_p_logo.png`) and
---KagrokLauncherCore (`Media/Social/patreon.png`) already ship. The glyph is simple-icons' `paypal`
---(CC0) in PayPal's two blues, rendered at 64x64.
ns.PAYPAL_ICON = "Interface\\AddOns\\" .. ADDON .. "\\Textures\\PayPal.png"
-- The game's own alert glyph (20x20 in the art, seen with `tools/ver_atlas.py`).
ns.REPORT_ICON = "gmchat-icon-alert"
local ICON = 14

---THE SUPPORT LINE (27/09), the standard for every Rocket window, current and future. The user:
---*"esse item tem que ser padrão em todos os addons atuais e futuros, deixa ele numa linha sozinho no
---final da janela"*. A line of its own at the very bottom, centred, below everything else: the
---window grows by `DONATE_ROW` and whatever lived at the bottom moves up by the same amount.
ns.DONATE_ROW = 22            -- 5 below + the 14 of the link + 3 above
local DONATE_Y = 5
-- Between the two links of the line: more than the 3 between a glyph and its word, so each
-- glyph reads as belonging to the word at its right.
local LINK_GAP = 18
ns.LINK_GAP = LINK_GAP

---A link of the support line: a glyph, a word in the game's grey, and a tooltip.
local function Link(parent, word, tip, icon, click)
    local b = CreateFrame("Button", nil, parent)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(ICON, ICON)
    b.icon:SetPoint("LEFT")
    icon(b.icon)
    b.icon:SetAlpha(0.8)                                 -- discreet until the mouse comes
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    b.text:SetPoint("LEFT", b.icon, "RIGHT", 3, 0)
    b.text:SetText(word)
    local w = b.text.GetStringWidth and b.text:GetStringWidth()
    if type(w) ~= "number" or w <= 0 then w = 30 end     -- by TYPE: the harness answers a table
    b.linkWidth = ICON + 3 + w + 4
    b:SetSize(b.linkWidth, ICON)
    b:SetScript("OnEnter", function(self)
        self.icon:SetAlpha(1)
        self.text:SetFontObject("GameFontHighlightSmall")
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(word, 1, 1, 1)
        GameTooltip:AddLine(tip, 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function(self)
        self.icon:SetAlpha(0.8)
        self.text:SetFontObject("GameFontDisableSmall")
        GameTooltip:Hide()
    end)
    b:SetScript("OnClick", click)
    return b
end

function ns.DonateLink(parent)
    return Link(parent, L["Support the project"], L["Opens the donation link, ready to copy."],
        function(icon) icon:SetTexture(ns.PAYPAL_ICON) end,
        function() ns.ShowDonate() end)
end

function ns.ReportLink(parent)
    return Link(parent, L["Report a problem"], L["Opens the address to report a problem, ready to copy."],
        function(icon) icon:SetAtlas(ns.REPORT_ICON) end,
        function(self) ns.ReportMenu(self) end)
end

---The support line at the bottom of `window` (see `DONATE_ROW`): the two links side by side,
---the PAIR centred. Every window uses this; `DonateLink` alone is for a place that is not a
---window (none today).
---@return table donate the support link; the report link is its `report`
function ns.DonateFooter(window)
    local b = ns.DonateLink(window)
    local r = ns.ReportLink(window)
    -- The middle of the pair on the middle of the window: the first link sits half of what is
    -- at its right to the left of it.
    b:SetPoint("BOTTOM", window, "BOTTOM", -(LINK_GAP + r.linkWidth) / 2, DONATE_Y)
    r:SetPoint("LEFT", b, "RIGHT", LINK_GAP, 0)
    b.report = r
    return b
end
