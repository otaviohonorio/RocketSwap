-- RocketSwap | UI.lua
-- A janela: lista de conjuntos à esquerda, editor à direita, estado no rodapé.
--
-- ESTE ARQUIVO FOI REESCRITO depois do primeiro teste in-game. O print mostrou três defeitos,
-- e os três vinham da mesma raiz: **eu ancorei conteúdo sem contar com a arte do template.**
-- A geometria abaixo foi medida no código-fonte da UI da Blizzard do 12.1.0, não estimada.
--
--   1. O RETRATO POR CIMA DO TEXTO. `PortraitFrameTemplate` desenha um disco de Ø58 com
--      centro em (26, −22) do frame. O rótulo "Conjuntos" estava em (14, −34), a
--      sqrt(12² + 12²) = 17px do centro — ou seja, 12px DENTRO do disco.
--      REGRA: nada ancorado em `frame` com x < 58 e y > −55. Nada aqui viola isso.
--
--   2. RÓTULOS ÓRFÃOS. Com zero conjuntos, "Nome / Especialização / Talentos / Itens"
--      apareciam sem campo embaixo: eu escondia os controles e esquecia os rótulos.
--      A correção não é um `SetShown` a mais — é que **o estado "nada selecionado" deixou de
--      existir**: com ≥1 conjunto, a lista seleciona o primeiro sozinha. Precedente da
--      Blizzard: `ClickBindingFrameMixin:OnShow` foca o primeiro item.
--      E cada rótulo agora vive DENTRO do seu grupo — esconder o grupo esconde os dois.
--
--   3. JANELA VAZIA. 640×452 para 2 a 5 conjuntos. Agora 520×320, derivado do conteúdo, e o
--      estado vazio é um bloco centralizado com uma frase e um botão.
--
-- O TEMPLATE MUDOU para `ButtonFrameTemplate`: é o `PortraitFrameTemplate` mais um `Inset` já
-- posicionado nos offsets oficiais (`PANEL_INSET_*` em `SharedUIPanelTemplates.lua:4-9`).
-- Ancorar na área rebaixada em vez de no frame cru torna o bug 1 impossível de repetir.
local ADDON, ns = ...
local L = ns.L

local UI = {}
ns.UI = UI

-- Todos os números têm origem. Onde há citação, ela é de arquivo do cliente 12.1.0.
local WIDTH, HEIGHT = 520, 370
local LIST_W = 260            -- largura externa do inset da lista: x 4..264
local GUTTER = 20             -- calha entre colunas (MountJournal)
local COL_X = 284             -- borda esquerda da ARTE da coluna direita
local ROW_HEIGHT = 44         -- GearSetButtonTemplate: a lista de conjuntos da própria Blizzard
local ROW_SPACING = 2
local FIELD_W = 200           -- combos (o dropdown de loadout de talentos usa 200)
local NAME_W = 211            -- EditBox: a arte termina em 500, alinhada com a dos combos
local GROUP_STEP = 50         -- rótulo (15) + combo (25) + respiro (10)
local ATTIC_Y = -30           -- faixa entre o título e o inset

local frame, editor, selection

-- O conjunto em edição, guardado AQUI e não perguntado ao ScrollBox.
--
-- Dois motivos, os dois descobertos no primeiro teste in-game:
--
--   1. `SelectionBehaviorMixin:GetSelectedElementData()` devolve uma **LISTA**, não um
--      elemento (`ScrollUtil.lua:434`). Uma lista vazia é VERDADEIRA em Lua, então o editor
--      achava que havia um conjunto selecionado — um conjunto sem spec, sem talentos e sem
--      itens. Era isso o "combo de talentos não traz nada": sem spec, `GetLoadouts(nil)`
--      devolve lista vazia. E era isso o "a deleção não funcionou": `UI.Delete` procurava
--      uma tabela vazia na lista e não achava.
--   2. `SetDataProvider` **apaga a seleção** (`OnScrollBoxDataProviderReassigned`,
--      `ScrollUtil.lua:413`). Sem guardar por fora, qualquer troca de equipamento no jogo
--      redesenharia a lista e jogaria a seleção de volta para o primeiro conjunto.
local current

--------------------------------------------------------------------------------
local function Presets()
    return ns.db and ns.db.presets or {}
end

