-- RocketSwap | UI.lua
-- A janela: lista de conjuntos à esquerda, editor à direita, estado embaixo.
--
-- DECISÕES DE APARÊNCIA, e de onde saíram:
--
-- * `PortraitFrameTemplate` (`SharedUIPanelTemplates.xml:631`). É a moldura que o próprio jogo
--   usa nas janelas de gerenciamento — retrato redondo, título, botão de fechar, borda
--   dourada. Sai de graça e é imediatamente familiar. Só se pode herdar template na CRIAÇÃO
--   do frame, nunca depois.
-- * `WowStyle1DropdownTemplate` (`Blizzard_AddOnList/AddonList.xml:126`) para os três combos.
--   É o dropdown atual; `UIDropDownMenuTemplate` é o legado e não combina com nada de 12.x.
--   A API é `dropdown:SetupMenu(function(dropdown, root) root:CreateRadio(...) end)`.
-- * Cada linha da lista é uma FAIXA com o ícone do conjunto de itens, não uma célula de
--   planilha: o ícone é o que o olho reconhece antes de ler.
-- * A linha do conjunto que já está aplicado ganha um realce e o botão vira um "✓" — sem
--   isso, "carregar" o que já está carregado é o clique mais comum e o mais inútil.
local ADDON, ns = ...
local L = ns.L

local UI = {}
ns.UI = UI

local WIDTH, HEIGHT = 640, 452
local LIST_WIDTH = 292
local ROW_HEIGHT = 54
local ROW_SPACING = 4
local VISIBLE_ROWS = 6
local SIDE = 14

local frame, rows, editor
local selected              -- índice do conjunto em edição
local scrollOffset = 0

local GOLD = { 1, 0.82, 0 }
local DIM = { 0.65, 0.66, 0.70 }

--------------------------------------------------------------------------------
local function Presets()
    return ns.db and ns.db.presets or {}
end

