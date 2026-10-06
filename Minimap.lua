-- RocketSwap | Minimap.lua
-- Botão no minimapa, sem biblioteca externa.
--
-- Por que não LibDBIcon: a lib resolve arrastar, salvar ângulo e integração com barras de
-- LDB. Aqui só o primeiro item importa, e ele cabe em 30 linhas — uma dependência que
-- precisa ser empacotada e atualizada não se paga por isso.
local ADDON, ns = ...
local L = ns.L

local Minimap_ = {}
ns.Minimap = Minimap_

local RADIUS = 80
local button

-- Candidatos de ícone, do preferido para o último recurso. Quem escolhe é o CLIENTE, via
-- `ns.FirstIcon` → `GetFileIDFromPath`: caminho de textura que não existe falha em silêncio,
-- e nome de ícone é justamente o que não dá para conferir em disco (as texturas moram no
-- CASC, não na pasta de addons).
--
-- O último da lista é o do RocketMeter — o único nome que eu SEI existir neste cliente,
-- porque o usuário o vê na lista de addons hoje. Se todos os outros falharem, cai nele.
--
-- `/rs icon` imprime quais resolveram: se você preferir outro, é trocar uma linha.
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
    button:SetPoint("CENTER", Minimap, "CENTER",
        math.cos(angle) * RADIUS, math.sin(angle) * RADIUS)
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
-- with an appearance, which is nearly all of them. No installed addon puts a secure button
-- inside the game's menu (searched), so the list is ours, each row a secure button with the
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

    -- O ícone É o conjunto que você está vestindo agora.
    --
    -- Dois motivos. O bom: o botão vira indicador — de relance dá para saber se está de Frost
    -- ou de PvP sem abrir nada, que é exatamente a informação que se perde. O honesto: nenhum
    -- nome de ícone bonito pôde ser CONFIRMADO em disco (o dump da Blizzard só entrega
    -- `INV_Misc_QuestionMark` e `INV_Misc_Coin_17`), e ícone inexistente falha em silêncio.
    -- O ícone do conjunto vem da API, então é sempre real.
    -- (!) THE GAME'S RING AND THE ICON, AT THE NUMBERS EVERY OTHER BUTTON USES (06/10). Reported
    -- with a screenshot: our drawing sat off-centre inside the gold ring. The button had the ring
    -- at 53 and the icon at 19, shifted (-1, 1) -- numbers of the OLD clients. On retail the
    -- minimap-button library the other addons ship (LibDBIcon-1.0, `WOW_PROJECT_MAINLINE`
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

    -- (!) O BOTAO DIREITO LISTA OS CONJUNTOS. ELE NAO TROCA NADA SOZINHO.
    --
    -- Ele chamava `ns.LoadLast()`, e um usuario reportou em video que o clique direito "trocava
    -- a spec sozinha". Estava certo, e o codigo fazia exatamente isso.
    --
    -- Dois motivos para tirar:
    --
    --   * BOTAO DIREITO EM ICONE DE MINIMAPA ABRE MENU. E a convencao do jogo inteiro, e e o
    --     que os outros dois addons Rocket fazem (nos dois, o direito abre as opcoes). Este era
    --     o unico que divergia -- e o unico em que a acao divergente era destrutiva. Quem clica
    --     esperando um menu leva uma troca de spec, talentos e itens.
    --   * A DICA NAO SALVA NINGUEM. Ela dizia "Right click: load the last preset", mas dica
    --     exige passar o mouse e ler, e ninguem le dica antes de clicar com o direito.
    --
    -- POR QUE ISSO NAO APARECIA AQUI: todos os conjuntos deste desenvolvedor tem aparencia, e
    -- conjunto com aparencia cai no ramo do `LoadPreset` que ABRE A JANELA em vez de aplicar.
    -- O dado dele impedia o defeito de acontecer. Os conjuntos do usuario que reportou nao tem
    -- aparencia, entao caiam direto no `Data.Apply`. Confirmado nos dois SavedVariables.
    button:SetScript("OnClick", function(self, mouseButton)
        if mouseButton == "RightButton" then
            Minimap_.Menu(self)
        else
            ns.UI.Toggle()
        end
    end)

    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(ns.TITLE, 1, 1, 1)
        GameTooltip:AddLine(L["Left click: open. Right click: pick a preset."],
            0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", GameTooltip_Hide)

    -- Arrastar: o ângulo sai da posição do cursor em relação ao centro do minimapa, o que
    -- faz o botão seguir a borda em vez de sair flutuando pela tela.
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

    Reposition()
    Minimap_.Refresh()
    return button
end

---Ícone do botão: FIXO e genérico.
---
---A primeira versão mostrava o ícone do conjunto vestido, com a ideia de virar indicador. Na
---prática o botão passou a parecer ícone de classe — o usuário viu um Cavaleiro da Morte
---Sangue no minimapa, não o addon. Botão de addon precisa dizer QUAL addon ele é; qual
---conjunto está ativo já é dito na janela, pelo ✓.
function Minimap_.Refresh()
    if not button then return end
    button.icon:SetTexture(ns.LOGO_MINIMAP)
end