---Texto de apoio da linha: "Gélido · SBA ST · Frost". Só entra o que o conjunto define — um
---conjunto que não mexe em talentos não deve dar a entender que mexe.
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
---Monta a linha uma vez. O ScrollBox reaproveita o mesmo frame para dados diferentes, então
---tudo que depende do conjunto vai em `Fill`, não aqui.
local function BuildRow(row)
    if row.built then return end
    row.built = true

    row:SetHeight(ROW_HEIGHT)

    -- Sem fundo próprio: quem dá o fundo é o mármore do inset. A linha só se pinta quando
    -- está sob o mouse ou selecionada — o padrão do painel de Opções do jogo.
    --
    -- Os alfas antigos (0.12 na seleção, 0.07 no hover) eram 3 a 6× mais fracos que o nativo
    -- e sem `ADD`: era por isso que a seleção não aparecia. Estas duas texturas e estes
    -- números são copiados do `GearSetButtonTemplate`, que é a lista de conjuntos de itens
    -- da própria Blizzard. `TexCoord 0.2..0.8` corta as pontas para esticar sem deformar.
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
    row.icon:SetSize(36, 36)
    row.icon:SetPoint("LEFT", 4, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.name:SetPoint("TOPLEFT", 44, -8)
    row.name:SetPoint("RIGHT", row, "RIGHT", -86, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    row.detail = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.detail:SetPoint("BOTTOMLEFT", 44, 8)
    row.detail:SetPoint("RIGHT", row, "RIGHT", -86, 0)
    row.detail:SetJustifyH("LEFT")
    row.detail:SetWordWrap(false)

    -- O botão e o ✓ dividem o mesmo slot: a linha não reflui quando o conjunto passa a
    -- estar aplicado, porque o texto reserva os 86px dos dois jeitos.
    row.load = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.load:SetSize(74, 22)
    row.load:SetPoint("RIGHT", -6, 0)
    row.load:SetText(L["Load"])
    row.load:SetScript("OnClick", function(self)
        UI.Load(self:GetParent().preset)
    end)

    row.check = row:CreateTexture(nil, "OVERLAY")
    row.check:SetSize(16, 16)
    row.check:SetPoint("RIGHT", -8, 0)
    row.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    row.check:Hide()

    -- O CLIQUE DA LINHA. Ele não existia: eu troquei o `OnClick` manual pelo
    -- `AddSelectionBehavior` achando que o comportamento também capturava o clique. Ele só
    -- gerencia o ESTADO da seleção — quem seleciona é quem clica. Era o "não consigo clicar
    -- em outros conjuntos".
    row:RegisterForClicks("LeftButtonUp")
    row:SetScript("OnClick", function(self)
        if selection and self.GetElementData then
            selection:Select(self)
        end
    end)

    row:SetScript("OnEnter", function(self)
        if not self.preset then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.preset.name ~= "" and self.preset.name or L["Unnamed"], 1, 1, 1)
        GameTooltip:AddLine(Subtitle(self.preset), 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", GameTooltip_Hide)
end

---Preenche a linha com um conjunto.
local function FillRow(row, preset)
    BuildRow(row)
    row.preset = preset

    row.name:SetText(preset.name ~= "" and preset.name or L["Unnamed"])
    row.detail:SetText(Subtitle(preset))

    local _, icon = ns.Data.GearSetName(preset.gear)
    row.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")

    -- UM canal por fato: a barra dourada diz "selecionado", o slot do botão diz "aplicado".
    -- A versão anterior também tingia o nome, e dourado-contra-quase-branco é distinção que
    -- ninguém lê — dois sinais para o mesmo fato brigando com a barra de seleção.
    local loaded = ns.Data.IsLoaded(preset)
    row.check:SetShown(loaded)
    row.load:SetShown(not loaded)

    row.selected:SetShown(selection ~= nil and selection:IsElementDataSelected(preset))
end

--------------------------------------------------------------------------------
-- Os campos do editor
--------------------------------------------------------------------------------
---Rótulo + combo num CONTÊINER. Esconder o grupo esconde os dois — é o que impede o rótulo
---órfão de voltar no próximo campo que alguém acrescentar.
---
---O rótulo assenta pelo rodapé no topo do combo, +3: assim ele não depende do corpo da fonte.
local function Group(parent, labelText, yTop, items, get, set)
    local group = CreateFrame("Frame", nil, parent)
    group:SetSize(216, 40)
    group:SetPoint("TOPLEFT", parent, "TOPLEFT", COL_X, yTop)

    -- +8 compensa o transbordo da arte do combo, para ela cair exatamente na coluna.
    local dd = CreateFrame("DropdownButton", nil, group, "WowStyle1DropdownTemplate")
    dd:SetSize(FIELD_W, 25)
    dd:SetPoint("BOTTOMLEFT", group, "BOTTOMLEFT", 8, 0)

    local label = group:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    label:SetPoint("BOTTOMLEFT", dd, "TOPLEFT", 3, 3)
    label:SetJustifyH("LEFT")
    label:SetText(labelText)

    ---Regenera o menu a partir do estado atual.
    ---
    ---`SetDefaultText` é só para "nada selecionado" — a marca do item escolhido sai de graça
    ---do `IsSelected` do `CreateRadio`. A versão anterior usava o default como "texto do
    ---selecionado", que é o que o comentário da própria Blizzard desaconselha.
    function group.Sync()
        local list = items()

        dd:SetupMenu(function(_, root)
            root:CreateButton(L["(none)"], function() set(nil); UI.AfterEdit() end)
            if #list > 0 then root:CreateDivider() end

            for _, item in ipairs(list) do
                local entry = root:CreateRadio(item.text,
                    function() return get() == item.value end,
                    function() set(item.value); UI.AfterEdit() end,
                    item.value)

                -- O conjunto de itens já tem ícone; mostrá-lo no menu custa cinco linhas e
                -- é o que faz escolher "Frost" sem ler.
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

            -- Sem nada para escolher, o combo fica apagado em vez de abrir um menu de um
            -- item só — o caso real de uma spec sem loadout salvo.
            if root.HasElements then dd:SetEnabled(root:HasElements()) end
        end)

        local current, text = get(), nil
        for _, item in ipairs(list) do
            if item.value == current then text = item.text end
        end
        dd:SetDefaultText(text or L["(none)"])
    end

    group.dropdown = dd
    return group
end

local function BuildEditor()
    editor = {}

    -- O nome NÃO tem rótulo separado: a instrução mora dentro da caixa. Era metade do
    -- "texto colado", resolvida pela raiz em vez de por um `SetShown`.
    editor.name = CreateFrame("EditBox", nil, frame, "InputBoxInstructionsTemplate")
    editor.name:SetSize(NAME_W, 22)
    editor.name:SetPoint("TOPLEFT", frame, "TOPLEFT", COL_X + 5, -60)
    editor.name:SetAutoFocus(false)
    editor.name:SetMaxLetters(31)
    if editor.name.Instructions then
        -- Sem isto o texto de instrução nasce 16px à direita do texto digitado.
        editor.name.Instructions:SetAllPoints()
        editor.name.Instructions:SetText(L["Preset name"])
    end
    editor.name:SetScript("OnEscapePressed", editor.name.ClearFocus)
    editor.name:SetScript("OnEnterPressed", editor.name.ClearFocus)
    -- Sair da caixa salva. O botão "Salvar" foi embora: os combos já escrevem direto no
    -- conjunto, então ele só confirmava o nome — e sua existência levantava a dúvida "a
    -- escolha do combo salvou?".
    editor.name:SetScript("OnEditFocusLost", function() UI.SaveName() end)

    editor.divider = frame:CreateTexture(nil, "ARTWORK")
    editor.divider:SetSize(216, 1)
    editor.divider:SetPoint("TOPLEFT", frame, "TOPLEFT", COL_X, -98)
    if not ns.SetAtlasSafe or not ns.SetAtlasSafe(editor.divider, "Options_HorizontalDivider") then
        editor.divider:SetColorTexture(1, 1, 1, 0.12)
    end

    local function Current() return UI.Selected() end

    editor.spec = Group(frame, L["Specialization"], -108,
        function()
            local out = {}
            for _, s in ipairs(ns.Data.GetSpecs()) do
                out[#out + 1] = { value = s.index, text = s.name, icon = s.icon }
            end
            return out
        end,
        function() local p = Current(); return p and p.spec end,
        -- Trocar a spec zera o loadout: um loadout de Gélido não existe em Profano, e
        -- oferecê-lo seria oferecer o impossível.
        function(v) local p = Current(); if p then p.spec = v; p.talent = nil end end)

    editor.talent = Group(frame, L["Talents"], -108 - GROUP_STEP,
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

    editor.gear = Group(frame, L["Gear"], -108 - GROUP_STEP * 2,
        function()
            local out = {}
            for _, s in ipairs(ns.Data.GetGearSets()) do
                out[#out + 1] = { value = s.setID, text = s.name, icon = s.icon }
            end
            return out
        end,
        function() local p = Current(); return p and p.gear end,
        function(v) local p = Current(); if p then p.gear = v end end)

    -- Aparência é OPCIONAL de propósito: deixar em "(nenhum)" faz o conjunto não mexer na
    -- roupa. Quem não usa transmog nem percebe que o campo existe.
    editor.transmog = Group(frame, L["Appearance"], -108 - GROUP_STEP * 3,
        function()
            local out = {}
            for _, o in ipairs(ns.Data.GetOutfits()) do
                out[#out + 1] = { value = o.outfitID, text = o.name, icon = o.icon }
            end
            return out
        end,
        function() local p = Current(); return p and p.transmog end,
        function(v) local p = Current(); if p then p.transmog = v end end)
end

--------------------------------------------------------------------------------
-- Estado vazio
--------------------------------------------------------------------------------
---Bloco centralizado. A Blizzard não tem tela de vazio com arte: em ~20 sistemas o padrão é
---uma FontString centralizada mais, quando há o que fazer, um botão.
---
---O texto responde à pergunta que o botão levanta ("vou ter que preencher tudo?"), em vez de
---descrever o produto. E a resposta é verdade no código: `UI.New` já nasce preenchido.
local function BuildEmptyState()
    local empty = CreateFrame("Frame", nil, frame)
    empty:SetAllPoints()

    empty.title = empty:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    empty.title:SetPoint("CENTER", frame, "CENTER", 0, 45)
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
local function Create()
    if frame then return frame end

    -- Herança de template só na criação.
    frame = CreateFrame("Frame", ADDON .. "Frame", UIParent, "ButtonFrameTemplate")
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
    if frame.SetPortraitToAsset then
        frame:SetPortraitToAsset(ns.FirstIcon(ns.ICON_CANDIDATES))
    end
    tinsert(UISpecialFrames, frame:GetName())

    -- O inset do template cobre a largura toda; aqui ele passa a cobrir só a coluna da lista.
    -- A coluna direita fica sobre o fundo da janela de propósito: o mármore do inset é fundo
    -- de LISTA, e sob um formulário ele compete com a arte dos combos.
    if frame.Inset then
        frame.Inset:ClearAllPoints()
        frame.Inset:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -60)
        frame.Inset:SetPoint("BOTTOMRIGHT", frame, "TOPLEFT", 4 + LIST_W, -(HEIGHT - 26))
    end
    local host = frame.Inset or frame

    -- Sem rótulo "Conjuntos": o inset já delimita a lista, e era justamente esse rótulo que
    -- estava embaixo do retrato.
    frame.list = CreateFrame("Frame", nil, host, "WowScrollBoxList")
    frame.listBar = CreateFrame("EventFrame", nil, host, "MinimalScrollBar")
    frame.listBar:SetPoint("TOPRIGHT", host, "TOPRIGHT", -3, -3)
    frame.listBar:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -3, 3)

    local view = CreateScrollBoxListLinearView(0, 0, 0, 0, ROW_SPACING)
    view:SetVirtualized(false)          -- 2 a 5 itens: cria todos, não recicla
    view:SetElementExtent(ROW_HEIGHT)   -- obrigatório com o tipo nativo "Button"
    view:SetElementInitializer("Button", FillRow)
    ScrollUtil.InitScrollBoxListWithScrollBar(frame.list, frame.listBar, view)

    ScrollUtil.AddManagedScrollBarVisibilityBehavior(frame.list, frame.listBar,
        { CreateAnchor("TOPLEFT", host, "TOPLEFT", 3, -3),
          CreateAnchor("BOTTOMRIGHT", host, "BOTTOMRIGHT", -17, 3) },
        { CreateAnchor("TOPLEFT", host, "TOPLEFT", 3, -3),
          CreateAnchor("BOTTOMRIGHT", host, "BOTTOMRIGHT", -3, 3) })

    -- A seleção guarda a TABELA do conjunto, não o índice. Com índice, `table.remove` no
    -- Apagar deslocava tudo e a seleção passava a apontar para outro conjunto.
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

    -- Sótão: a faixa entre o título e o inset, à direita do retrato (x ≥ 58).
    frame.new = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.new:SetSize(140, 22)
    frame.new:SetPoint("TOPLEFT", frame, "TOPLEFT", 60, ATTIC_Y)
    frame.new:SetText("+ " .. L["New preset"])
    frame.new:SetScript("OnClick", function() UI.New() end)

    -- Rodapé: a banda que o template já reserva (y 4..26).
    frame.delete = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.delete:SetSize(100, 22)
    frame.delete:SetPoint("BOTTOMRIGHT", -6, 4)
    frame.delete:SetText(L["Delete"])
    frame.delete:SetScript("OnClick", function() UI.Delete() end)

    frame.status = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.status:SetPoint("BOTTOMLEFT", 10, 8)
    frame.status:SetPoint("RIGHT", frame.delete, "LEFT", -8, 0)
    frame.status:SetJustifyH("LEFT")
    frame.status:SetWordWrap(false)

    BuildEditor()
    BuildEmptyState()
    return frame
end

--------------------------------------------------------------------------------
---O conjunto em edição. É a TABELA do conjunto, não um índice — `table.remove` no Apagar
---desloca os índices, e um índice guardado passaria a apontar para outro conjunto.
---Acesso à lista, só para o harness poder disparar o clique de uma linha. Sem isto o teste
---que trava o bug "não consigo clicar em outros conjuntos" não teria como existir.
function UI.DebugList()
    return frame and frame.list
end

function UI.Selected()
    return current
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

---Só o editor. Chamado quando a seleção muda ou quando um combo escreve.
function UI.RefreshEditor()
    if not frame or not editor then return end

    local preset = UI.Selected()
    local has = preset ~= nil

    editor.name:SetShown(has)
    for _, group in ipairs({ editor.spec, editor.talent, editor.gear, editor.transmog }) do
        -- `SetupMenu` só gera o menu com o frame visível: mostrar ANTES de sincronizar.
        group:SetShown(has)
        if has then group.Sync() end
    end
    editor.divider:SetShown(has)

    if has and not editor.name:HasFocus() then
        editor.name:SetText(preset.name or "")
        if editor.name.Instructions and InputBoxInstructions_OnTextChanged then
            InputBoxInstructions_OnTextChanged(editor.name)
        end
    end
end

function UI.Refresh()
    if not frame or not frame:IsShown() then return end

    local presets = Presets()
    local total = #presets
    local empty = total == 0

    frame.emptyState:SetShown(empty)
    if frame.Inset then frame.Inset:SetShown(not empty) end
    frame.list:SetShown(not empty)
    frame.new:SetShown(not empty)
    frame.delete:SetShown(not empty)

    if empty then
        editor.name:Hide()
        editor.divider:Hide()
        for _, group in ipairs({ editor.spec, editor.talent, editor.gear, editor.transmog }) do
            group:Hide()
        end
        return
    end

    -- `SetDataProvider` apaga a seleção do comportamento; por isso o conjunto corrente é
    -- guardado por fora e reancorado logo abaixo.
    local wanted = current
    frame.list:SetDataProvider(CreateDataProvider(presets), true)

    local stillThere = false
    for i = 1, total do
        if presets[i] == wanted then stillThere = true end
    end

    -- Seleção automática: é isto que faz o estado "nada selecionado" não existir, e com ele
    -- os rótulos órfãos e o texto colado. Não é um remendo — é a remoção do estado.
    selection:SelectElementData(stillThere and wanted or presets[1])

    UI.RefreshEditor()
end

---Depois de mexer num combo: o texto da linha mudou, a quantidade não. Reinicializar é mais
---barato que trocar o data provider, e não perde a rolagem.
function UI.AfterEdit()
    if frame and frame.list and frame.list.ReinitializeFrames then
        frame.list:ReinitializeFrames()
    end
    UI.RefreshEditor()
end

--------------------------------------------------------------------------------
function UI.New()
    local presets = Presets()

    -- O conjunto novo já nasce com o que está valendo AGORA. É o caso de uso real: você
    -- acabou de arrumar spec, talentos e equipamento para uma masmorra — agora só quer dar
    -- um nome a isso. Começar vazio obrigaria a redigitar o óbvio.
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

function UI.SaveName()
    local preset = UI.Selected()
    if not preset then return end

    local name = editor.name:GetText() or ""
    name = name:match("^%s*(.-)%s*$")
    if name == preset.name then return end

    preset.name = name
    UI.AfterEdit()
end

function UI.Delete()
    local preset = UI.Selected()
    if not preset then return end

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

function UI.Load(preset)
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