---Texto de apoio da linha: "Gélido · SBA ST · Frost". Só entra o que o conjunto define —
---um conjunto que não mexe em talentos não deve mentir que mexe.
local function Subtitle(preset)
    local parts = {}

    local spec = ns.Data.GetSpecByIndex(preset.spec)
    if spec then parts[#parts + 1] = spec.name end

    if preset.talent then
        local specID = spec and spec.id
        parts[#parts + 1] = ns.Data.LoadoutName(specID, preset.talent) or ("#" .. preset.talent)
    end

    if preset.gear then
        parts[#parts + 1] = ns.Data.GearSetName(preset.gear) or ("#" .. preset.gear)
    end

    return table.concat(parts, "  ·  ")
end

--------------------------------------------------------------------------------
-- Linhas
--------------------------------------------------------------------------------
local function BuildRow(index)
    local row = rows[index]
    if row then return row end

    row = CreateFrame("Button", nil, frame.list)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", frame.list, "TOPLEFT", 0, -((index - 1) * (ROW_HEIGHT + ROW_SPACING)))
    row:SetPoint("TOPRIGHT", frame.list, "TOPRIGHT", 0, -((index - 1) * (ROW_HEIGHT + ROW_SPACING)))

    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.bg:SetColorTexture(1, 1, 1, 0.04)

    row.selection = row:CreateTexture(nil, "BORDER")
    row.selection:SetAllPoints()
    row.selection:SetColorTexture(1, 0.82, 0, 0.12)
    row.selection:Hide()

    row:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
    local hl = row:GetHighlightTexture()
    hl:SetVertexColor(1, 1, 1, 0.07)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(38, 38)
    row.icon:SetPoint("LEFT", 8, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 10, -2)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    row.detail = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.detail:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 10, 3)
    row.detail:SetJustifyH("LEFT")
    row.detail:SetWordWrap(false)

    row.load = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.load:SetSize(78, 22)
    row.load:SetPoint("RIGHT", -8, 0)
    row.load:SetText(L["Load"])
    row.load:SetScript("OnClick", function(self)
        UI.Load(self:GetParent().presetIndex)
    end)

    -- O "já está" ocupa o mesmo lugar do botão: é a resposta para a pergunta que o botão faria.
    row.active = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.active:SetPoint("RIGHT", -18, 0)
    row.active:SetText("|cff40d878✓|r")
    row.active:Hide()

    row:SetScript("OnClick", function(self)
        selected = self.presetIndex
        UI.Refresh()
    end)

    rows[index] = row
    return row
end

--------------------------------------------------------------------------------
-- Editor
--------------------------------------------------------------------------------
---Um combo com rótulo em cima. `items()` devolve a lista; `get()`/`set()` leem e escrevem
---o valor no conjunto em edição.
local function BuildDropdown(parent, label, y, items, get, set)
    local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
    title:SetText(label)
    title:SetTextColor(unpack(GOLD))

    local dd = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
    dd:SetPoint("TOPLEFT", title, "BOTTOMLEFT", -2, -4)
    dd:SetWidth(parent:GetWidth())

    dd.Sync = function()
        local current = get()
        local text = L["(none)"]
        for _, item in ipairs(items()) do
            if item.value == current then text = item.text end
        end
        dd:SetDefaultText(text)

        dd:SetupMenu(function(_, root)
            root:CreateRadio(L["(none)"],
                function() return get() == nil end,
                function() set(nil); UI.Refresh() end)

            for _, item in ipairs(items()) do
                root:CreateRadio(item.text,
                    function() return get() == item.value end,
                    function() set(item.value); UI.Refresh() end)
            end
        end)
    end

    return dd
end

local function BuildEditor()
    editor = CreateFrame("Frame", nil, frame)
    editor:SetPoint("TOPLEFT", frame, "TOPLEFT", SIDE + LIST_WIDTH + 16, -64)
    editor:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -SIDE, 66)

    editor.title = editor:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    editor.title:SetPoint("TOPLEFT", 0, 0)
    editor.title:SetTextColor(unpack(GOLD))

    local nameLabel = editor:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameLabel:SetPoint("TOPLEFT", 0, -34)
    nameLabel:SetText(L["Name"])
    nameLabel:SetTextColor(unpack(GOLD))

    editor.name = CreateFrame("EditBox", nil, editor, "InputBoxTemplate")
    editor.name:SetPoint("TOPLEFT", nameLabel, "BOTTOMLEFT", 6, -4)
    editor.name:SetSize(240, 22)
    editor.name:SetAutoFocus(false)
    editor.name:SetScript("OnEscapePressed", editor.name.ClearFocus)
    editor.name:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        UI.Save()
    end)

    local function Current()
        return Presets()[selected]
    end

    editor.spec = BuildDropdown(editor, L["Specialization"], -92,
        function()
            local out = {}
            for _, s in ipairs(ns.Data.GetSpecs()) do
                out[#out + 1] = { value = s.index, text = s.name }
            end
            return out
        end,
        function() local p = Current(); return p and p.spec end,
        function(v) local p = Current(); if p then p.spec = v; p.talent = nil end end)

    -- Os talentos dependem da spec escolhida: trocar a spec zera o loadout (acima), porque
    -- um loadout de Gélido não existe em Profano e mostrá-lo seria oferecer o impossível.
    editor.talent = BuildDropdown(editor, L["Talents"], -152,
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

    editor.gear = BuildDropdown(editor, L["Gear"], -212,
        function()
            local out = {}
            for _, s in ipairs(ns.Data.GetGearSets()) do
                out[#out + 1] = { value = s.setID, text = s.name }
            end
            return out
        end,
        function() local p = Current(); return p and p.gear end,
        function(v) local p = Current(); if p then p.gear = v end end)

    editor.save = CreateFrame("Button", nil, editor, "UIPanelButtonTemplate")
    editor.save:SetSize(110, 22)
    editor.save:SetPoint("BOTTOMLEFT", 0, 0)
    editor.save:SetText(L["Save"])
    editor.save:SetScript("OnClick", function() UI.Save() end)

    editor.delete = CreateFrame("Button", nil, editor, "UIPanelButtonTemplate")
    editor.delete:SetSize(110, 22)
    editor.delete:SetPoint("BOTTOMLEFT", editor.save, "BOTTOMRIGHT", 8, 0)
    editor.delete:SetText(L["Delete"])
    editor.delete:SetScript("OnClick", function() UI.Delete() end)

    editor.empty = editor:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    editor.empty:SetPoint("TOPLEFT", 0, -40)
    editor.empty:SetWidth(editor:GetWidth())
    editor.empty:SetJustifyH("LEFT")
    editor.empty:SetText(L["Pick a preset"])
end

--------------------------------------------------------------------------------
local function Create()
    if frame then return frame end

    -- Herança de template só na criação — depois não dá.
    frame = CreateFrame("Frame", ADDON .. "Frame", UIParent, "PortraitFrameTemplate")
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("HIGH")
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

    if frame.SetTitle then frame:SetTitle(ADDON) end
    -- `SetPortraitToAsset` é o método do próprio `PortraitFrameMixin` (`PortraitFrame.lua:47`).
    -- Mexer em `frame.PortraitContainer.portrait` à mão funciona hoje e quebra quando a
    -- Blizzard reorganizar o template — e um addon instalado já guarda esta chamada assim.
    if frame.SetPortraitToAsset then
        frame:SetPortraitToAsset(ns.FirstIcon(ns.ICON_CANDIDATES))
    end
    tinsert(UISpecialFrames, frame:GetName())

    frame.listLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.listLabel:SetPoint("TOPLEFT", SIDE, -34)
    frame.listLabel:SetText(L["Presets"])
    frame.listLabel:SetTextColor(unpack(GOLD))

    frame.list = CreateFrame("Frame", nil, frame)
    frame.list:SetPoint("TOPLEFT", SIDE, -56)
    frame.list:SetSize(LIST_WIDTH, VISIBLE_ROWS * (ROW_HEIGHT + ROW_SPACING))

    -- Rolagem pela roda, sem barra: com poucos conjuntos a barra é moldura vazia.
    frame.list:EnableMouseWheel(true)
    frame.list:SetScript("OnMouseWheel", function(_, delta)
        local total = #Presets()
        local max = math.max(0, total - VISIBLE_ROWS)
        local wanted = scrollOffset - delta
        if wanted < 0 then wanted = 0 elseif wanted > max then wanted = max end
        if wanted ~= scrollOffset then
            scrollOffset = wanted
            UI.Refresh()
        end
    end)

    frame.empty = frame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    frame.empty:SetPoint("TOPLEFT", frame.list, "TOPLEFT", 4, -8)
    frame.empty:SetWidth(LIST_WIDTH - 8)
    frame.empty:SetJustifyH("LEFT")
    frame.empty:SetText(L["No presets yet."] .. "\n\n"
        .. L["Create one to switch spec, talents and gear with a single click."])

    frame.new = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.new:SetSize(LIST_WIDTH, 22)
    frame.new:SetPoint("TOPLEFT", frame.list, "BOTTOMLEFT", 0, -8)
    frame.new:SetText("+ " .. L["New preset"])
    frame.new:SetScript("OnClick", function() UI.New() end)

    -- Uma linha de estado embaixo, que é onde a corrente de passos se explica. Sem ela o
    -- clique em "Carregar" é um salto no escuro: a troca demora, e falha em silêncio.
    frame.status = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.status:SetPoint("BOTTOMLEFT", SIDE, 16)
    frame.status:SetPoint("BOTTOMRIGHT", -SIDE, 16)
    frame.status:SetJustifyH("LEFT")

    rows = {}
    BuildEditor()
    return frame
end

--------------------------------------------------------------------------------
function UI.SetStatus(text, isError)
    if not frame then return end
    frame.status:SetText(text or "")
    if isError then
        frame.status:SetTextColor(1, 0.5, 0.4)
    else
        frame.status:SetTextColor(0.75, 0.78, 0.82)
    end
end

function UI.Refresh()
    if not frame or not frame:IsShown() then return end

    local presets = Presets()
    local total = #presets

    local max = math.max(0, total - VISIBLE_ROWS)
    if scrollOffset > max then scrollOffset = max end

    frame.empty:SetShown(total == 0)

    for i = 1, VISIBLE_ROWS do
        local row = BuildRow(i)
        local preset = presets[scrollOffset + i]

        if not preset then
            row:Hide()
        else
            row.presetIndex = scrollOffset + i
            row.name:SetText(preset.name ~= "" and preset.name or L["Unnamed"])
            row.detail:SetText(Subtitle(preset))

            local _, icon = ns.Data.GearSetName(preset.gear)
            row.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")

            local loaded = ns.Data.IsLoaded(preset)
            row.active:SetShown(loaded)
            row.load:SetShown(not loaded)
            row.selection:SetShown(row.presetIndex == selected)
            row.name:SetTextColor(loaded and 1 or 0.95, loaded and 0.9 or 0.95, loaded and 0.6 or 0.95)
            row:Show()
        end
    end

    -- Editor
    local preset = presets[selected]
    local has = preset ~= nil

    editor.empty:SetShown(not has)
    editor.name:SetShown(has)
    editor.save:SetShown(has)
    editor.delete:SetShown(has)
    for _, dd in ipairs({ editor.spec, editor.talent, editor.gear }) do
        dd:SetShown(has)
        if has then dd.Sync() end
    end
    for _, fs in ipairs({ editor.title }) do
        fs:SetShown(has)
    end

    if has then
        editor.title:SetText(preset.name ~= "" and preset.name or L["Unnamed"])
        if not editor.name:HasFocus() then editor.name:SetText(preset.name or "") end
    end
end

--------------------------------------------------------------------------------
function UI.New()
    local presets = Presets()

    -- O novo conjunto já nasce com o que está valendo AGORA. É o caso de uso real: você
    -- acabou de arrumar a spec, os talentos e o equipamento para uma masmorra — agora só
    -- quer dar um nome a isso. Começar vazio obrigaria a redigitar o óbvio.
    local specIndex = ns.Data.GetCurrentSpecIndex()
    local spec = ns.Data.GetSpecByIndex(specIndex)

    presets[#presets + 1] = {
        name = "",
        spec = specIndex,
        talent = spec and ns.Data.GetActiveLoadoutID(spec.id) or nil,
        gear = ns.Data.GetEquippedSetID(),
    }

    selected = #presets
    scrollOffset = math.max(0, #presets - VISIBLE_ROWS)
    UI.Refresh()
    editor.name:SetFocus()
end

function UI.Save()
    local preset = Presets()[selected]
    if not preset then return end

    local name = editor.name:GetText()
    if not name or name:match("^%s*$") then
        UI.SetStatus(L["give the preset a name first."], true)
        return
    end

    preset.name = name:match("^%s*(.-)%s*$")
    UI.SetStatus(L["preset saved."], false)
    UI.Refresh()
end

function UI.Delete()
    if not Presets()[selected] then return end
    table.remove(Presets(), selected)
    selected = nil
    UI.SetStatus(L["preset deleted."], false)
    UI.Refresh()
end

function UI.Load(index)
    local preset = Presets()[index]
    if not preset then return end

    ns.db.last = preset.name
    ns.Data.Apply(preset, UI.SetStatus)
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
