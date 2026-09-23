-- RocketSwap | tests/harness.lua
-- Simulador mínimo da API do WoW, para rodar o addon fora do jogo.
--
--   luajit tests/harness.lua        (da pasta do addon)
--
-- Não substitui o teste in-game: não desenha nada e os dados são falsos. Serve para pegar o
-- que quebra no carregamento — nil indexado, função que não existe, evento que estoura — e
-- para travar a lógica da corrente de aplicação, que é a parte que mais fácil quebra em
-- silêncio. Este arquivo NÃO entra no .toc.
local ADDON = "RocketSwap"

--------------------------------------------------------------------------------
-- Widget genérico: qualquer método PascalCase vira no-op que devolve outro widget.
--------------------------------------------------------------------------------
local function widget(kind)
    local self = { __kind = kind, __scripts = {}, __events = {} }

    -- A GEOMETRIA FICA GUARDADA. `SetPoint` e `SetSize` caiam no no-op do metatable, entao a
    -- skill `wow-ui-design` (secao "isto se testa fora do jogo") era impossivel de cumprir aqui:
    -- nao havia como perguntar onde uma coisa foi parar. E o proprio texto dela avisa que medir
    -- so `x` e `width` deixou TRES reprovacoes verticais passarem -- todas colisao de altura.
    self.__points = {}
    function self.SetPoint(_, ...) self.__points[#self.__points + 1] = { ... } end
    function self.ClearAllPoints() self.__points = {} end
    function self.SetHeight(_, h) self.__h = h end
    function self.SetWidth(_, w) self.__w = w end
    function self.SetSize(_, w, h) self.__w, self.__h = w, h end

    ---O deslocamento de uma ancora, pelo canto que ela prende. Devolve x, y.
    function self.PointOffset(_, corner)
        for _, pt in ipairs(self.__points) do
            if pt[1] == corner then
                -- AS DUAS FORMAS DE `SetPoint`, e so a longa era entendida:
                -- `("TOPLEFT", pai, "TOPLEFT", x, y)` e `("TOPLEFT", x, y)`. Na forma curta o
                -- stub devolvia nil, nil -- e um check de posicao comparando nil com nil passa
                -- sem medir nada. As caixas da faixa de avisos usam a curta.
                if type(pt[2]) == "number" then return pt[2], pt[3] end
                return pt[4], pt[5]
            end
        end
    end

    function self.SetScript(_, name, fn) self.__scripts[name] = fn end
    function self.GetScript(_, name) return self.__scripts[name] end
    function self.RegisterEvent(_, event) self.__events[event] = true end
    function self.CreateFontString(_, _, template)
        local fs = widget("FontString")
        fs.__hasFont = template ~= nil
        function fs.SetFont() fs.__hasFont = true end
        -- A FONTSTRING GUARDA O QUE ESCREVERAM NELA. Sem isto o `GetText` do widget generico
        -- devolvia sempre "" -- e todo teste que perguntasse "o que apareceu na tela?" comparava
        -- vazio com vazio e passava. O rotulo do passo PULADO, que existe justamente para nao
        -- ser confundido com um passo que nao comecou, seria invisivel ao harness.
        function fs.SetText(_, text, ...)
            if not fs.__hasFont then error("FontString:SetText(): Font not set", 2) end
            fs.__text = text
            return text, ...
        end
        function fs.HasFocus() return false end
        -- Quebra de linha e decisao de layout, e o painel de progresso depende dela.
        function fs.SetWordWrap(_, v) fs.__wordWrap = v end
        return fs
    end
    -- A TEXTURA GUARDA O ATLAS QUE RECEBEU. Sem isto o `__index` generico respondia `GetAtlas`
    -- com uma funcao que devolve outro widget -- sempre nao-nil --, e a conferencia de
    -- `ns.SetAtlasSafe` ("pegou mesmo?") dava certo para QUALQUER nome, inclusive inventado.
    -- O stub concordava com o defeito exato que a funcao existe para pegar.
    function self.CreateTexture()
        local t = widget("Texture")
        function t.SetAtlas(_, atlas) t.__atlas = atlas end
        function t.GetAtlas() return t.__atlas end
        -- GUARDA A COR. Sem isto "a barra ficou verde no fim" nao era conferivel em disco, e
        -- cor e justamente o tipo de coisa que ninguem percebe ter quebrado.
        function t.SetColorTexture(_, r, g, b, a) t.__color = { r, g, b, a } end
        function t.GetVertexColor()
            local c = t.__color or {}
            return c[1], c[2], c[3], c[4]
        end
        return t
    end
    function self.GetName() return ADDON .. kind end
    function self.GetPoint() return "CENTER", nil, "CENTER", 0, 0 end
    function self.IsShown() return self.__shown == true end
    function self.SetShown(_, v) self.__shown = v end
    function self.Show() self.__shown = true end
    function self.Hide() self.__shown = false end
    function self.GetWidth() return self.__w or 280 end
    function self.GetHeight() return self.__h or 400 end
    function self.GetEffectiveScale() return 1 end
    function self.GetCenter() return 400, 300 end
    function self.GetFrameLevel() return 1 end
    function self.GetHighlightTexture() return widget("Texture") end
    function self.GetNormalTexture() return widget("Texture") end
    function self.GetText() return self.__text or "" end
    function self.SetChecked(_, v) self.__checked = v end
    function self.GetChecked() return self.__checked == true end
    function self.SetText(_, t) self.__text = t end
    function self.HasFocus() return false end

    -- ATRIBUTOS DE VERDADE, guardados e devolvidos. Sem isto o `__index` generico respondia
    -- `SetAttribute` com um no-op e a acao segura de aparencia -- que E toda feita de atributos --
    -- ficava invisivel ao teste: o addon podia nao armar nada e nada acusaria.
    --
    -- E a quarta divergencia da mesma familia nesta sessao (faltavam tambem
    -- `ChangeDisplayedOutfit`, `Enum.TransmogSituationTrigger` e o disparo do evento de troca).
    -- Stub que nao sabe representar uma parte da API testa a si mesmo naquela parte.
    self.__attrs = {}
    -- HABILITADO/DESABILITADO de verdade. Sem isto o `__index` generico respondia `SetEnabled`
    -- com um no-op, e o botao apagado -- que E a resposta ao pedido do usuario -- ficava
    -- invisivel ao teste.
    self.__enabled = true
    function self.SetEnabled(_, v) self.__enabled = v and true or false end
    function self.IsEnabled() return self.__enabled end
    function self.Enable() self.__enabled = true end
    function self.Disable() self.__enabled = false end

    function self.SetAttribute(_, key, value) self.__attrs[key] = value end
    function self.GetAttribute(_, key) return self.__attrs[key] end
    function self.RegisterForClicks(_, ...) self.__clicks = { ... } end

    return setmetatable(self, {
        __index = function(_, key)
            if type(key) == "string" and key:match("^%u") then
                return function() return widget(key) end
            end
            return nil
        end,
    })
end

local frames = {}

-- As PARTES que cada template da Blizzard cria. Sem isto o simulador devolveria uma FUNCAO
-- para `frame.Inset` (o metatable responde qualquer chave PascalCase), o guard `if frame.Inset`
-- passaria e o `:ClearAllPoints()` estouraria — um erro que so existe no simulador e mascara
-- o comportamento real. Melhor o stub imitar o template do que o codigo se defender do stub.
local TEMPLATE_PARTS = {
    ButtonFrameTemplate = { "Inset", "Bg", "TitleContainer", "CloseButton", "PortraitContainer" },
    PortraitFrameTemplate = { "TitleContainer", "CloseButton", "PortraitContainer" },
    InputBoxInstructionsTemplate = { "Instructions" },
}

function CreateFrame(frameType, name, parent, template)
    local f = widget(frameType or "Frame")
    f.__name, f.__template = name, template

    for pattern, parts in pairs(TEMPLATE_PARTS) do
        if template == pattern then
            for _, part in ipairs(parts) do
                f[part] = widget(part)
            end
        end
    end

    frames[#frames + 1] = f
    return f
end

--------------------------------------------------------------------------------
-- Globais do jogo
--------------------------------------------------------------------------------
UIParent = widget("Frame")
Minimap = widget("Frame")

-- O MENU DE CONTEXTO FALSO. Ele guarda o que foi montado -- titulo e botoes -- para o teste
-- poder conferir a LISTA sem desenhar nada, e poder "clicar" numa entrada chamando a funcao
-- que ela registrou.
MENU = nil
MenuUtil = {
    CreateContextMenu = function(_, montar)
        MENU = { titulo = nil, itens = {} }
        montar(nil, {
            CreateTitle = function(_, texto) MENU.titulo = texto end,
            CreateButton = function(_, texto, fn)
                MENU.itens[#MENU.itens + 1] = { texto = texto, acao = fn }
            end,
        })
    end,
}
GameTooltip = widget("GameTooltip")
UISpecialFrames = {}
SlashCmdList = {}
unpack = unpack or table.unpack
format = string.format

function GameTooltip_Hide() end
function GetLocale() return "ptBR" end

-- Le o .toc de verdade em vez de devolver um numero fixo: com constante aqui, um teste
-- sobre versao passaria a confirmar o stub em vez do addon.
C_AddOns = {
    GetAddOnMetadata = function(_, field)
        for line in io.lines(ADDON .. ".toc") do
            local value = line:match("^## " .. field .. ":%s*(.-)%s*$")
            if value then return (value:gsub("%c", "")) end
        end
    end,
}

function GetCursorPosition() return 400, 300 end
-- `date` e `time` sao do jogo (o Lua do WoW expoe os de `os`), e o log grava a hora de cada
-- linha. Sem eles aqui o addon carregava e o log estourava na primeira gravacao.
date = date or os.date
time = time or os.time
function CopyTable(t)
    local out = {}
    for k, v in pairs(t) do out[k] = type(v) == "table" and CopyTable(v) or v end
    return out
end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function tinsert(t, v) t[#t + 1] = v end
-- `tremove` e do jogo (alias de `table.remove`) e o anel do diario depende dele. Faltava, e o
-- unico sinal era o log estourar na entrada 401 -- ou seja, so depois de trinta trocas.
tremove = tremove or table.remove
function UnitCastingInfo() return nil end
-- No jogo, valor secret e opaco em combate. Aqui nada e secret; o que importa e o addon
-- CHAMAR a funcao antes de tocar no valor, e isso o simulador exercita.
function issecretvalue() return false end
_G = _G or setmetatable({}, { __index = function(_, k) return rawget(_ENV or {}, k) end })
-- Resolve caminho de textura em FileID, ou nil se nao existir. E como o addon evita icone
-- fantasma: aqui so o ultimo candidato "existe", para o fallback ser exercitado.
function GetFileIDFromPath(path)
    return path:find("MissileLarge_Red", 1, true) and 12345 or nil
end

-- Equipamento e tooltip. O texto da global e o REAL do build 12.1.0.69587, conferido no
-- GlobalStrings do wago.tools — e a linha vem EMBRULHADA EM CODIGO DE COR de proposito,
-- porque foi exatamente isso que quebrou o padrao ancorado do EnhanceQoL.
PVP_ITEM_LEVEL_TOOLTIP =
    "Equipar: aumenta o nível do item para um mínimo de %d em Arenas, Campos de Batalha e no Modo de Guerra."

HEADSLOT, NECKSLOT, SHOULDERSLOT = "Cabeca", "Pescoco", "Ombros"
CHESTSLOT, WAISTSLOT, LEGSSLOT, FEETSLOT = "Peito", "Cintura", "Pernas", "Pes"
WRISTSLOT, HANDSSLOT = "Pulsos", "Maos"
FINGER0SLOT, FINGER1SLOT = "Anel 1", "Anel 2"
TRINKET0SLOT, TRINKET1SLOT = "Berloque 1", "Berloque 2"
BACKSLOT, MAINHANDSLOT, SECONDARYHANDSLOT = "Costas", "Mao principal", "Mao secundaria"
NORMAL_FONT_COLOR = {}

-- O RECADO QUE O CLIENTE DEVOLVE ENQUANTO BUSCA OS DADOS DO ITEM. Global do jogo, e e o texto que
-- apareceu no despejo de 13/09 (`tipo=41 Recuperando informacoes do item`) -- a linha unica que
-- fazia o addon marcar peca de PvP como PvE.
RETRIEVING_ITEM_INFO = "Recuperando informações do item"

-- Que peca esta em cada slot, se ela e de PvP, e se os DADOS dela ja chegaram. O teste mexe nisto.
--
-- ⚑ `loaded` NASCEU DO DEFEITO: o stub antigo entregava a tooltip pronta sempre, entao o caminho
-- "cliente ainda buscando" nao existia aqui -- e era exatamente ele que quebrava no jogo. Stub que
-- so sabe representar o mundo bom testa a si mesmo.
local equipped = {}
local function VestirTudo(ehPvP)
    equipped = {}
    for _, slot in ipairs({ 1,2,3,5,6,7,8,9,10,11,12,13,14,15,16,17 }) do
        equipped[slot] = { link = "item:" .. slot, pvp = ehPvP, loaded = true }
    end
end
VestirTudo(false)

function GetInventoryItemLink(_, slot)
    return equipped[slot] and equipped[slot].link
end

-- O id do item daquele slot, que e por onde se pede o carregamento.
function GetInventoryItemID(_, slot)
    return equipped[slot] and (1000 + slot) or nil
end

-- Quantas vezes cada item teve carregamento pedido, e os retornos pendentes.
pedidos = {}
local aoCarregar = {}

C_Item = C_Item or {}
function C_Item.RequestLoadItemDataByID(id)
    pedidos[id] = (pedidos[id] or 0) + 1
end

Item = {
    CreateFromItemID = function(_, id)
        return {
            id = id,
            ContinueOnItemLoad = function(self, cb)
                aoCarregar[self.id] = aoCarregar[self.id] or {}
                table.insert(aoCarregar[self.id], cb)
            end,
        }
    end,
}

---Os dados daquele item chegaram: marca a peca como carregada e chama quem esperava.
function CarregarItem(slot)
    if equipped[slot] then equipped[slot].loaded = true end
    local id = 1000 + slot
    local fila = aoCarregar[id] or {}
    aoCarregar[id] = nil
    for _, cb in ipairs(fila) do cb() end
end

C_TooltipInfo = {
    GetInventoryItem = function(_, slot)
        local item = equipped[slot]
        if not item then return nil end

        -- DADOS AINDA NAO CHEGARAM: uma linha so, de recado. E o que o cliente faz de verdade.
        if item.loaded == false then
            return { lines = { { type = 41, leftText = RETRIEVING_ITEM_INFO } } }
        end

        local lines = { { type = 0, leftText = "Nome do item" } }
        if item.pvp then
            -- EMBRULHADA EM COR: o caso que derruba padrao ancorado.
            lines[#lines + 1] = {
                type = 0,
                leftText = "|cffffffff" .. PVP_ITEM_LEVEL_TOOLTIP:gsub("%%d", "684") .. "|r",
            }
        end
        return { lines = lines }
    end,
}

-- A tabela GLOBAL de caixas de confirmacao do jogo, e o `Show` que as abre. Ela existe sempre no
-- cliente (o `Blizzard_StaticPopup` e addon base), e sem ela aqui o resumo do ready check nao era
-- conferivel -- so daria para testar que NAO estourou.
--
-- `StaticPopup_Show` DA ERRO quando o dialogo nao existe (`StaticPopup.lua:302-304`), e o stub
-- reproduz isso: e o motivo de o addon chamar por `pcall`.
StaticPopupDialogs = {}
OKAY = "OK"
shownPopups = {}
function StaticPopup_Show(which, arg1)
    if not StaticPopupDialogs[which] then
        error("Dialog " .. tostring(which) .. " does not exist.")
    end
    shownPopups[#shownPopups + 1] = { which = which, text = arg1 }
    return {}
end

-- `StaticPopup_Hide` fecha a caixa. O addon usa para tirar da tela o resumo do convite quando o
-- convite acaba -- aceito, recusado ou expirado --, e sem este stub nao dava para conferir que
-- ele fecha, so que ele abre.
hiddenPopups = {}
function StaticPopup_Hide(which)
    hiddenPopups[#hiddenPopups + 1] = which
end

-- `SuppressMessagesThisFrame` e metodo da propria Blizzard
-- (`Blizzard_UIErrorsFrame/Mainline/UIErrorsFrame.lua:182-189`): suprime as mensagens de erro por
-- UM quadro e se desarma sozinho. Sem ele aqui nao dava para conferir que o addon engole o erro
-- vermelho que a propria chamada dele provoca.
-- Contador proprio, e nao `state`: este bloco roda ANTES de `state` existir no arquivo.
suppressedFrames = 0
UIErrorsFrame = {
    AddExternalWarningMessage = function() end,
    SuppressMessagesThisFrame = function() suppressedFrames = suppressedFrames + 1 end,
}
C_EventUtils = { IsEventValid = function() return true end }
C_RestrictedActions = { GetAddOnRestrictionState = function() return 0 end }
function GetMaxBattlefieldID() return 2 end
function GetBattlefieldStatus() return "none" end

-- ScrollBox: o sistema de lista da Blizzard. Os stubs nao sao no-op — o SetDataProvider
-- CHAMA o inicializador de cada linha, para o teste exercitar FillRow de verdade. Stub que
-- nao executa nada da a impressao de cobertura sem cobrir.
function CreateDataProvider(t) return { __items = t } end
function CreateAnchor() return {} end
function WrapTextInColor(text) return text end
function InputBoxInstructions_OnTextChanged() end
GRAY_FONT_COLOR = {}
SelectionBehaviorMixin = { Event = { OnSelectionChanged = "OnSelectionChanged" } }

function CreateScrollBoxListLinearView()
    local view = {}
    function view.SetVirtualized() end
    function view.SetElementExtent() end
    -- ALTURA POR ELEMENTO. O stub GUARDA a funcao em vez de engolir: com ela guardada, o teste
    -- consegue perguntar quanto mede um card -- que e a unica parte da geometria do card que da
    -- para conferir em disco, e e a que muda quando alguem mexe nos campos.
    function view.SetElementExtentCalculator(_, fn) view.__extent = fn end
    function view.SetPadding() end
    function view.SetElementInitializer(_, _, fn) view.__init = fn end
    return view
end

ScrollUtil = {
    InitScrollBoxListWithScrollBar = function(list, _, view)
        list.__view = view
        list.__rows = {}
        -- AS LINHAS SAO RECICLADAS, como no jogo. O stub recriava todas a cada troca de provider,
        -- e isso escondia uma classe inteira de defeito: estado que fica na linha de um conjunto e
        -- reaparece na linha de outro. Reciclar e o que torna isso visivel -- e e o que o jogo faz
        -- (e por isso que `ReinitializeFrames` existe: as molduras sao as mesmas).
        function list.SetDataProvider(_, provider)
            local items = provider.__items or {}
            for i, data in ipairs(items) do
                local row = list.__rows[i]
                if not row then
                    row = CreateFrame("Button", nil, list)
                    list.__rows[i] = row
                end
                row.GetElementData = function() return data end
                if view.__init then view.__init(row, data) end
            end
            for i = #list.__rows, #items + 1, -1 do
                list.__rows[i] = nil
            end
            -- Como no jogo: trocar o data provider APAGA a selecao
            -- (SelectionBehaviorMixin:OnScrollBoxDataProviderReassigned, ScrollUtil.lua:413).
            if list.__selection then list.__selection.__selected = nil end
        end
        function list.ReinitializeFrames()
            for i, row in ipairs(list.__rows) do
                if view.__init and row.preset then view.__init(row, row.preset) end
            end
        end
        function list.FindFrame(_, data)
            for _, row in ipairs(list.__rows) do
                if row.preset == data then return row end
            end
            return nil
        end
    end,
    AddManagedScrollBarVisibilityBehavior = function() end,
    -- ESTE STUB JA MENTIU UMA VEZ. A versao anterior fazia GetSelectedElementData devolver UM
    -- elemento; a API real devolve uma LISTA (ScrollUtil.lua:434). Lista vazia e verdadeira em
    -- Lua, entao o addon achava que havia selecao onde nao havia — e 61 checks passaram em
    -- cima de codigo quebrado. Stub que diverge da API testa a si mesmo.
    AddSelectionBehavior = function(list)
        local sel = { __selected = nil, __callbacks = {} }
        sel.__list = list
        list.__selection = sel

        function sel.RegisterCallback(_, _, fn, owner)
            sel.__callbacks[#sel.__callbacks + 1] = { fn, owner }
        end
        -- LISTA, como a de verdade.
        function sel.GetSelectedElementData()
            return sel.__selected and { sel.__selected } or {}
        end
        function sel.GetFirstSelectedElementData() return sel.__selected end
        function sel.IsElementDataSelected(_, data) return sel.__selected == data end
        function sel.SelectElementData(_, data)
            local antigo = sel.__selected
            sel.__selected = data
            for _, cb in ipairs(sel.__callbacks) do
                if antigo and antigo ~= data then cb[1](cb[2], antigo, false) end
                cb[1](cb[2], data, true)
            end
        end
        -- Select(frame) le o elementData DO FRAME (ScrollUtil.lua:619).
        function sel.Select(_, f) return sel:SelectElementData(f:GetElementData()) end
        function sel.ClearSelections() sel.__selected = nil end
        return sel
    end,
}

-- Estado simulado do personagem: um Cavaleiro da Morte com os mesmos conjuntos e loadouts
-- do print que o usuario mandou. Frost e PvP sao a MESMA spec — que e o caso que o jogo
-- nao consegue expressar sozinho, e a razao deste addon existir.
local state = {
    inCombat = false,
    instance = nil,          -- nil | "party" | "raid" | "arena" | "pvp"
    specIndex = 2,               -- Gelido
    equippedSet = 1,             -- Frost
    outfit = 71,                 -- aparencia ativa
    activeLoadout = { [251] = 11, [252] = nil, [250] = nil },
}

function InCombatLockdown() return state.inCombat end
function IsInInstance() return state.instance ~= nil, state.instance end
function IsInRaid() return state.instance == "raid" end

local SPECS = {
    { index = 1, id = 250, name = "Sangue",  icon = 1 },
    { index = 2, id = 251, name = "Gelido",  icon = 2 },
    { index = 3, id = 252, name = "Profano", icon = 3 },
}

-- Pode trocar de spec agora? E o que a janela de talentos do jogo pergunta para decidir se o
-- botao "Ativar" fica clicavel (`Blizzard_ClassSpecializationsFrame.lua:139,149`), e devolve
-- `canUse, failureReason` -- com o motivo ja traduzido pelo cliente.
state.canChangeSpec = true
state.cannotChangeReason = "Voce nao pode trocar de especializacao agora."

-- A MAGIA DE ATIVAR ESPECIALIZACAO. Nao ha constante para ela no cliente: ha o predicado
-- `IsSpecializationActivateSpell`, e e assim que o addon aprende o id -- perguntando ao jogo
-- quando um cast do jogador termina.
state.specSpellID = 200749
state.specSpellOnCooldown = false

function IsSpecializationActivateSpell(spellID)
    return spellID == state.specSpellID
end

C_SpecializationInfo = {
    CanPlayerUseTalentSpecUI = function()
        if state.canChangeSpec then return true, "" end
        return false, state.cannotChangeReason
    end,
    GetNumSpecializations = function() return #SPECS end,
    GetSpecialization = function() return state.specIndex end,
    GetSpecializationInfo = function(i)
        local s = SPECS[i]
        if not s then return nil end
        return s.id, s.name, "desc", s.icon
    end,
    -- A RECUSA TRANSITORIA DO JOGO, que o diario real do usuario registrou em quatro das nove
    -- trocas: `SetSpecialization` devolve `false` e nao faz nada. O stub precisa saber produzi-la,
    -- senao o caminho da insistencia -- e o da desistencia no teto -- nao existe para o teste.
    SetSpecialization = function(i)
        if state.refuseSpec then return false end
        state.pendingSpec = i
        return true
    end,
}

local LOADOUTS = {
    [251] = { { configID = 10, name = "PvP" }, { configID = 11, name = "SBA ST" },
              { configID = 12, name = "Deathbringer ST" } },
    [250] = {},
    [252] = {},
}

C_ClassTalents = {
    GetConfigIDsBySpecID = function(specID)
        local out = {}
        for _, l in ipairs(LOADOUTS[specID] or {}) do out[#out + 1] = l.configID end
        return out
    end,
    GetLastSelectedSavedConfigID = function(specID) return state.activeLoadout[specID] end,
    -- O CONFIG ATIVO, que e como se sabe de quem e o `TRAIT_CONFIG_UPDATED`. Faltava, e sem ele o
    -- addon nao tinha com que comparar: fechava o passo no PRIMEIRO evento, que a Blizzard avisa
    -- por escrito ser o do config base da spec, e nao o do loadout
    -- (`Blizzard_ClassTalentsFrame.lua:407-411`).
    GetActiveConfigID = function() return state.activeConfigID end,
    UpdateLastSelectedSavedConfigID = function(specID, configID)
        state.activeLoadout[specID] = configID
    end,
    -- TRES retornos, como a API: `result, changeError, newLearnedNodeIDs`
    -- (ClassTalentsDocumentation.lua:263-268). Devolver so o primeiro escondia que o addon
    -- estava jogando fora justamente a string que diz por que a troca nao deu.
    -- A RECUSA DO SERVIDOR, que o diario real de 07/09 21:1x registrou: `LoadConfig` devolveu
    -- `Error` (0) com `changeError` **nil** -- recusou sem dizer por que -- no instante seguinte
    -- a troca de spec. Sem o stub saber produzir isso, o caminho da insistencia nao existia para
    -- o teste, e o addon desistia na primeira recusa: o jogador virava Frost com a build de PvE.
    --
    -- `loadRefusals` conta quantas recusas ainda faltam; `loadError` diz se elas vem com motivo
    -- declarado (que NAO deve insistir) ou sem (que deve).
    LoadConfig = function(configID)
        if (state.loadRefusals or 0) > 0 then
            state.loadRefusals = state.loadRefusals - 1
            return 0, state.loadError, {}
        end
        state.pendingLoadout = configID
        return 2, nil, {}        -- LoadInProgress: confirma por evento
    end,
    -- `CanEditTalents` devolve `canEdit, changeError`. Sem ela no simulador, a pre-checagem do
    -- addon era pulada em silencio e o teste nunca via esse caminho.
    CanEditTalents = function() return true, nil end,
}

-- Botoes da recusa de `LoadConfig` (ver o comentario dentro de `C_ClassTalents`).
state.loadRefusals = 0
state.loadError = nil

C_Traits = {
    GetConfigInfo = function(configID)
        for _, list in pairs(LOADOUTS) do
            for _, l in ipairs(list) do
                if l.configID == configID then return { ID = configID, name = l.name } end
            end
        end
        return nil
    end,
}

local SETS = {
    { setID = 1, name = "Frost",  icon = 100 },
    { setID = 2, name = "Unholy", icon = 101 },
    { setID = 3, name = "Blood",  icon = 102 },
    { setID = 4, name = "PvP",    icon = 103 },
}

--------------------------------------------------------------------------------
-- Tratamento de erro do cliente
--------------------------------------------------------------------------------
-- O SIMULADOR PRECISA DOS TRES MUNDOS, porque o addon escolhe caminho diferente em cada um:
--
--   1. sem !BugGrabber          -> encadeia no handler que estiver valendo
--   2. com !BugGrabber          -> assina o callback dele (e o `seterrorhandler` e um no-op)
--   3. `seterrorhandler` mudo, sem BugGrabber -> nao da para capturar, e tem que ADMITIR isso
--
-- O mundo 3 e o que justifica a conferencia `geterrorhandler() == meu` no addon: sem ela a
-- captura se declara ligada estando desligada, e "o arquivo nao tem erro" viraria mentira.
mundoErro = {
    handler = nil,
    mudo = false,        -- o !BugGrabber faz `function seterrorhandler() end`
}

function seterrorhandler(fn)
    if mundoErro.mudo then return end
    mundoErro.handler = fn
end

function geterrorhandler()
    return mundoErro.handler
end

function debugstack()
    return mundoErro.pilha or ""
end

C_EquipmentSet = {
    GetEquipmentSetIDs = function()
        local out = {}
        for _, s in ipairs(SETS) do out[#out + 1] = s.setID end
        return out
    end,
    -- NOVE RETORNOS, e nao quatro. Os quatro ultimos sao contagem
    -- (`numItems, numEquipped, numInInventory, numLost, numIgnored`), e `numLost` -- "pecas que o
    -- jogador nao tem a mao agora" -- e a UNICA resposta direta que o jogo da para "por que a
    -- troca falhou": `UseEquipmentSet` nao da motivo e `EQUIPMENT_SWAP_FINISHED` so traz um
    -- booleano. O stub devolvia so quatro, entao o addon nao tinha como perguntar isso aqui.
    --
    -- `state.wornPieces[setID]` = PECAS DESTE CONJUNTO NO CORPO AGORA, para o caso em que o
    -- jogador trocou uma peca a mao: `isEquipped` cai (e tudo-ou-nada) mas `numEquipped` continua
    -- alto. Sem esse controle o stub so sabia dois estados (14 ou 0) e o quase-vestido --
    -- justamente o defeito relatado -- nao tinha como ser simulado.
    GetEquipmentSetInfo = function(setID)
        for _, s in ipairs(SETS) do
            if s.setID == setID then
                local perdidas = state.lostItems or 0
                local vestido = state.equippedSet == setID
                local vestidas = (state.wornPieces and state.wornPieces[setID])
                    or (vestido and 14 or 0)
                return s.name, s.icon, setID, vestido,
                    14, vestidas, 14 - perdidas, perdidas, 2
            end
        end
        return nil
    end,
    EquipmentSetContainsLockedItems = function() return state.locked == true end,
    -- EQUIPAR DE VERDADE, e nao so registrar o pedido. O stub guardava so `pendingSet`, entao
    -- `isEquipped` do conjunto alvo continuava falso depois da troca -- e o addon, que agora
    -- confirma o passo LENDO O ESTADO (e nao pelo id do evento), ficaria esperando para sempre um
    -- estado que o simulador nunca produzia.
    --
    -- `pendingSet` fica como sonda de "o que foi pedido"; `equippedSet` e o mundo.
    -- SO PEDE. O conjunto fica vestido quando o EVENTO chega, nao na chamada -- e a diferenca
    -- importa: o addon confirma o passo lendo o estado, e equipar cedo demais aqui fazia o
    -- primeiro evento (ate o de OUTRO conjunto) encontrar o alvo ja vestido e fechar o passo.
    -- E ELA DEVOLVE `setWasEquipped`. O stub sempre devolvia `true`, entao o caminho da RECUSA
    -- IMEDIATA -- o jogo dizendo "nao" na hora, sem swap e portanto sem evento nenhum depois --
    -- nao existia no simulador, e o addon podia ignorar o retorno sem nenhum teste reclamar.
    UseEquipmentSet = function(setID)
        if state.refuseUseSet then return false end
        state.pendingSet = setID
        return true
    end,
}

-- Transmog: namespace novo do Midnight. O ID e o INDICE sao coisas diferentes de proposito
-- (o comentario da Blizzard diz que os IDs tem buracos), e o simulador reproduz isso — se o
-- addon guardar o indice em vez do ID, o teste de "apagar uma aparencia" pega.
local OUTFITS = {
    { outfitID = 71, playerFacingOutfitIndex = 1, name = "Gelido",  icon = 201, isDisabled = false },
    { outfitID = 88, playerFacingOutfitIndex = 2, name = "Arena",   icon = 202, isDisabled = false },
    { outfitID = 93, playerFacingOutfitIndex = 3, name = "Antigo",  icon = 203, isDisabled = true  },
}

-- `fire` e definido bem mais abaixo, mas o stub de `ChangeToOutfit` precisa dele: no jogo, quem
-- troca a aparencia DISPARA `TRANSMOG_DISPLAYED_OUTFIT_CHANGED`. Declarar aqui e atribuir la
-- embaixo mantem o upvalue -- `local` declarado depois de quem usa resolve como global nil.
local fire

-- AS TRES PORTAS que recusam a troca de aparencia SEM devolver erro. O stub tem que saber
-- representa-las, senao o codigo que as consulta nunca e exercitado -- e o motivo de elas
-- existirem aqui e justamente que o jogo nao avisa quando fecham.
state.transmogCooldown = 0          -- segundos restantes; 0 = sem recarga
state.inStyleEvent = false
state.lockedOutfits = {}            -- [outfitID] = true
state.silentRefusal = false         -- aceita a chamada e nao faz nada, sem motivo declarado
state.usedDoor = nil                -- por qual das duas portas a troca entrou
state.lastTrigger = nil             -- o gatilho de situacao declarado na troca

---O que as DUAS portas fazem quando nada impede: aplicam e avisam. Uma so copia do
---comportamento, porque duas divergem -- foi assim que quatro copias de `ChangeToOutfit`
---espalhadas pelos testes ficaram para tras quando a confirmacao virou por evento.
local function Aplica(outfitID)
    if state.transmogCooldown > 0 or state.inStyleEvent or state.silentRefusal then return end
    if state.lockedOutfits[outfitID] then return end

    state.pendingOutfit = outfitID
    state.outfit = outfitID
    fire("TRANSMOG_DISPLAYED_OUTFIT_CHANGED")
end

C_TransmogOutfitInfo = {
    GetOutfitsInfo = function() return OUTFITS end,
    GetActiveOutfitID = function() return state.outfit end,
    InTransmogEvent = function() return state.inStyleEvent end,
    IsLockedOutfit = function(outfitID) return state.lockedOutfits[outfitID] == true end,
    -- A CHAMADA DEVOLVE `true` MESMO QUANDO NAO FAZ NADA, e e essencial que o stub minta assim:
    -- e exatamente esse o comportamento relatado ("nao troca e nao gera nenhum erro"). Um stub
    -- que devolvesse erro quando bloqueado testaria um jogo que nao existe.
    --
    -- E QUANDO FAZ, DISPARA O EVENTO. `TRANSMOG_DISPLAYED_OUTFIT_CHANGED` e o que a propria
    -- janela de transmog escuta para se redesenhar (`Blizzard_Transmog.lua:85,184`). Sem ele no
    -- stub, o passo que espera o evento ficaria pendurado e o teste acusaria um defeito que so
    -- existe no simulador.
    --
    -- `state.silentRefusal` representa a hipotese que sobrou depois do relato do usuario: nada
    -- bloqueando, chamada aceita, e mesmo assim nada muda. E o unico jeito de exercitar o
    -- caminho do PRAZO, que e quem responde nesse caso.
    ChangeToOutfit = function(index)
        for _, o in ipairs(OUTFITS) do
            if o.playerFacingOutfitIndex == index then
                state.usedDoor = "ChangeToOutfit"
                Aplica(o.outfitID)
            end
        end
        return true
    end,

    -- A PORTA QUE A UI DO JOGO USA (`Blizzard_TransmogTemplates.lua:72`). Ela existe aqui porque
    -- sem ela o addon caia no ramo de fallback e o caminho principal nunca era exercitado -- o
    -- teste passava confirmando o codigo que NAO roda no jogo. E a mesma classe de divergencia
    -- que ja apareceu meia duzia de vezes neste projeto: stub que diverge da API testa a si
    -- mesmo. `state.usedDoor` registra por qual delas a troca entrou.
    ChangeDisplayedOutfit = function(outfitID, trigger, _toggleLock, _allowRemove)
        state.lastTrigger = trigger
        state.usedDoor = "ChangeDisplayedOutfit"
        Aplica(outfitID)
        return true
    end,
}

-- `GetSpellCooldown` devolve `{ startTime, duration, isEnabled }`, e "sem recarga" NAO e um
-- estado so: a Blizzard exige `enable ~= 0 and start > 0 and duration > 0` para desenhar a
-- recarga (`Blizzard_FrameXMLUtil/Cooldown.lua:3`), ou seja, ela guarda contra combinacoes em
-- que uma das tres nao vale.
--
-- O STUB PRECISA SABER PRODUZIR ESSAS COMBINACOES. Enquanto ele devolvia `duration = 0` junto
-- com `startTime = 0`, um addon que so olhasse `duration` passava no teste -- o stub estava
-- concordando com o defeito. `state.cooldownShape` escolhe qual caso representar.
-- OS ATLAS QUE EXISTEM NESTE CLIENTE, e a lista e curta de proposito: sao os que o addon usa,
-- todos conferidos na fonte do 12.1.0. `GetAtlasInfo` devolvendo nil para nome desconhecido e o
-- que da ao teste como reprovar um atlas inventado -- que `SetAtlas` sozinho nunca faria, porque
-- ele falha em SILENCIO.
local ATLAS = {
    ["common-icon-checkmark"] = true,       -- Blizzard_UIWidgetTemplateBase.xml:184
    ["common-icon-redx"] = true,            -- Blizzard_CharacterCreate.xml:507
    ["common-icon-forwardarrow"] = true,    -- Blizzard_RotateControlFrame.xml:55
    ["Options_HorizontalDivider"] = true,   -- Blizzard_SettingsList.xml:20
}
C_Texture = {
    GetAtlasInfo = function(name)
        if not ATLAS[name] then return nil end
        return { file = 1, width = 16, height = 16, leftTexCoord = 0, rightTexCoord = 1,
                 topTexCoord = 0, bottomTexCoord = 1 }
    end,
}

local fakeNow = 1000
function GetTime() return fakeNow end

---Adianta o relogio do simulador. E o que permite testar a PAUSA em que o resultado fica na
---tela: sem mover o tempo, ela nunca vence e o painel pareceria eterno.
function AdvanceClock(seconds) fakeNow = fakeNow + seconds end

state.cooldownShape = "normal"      -- "normal" | "semInicio" | "desligada"

-- O VALOR OPACO, e ele e o centro do pior defeito que esta corrente teve.
--
-- `C_Spell.GetSpellCooldown` e `SecretWhenCooldownsRestricted` (`SpellDocumentation.lua:271`), e
-- esse predicado vale para combate, encontro, **modo desafio** e PvP -- a mitica+ inteira. Em
-- `SpellCooldownInfo`, `isEnabled`, `isActive` e `isOnGCD` sao `NeverSecret`; **`startTime` e
-- `duration` NAO SAO** (`SpellSharedDocumentation.lua:23-30`).
--
-- O stub nao sabia produzir isso, entao o addon podia comparar e somar os dois campos e o teste
-- concordava. No jogo, dentro de uma chave, aquilo era erro de Lua -- e como nenhum prazo tinha
-- sido armado ainda, a corrente ficava presa e todo clique seguinte voltava mudo.
--
-- `type()` num secret devolve o TIPO REAL: e por isso que a guarda de `type` do addon nao
-- protegia nada, e e isso que este marcador reproduz.
-- O MARCADOR SE COMPORTA COMO O DO JOGO, e sem isso ele nao testa nada:
--
--   * `type()` num secret devolve o **TIPO REAL** -- por isso a guarda `type(x) == "number"` do
--     addon NAO protegia, e era exatamente essa falsa protecao que deixava a comparacao passar;
--   * comparar ou fazer aritmetica com ele **estoura**.
--
-- Um marcador que fosse so uma tabela inerte faria `type()` devolver "table", a guarda barraria,
-- e o teste concordaria com o defeito -- que foi o que aconteceu na primeira tentativa deste
-- stub. Aqui `type` e trocado para mentir como o jogo mente, e o metatable faz comparacao e soma
-- levantarem erro.
local function proibido()
    error("attempt to compare or perform arithmetic on a secret value", 2)
end

local SECRET = setmetatable({}, {
    __tostring = function() return "secret" end,
    __lt = proibido, __le = proibido, __add = proibido, __sub = proibido,
})

state.cooldownSecret = false
-- O config base da spec, contra o qual os eventos de talento se conferem.
state.activeConfigID = 4242

-- O CAST EM CURSO, redefinido aqui porque o stub la de cima nasce antes de `state`. Devolvia
-- sempre nil, entao o caminho "o jogador esta conjurando" nao existia para o teste -- e foi por
-- ele que os itens cairam as 17:46:01 de 11/09. Nove retornos como a API; o 9o e o `spellID`.
function UnitCastingInfo()
    if state.casting then
        return "Conjurando", nil, nil, nil, nil, false, "c", false, state.casting
    end
    return nil
end

local realIsSecretBase = issecretvalue
function issecretvalue(v) return v == SECRET or realIsSecretBase(v) end

local realType = type
function type(v)
    if v == SECRET then return "number" end     -- o tipo REAL, como no jogo
    return realType(v)
end

C_Spell = {
    GetSpellCooldown = function(spellID)
        -- A MAGIA DE SPEC tem recarga propria, e e ela que explica o relato: o jogo recusa a troca
        -- por alguns segundos depois de uma que deu certo, e `CanPlayerUseTalentSpecUI` responde
        -- SIM o tempo todo -- o diario de 02:28:18 (sucesso) e 02:28:26 (recusa) provou.
        if spellID == state.specSpellID then
            return { startTime = 0, duration = 0, isEnabled = true,
                     isActive = state.specSpellOnCooldown }
        end
        local ativo = state.transmogCooldown > 0 and state.cooldownShape == "normal"

        -- DENTRO DE MITICA+ os dois campos de tempo vem opacos, e so eles. `isActive` continua
        -- legivel -- e e por isso que ele e a pergunta certa.
        if state.cooldownSecret then
            return { startTime = SECRET, duration = SECRET, isEnabled = true, isActive = ativo }
        end

        if state.transmogCooldown <= 0 then
            return { startTime = 0, duration = 0, isEnabled = true, isActive = false }
        end
        if state.cooldownShape == "semInicio" then
            -- duration > 0 mas start == 0: o caso contra o qual a Blizzard guarda.
            return { startTime = 0, duration = state.transmogCooldown,
                     isEnabled = true, isActive = false }
        end
        if state.cooldownShape == "desligada" then
            return { startTime = fakeNow, duration = state.transmogCooldown,
                     isEnabled = false, isActive = false }
        end
        return { startTime = fakeNow, duration = state.transmogCooldown,
                 isEnabled = true, isActive = true }
    end,
}

Constants = {
    TransmogOutfitDataConsts = { EQUIP_TRANSMOG_OUTFIT_MANUAL_SPELL_ID = 1247613 },
    -- O cast que grava talentos (`Blizzard_ClassTalentsFrame.lua:345-350`). O valor e o do cliente
    -- 12.1.0, conferido na lista de constantes que o Details carrega (`luaserver.lua:1048`).
    TraitConsts = { COMMIT_COMBAT_TRAIT_CONFIG_CHANGES_SPELL_ID = 384255 },
}

Enum = {
    AddOnRestrictionType = { Combat = 0, Encounter = 1, ChallengeMode = 2, PvPMatch = 3 },
    AddOnRestrictionState = { Inactive = 0, Activating = 1, Active = 2 },
    LoadConfigResult = { Error = 0, NoChangesNecessary = 1, LoadInProgress = 2, Ready = 3 },

    -- Os valores REAIS do 12.1.0 (`TransmogOutfitConstantsDocumentation.lua:368-376`). Sem este
    -- enum aqui, `Enum.TransmogSituationTrigger.Manual` no addon resolvia para `nil` e o teste
    -- passava com o addon mandando nada como gatilho -- a mesma classe de furo que ja apareceu
    -- meia duzia de vezes: o que o stub nao sabe representar, o teste nao ve.
    --
    -- `Specialization` e `EquipmentSet` estao aqui porque explicam por que o gatilho importa: o
    -- jogo troca aparencia sozinho por esses dois, e sao os dois passos que rodam antes deste.
    TransmogSituationTrigger = {
        None = 0, Manual = 1, TransmogUpdate = 2, Location = 3, Movement = 4,
        Specialization = 5, EquipmentSet = 6, Forms = 7, EventOutfit = 8,
    },
}

-- C_Timer com relogio manual: o teste controla quando o prazo estoura.
local timers = {}

---Dispara os prazos pendentes, como o relogio do jogo faria ao vencerem.
---
---Sem isto nao havia como testar o caminho do PRAZO -- `C_Timer.After` roda na hora neste
---simulador, mas `NewTimer` so guarda. E o prazo e justamente quem responde quando o jogo aceita
---a chamada e nao faz nada.
---@param ate number|nil so dispara o que vence dentro deste tanto de segundos
function RunTimers(ate)
    -- ATE ONDE O RELOGIO ANDOU. Sem este corte o simulador tratava 4 e 45 segundos como o MESMO
    -- instante: uma chamada disparava a reinsistencia da spec (4 s) e o prazo do passo (45 s)
    -- juntos, e o prazo sempre chegava primeiro. O caminho da DESISTENCIA -- insistir ate o teto
    -- e so entao desistir -- ficava inalcancavel pelo teste, e com ele a unica linha que marca o
    -- passo abandonado como falha. Sabotar essa linha nao reprovava nada.
    local pendentes, sobra = timers, {}
    timers = {}
    for _, t in ipairs(pendentes) do
        if t.cancelled then
            -- descartado
        elseif ate and t.at > ate then
            sobra[#sobra + 1] = t
        else
            t.fn()
        end
    end
    for _, t in ipairs(sobra) do timers[#timers + 1] = t end
end
C_Timer = {
    NewTimer = function(seconds, fn)
        local t = { at = seconds, fn = fn, cancelled = false }
        function t.Cancel() t.cancelled = true end
        timers[#timers + 1] = t
        return t
    end,
    -- `After` ENFILEIRA, como no jogo -- ele NAO roda na hora. Rodando na hora, uma repeticao
    -- espacada (o passo de spec insiste de 4 em 4 segundos) virava recursao imediata ate o teto,
    -- e o teste via "desistiu" onde o jogo veria "esperando".
    After = function(seconds, fn)
        local t = { at = seconds, fn = fn, cancelled = false }
        function t.Cancel() t.cancelled = true end
        timers[#timers + 1] = t
        return t
    end,
}

--------------------------------------------------------------------------------
-- Carrega o addon na ordem do .toc
--------------------------------------------------------------------------------
local ns = {}
local files = {}
for line in io.lines(ADDON .. ".toc") do
    line = line:gsub("\r", "")
    if line:match("%.lua$") and not line:match("^#") then
        files[#files + 1] = line:gsub("\\", "/")
    end
end

print("== carregando " .. #files .. " arquivos ==")
for _, file in ipairs(files) do
    local chunk, err = loadfile(file)
    if not chunk then
        print("  FALHA AO COMPILAR " .. file .. ": " .. err)
        os.exit(1)
    end
    local ok, runErr = pcall(chunk, ADDON, ns)
    print(ok and ("  ok    " .. file) or ("  ERRO  " .. file .. ": " .. tostring(runErr)))
    if not ok then os.exit(1) end
end

--------------------------------------------------------------------------------
fire = function(event, ...)
    -- O SIMULADOR NAO ADIANTA O ESTADO, e esta ausencia e deliberada -- eu ja escrevi o contrario
    -- aqui e o diario do usuario me desmentiu.
    --
    -- Eu tinha feito o `fire` equipar o conjunto ANTES de despachar, achando que "o evento so
    -- chega quando a troca terminou, logo o mundo ja mudou". O diario de 07/09 02:05:35 mostra o
    -- oposto: `EQUIPMENT_SWAP_FINISHED` com `result = true` chegou e a leitura de estado ainda
    -- respondia que o conjunto NAO estava vestido. O addon, que naquela versao exigia a leitura,
    -- travou -- e oito segundos de "recusado" seguiram no diario.
    --
    -- Quem quiser o estado virado que o vire explicitamente no teste. O simulador nao inventa
    -- fidelidade que o jogo nao tem.

    for _, f in ipairs(frames) do
        if f.__events[event] and f.__scripts.OnEvent then
            local ok, err = pcall(f.__scripts.OnEvent, f, event, ...)
            if not ok then
                print("  ERRO em " .. event .. ": " .. tostring(err))
                os.exit(1)
            end
        end
    end
end

---Roda um QUADRO, como o jogo faria: adianta o relogio e chama o `OnUpdate` de quem tiver um.
---
---Sem isto o simulador nao tinha quadros, e metade do ciclo do painel de progresso ficava fora
---do teste -- quem ABRE o painel e o clique, mas quem o FECHA e o quadro seguinte. O ciclo que
---nao se pode rodar e o ciclo que ninguem descobre quebrado.
function TickUI(seconds)
    seconds = seconds or 0.2
    AdvanceClock(seconds)
    for _, f in ipairs(frames) do
        if f.__scripts.OnUpdate and f.IsShown and f:IsShown() then
            local ok, err = pcall(f.__scripts.OnUpdate, f, seconds)
            if not ok then
                print("  ERRO em OnUpdate: " .. tostring(err))
                os.exit(1)
            end
        end
    end
end

local function check(label, got, want)
    local ok = got == want
    print(ok and ("  ok    " .. label .. " = " .. tostring(got))
        or ("  ERRO  " .. label .. ": esperado " .. tostring(want) .. ", veio " .. tostring(got)))
    if not ok then os.exit(1) end
end

---A GRAVACAO DE TALENTOS TERMINANDO, como o jogo faz: segundos depois do `LoadConfig`.
---
---Os testes disparavam `TRAIT_CONFIG_UPDATED` no mesmo instante e chamavam isso de confirmacao.
---No jogo, o evento desse instante e o ECO da troca de spec, e o da gravacao chegou 4 a 7 s depois
---nas tres vezes medidas (diario de 09/09 e 11/09). Um teste que confirma no instante zero
---aprovava justamente o defeito que recusava os itens.
---O andamento de um passo PELO NOME, e nao pela posicao na lista.
---
---⚑ POSICAO E FRAGIL, e a suite de sabotagem provou: a sabotagem que remove o filtro de linhas do
---painel (`src.preset[key]`) muda quantas linhas existem, e um check que le `[2]` passa a reprovar
---por um defeito que nao e o dele -- apontando para o check generico em vez do que descreve a
---falha. Buscar por nome deixa cada sabotagem reprovar onde ela deve.
local function estadoDoPasso(key)
    for _, row in ipairs(ns.Data.GetProgress() or {}) do
        if row.key == key then return row.state end
    end
    return nil
end

local function gravacaoTermina(configID)
    AdvanceClock(5)
    fire("TRAIT_CONFIG_UPDATED", configID or 999)
end

print("== ciclo de vida ==")
fire("ADDON_LOADED", ADDON)
fire("PLAYER_LOGIN")
print("  ok    ADDON_LOADED + PLAYER_LOGIN")

print("== leitura do que o jogo ja tem ==")
check("tres especializacoes", #ns.Data.GetSpecs(), 3)
check("spec atual e Gelido", ns.Data.GetSpecByIndex(ns.Data.GetCurrentSpecIndex()).name, "Gelido")
check("tres loadouts em Gelido", #ns.Data.GetLoadouts(251), 3)
check("nenhum loadout em Sangue", #ns.Data.GetLoadouts(250), 0)
check("quatro conjuntos de itens", #ns.Data.GetGearSets(), 4)
check("o conjunto equipado e o Frost", ns.Data.GearSetName(ns.Data.GetEquippedSetID()), "Frost")
check("nome de loadout por id", ns.Data.LoadoutName(251, 10), "PvP")

print("== o caso que o jogo nao resolve ==")
-- Dois conjuntos para a MESMA spec (Gelido): e exatamente o que
-- C_EquipmentSet.AssignSpecToEquipmentSet nao consegue expressar, porque ele amarra um
-- conjunto por especializacao. Se este teste deixar de fazer sentido, o addon perdeu o motivo.
local pve = { name = "Mitica", spec = 2, talent = 11, gear = 1 }
local pvp = { name = "Arena",  spec = 2, talent = 10, gear = 4 }
check("os dois sao da mesma spec", pve.spec == pvp.spec, true)
check("o de PvE ja esta carregado", ns.Data.IsLoaded(pve), true)
check("o de PvP nao esta", ns.Data.IsLoaded(pvp), false)

print("== aplicar: a corrente de passos ==")
local passos = {}
local aplicou = ns.Data.Apply(pvp, function(text) passos[#passos + 1] = text end)
check("comecou", aplicou, true)
check("nao trocou de spec (e a mesma)", state.pendingSpec, nil)
check("pediu o loadout de PvP", state.pendingLoadout, 10)
check("ainda NAO equipou — espera os talentos", state.pendingSet, nil)

-- Confirma os talentos; so entao o equipamento pode ir.
state.activeLoadout[251] = 10
gravacaoTermina(10)
check("agora sim equipou o conjunto de PvP", state.pendingSet, 4)

state.equippedSet = 4
fire("EQUIPMENT_SWAP_FINISHED", true, 4)
check("terminou", ns.Data.IsApplying(), false)
check("o de PvP agora esta carregado", ns.Data.IsLoaded(pvp), true)
check("o de PvE deixou de estar", ns.Data.IsLoaded(pve), false)

print("== a ordem importa: itens POR ULTIMO ==")
-- Ao trocar de spec o jogo equipa sozinho o conjunto amarrado aquela spec. Equipar antes
-- seria sobrescrito pelo proprio jogo — por isso o passo de itens e o ultimo.
state.pendingSpec, state.pendingLoadout, state.pendingSet = nil, nil, nil
state.specIndex, state.equippedSet, state.activeLoadout[251] = 2, 4, 10

local outraSpec = { name = "Tank", spec = 1, talent = nil, gear = 3 }
ns.Data.Apply(outraSpec, function() end)
check("primeiro pede a troca de spec", state.pendingSpec, 1)
check("e NAO equipou nada ainda", state.pendingSet, nil)

state.specIndex = 1
fire("ACTIVE_PLAYER_SPECIALIZATION_CHANGED")
check("so depois da spec o conjunto vai", state.pendingSet, 3)
state.equippedSet = 3
fire("EQUIPMENT_SWAP_FINISHED", true, 3)
check("terminou", ns.Data.IsApplying(), false)

print("== falha nao pode virar sucesso silencioso ==")
-- UseEquipmentSet nao devolve erro. A unica pista e o 1o argumento de EQUIPMENT_SWAP_FINISHED.
state.specIndex, state.equippedSet = 2, 1
local erro
ns.Data.Apply({ name = "Arena", spec = 2, talent = 10, gear = 4 }, function(text, isError)
    if isError then erro = text end
end)
state.activeLoadout[251] = 10
gravacaoTermina(10)
fire("EQUIPMENT_SWAP_FINISHED", false, 4)
check("a falha de equipar foi reportada", erro ~= nil, true)
check("e o addon nao ficou preso aplicando", ns.Data.IsApplying(), false)

print("== peca travada e cast em andamento ==")
-- Reseta o conjunto vestido: agora que o stub EQUIPA de verdade, o bloco anterior deixa o 4
-- vestido, e a corrente recusaria com "nada a fazer" antes de chegar na peca travada.
state.equippedSet = 1
state.locked = true
erro = nil
ns.Data.Apply({ name = "Arena", spec = 2, talent = nil, gear = 4 }, function(text, isError)
    if isError then erro = text end
end)
check("aviso de peca travada", erro ~= nil, true)
state.locked = false

print("== combate: enfileira em vez de tentar ==")
state.inCombat = true
state.pendingSet = nil
local avisou
ns.Data.Apply({ name = "Arena", spec = 2, talent = nil, gear = 4 }, function(_, isError)
    if isError then avisou = true end
end)
check("nao aplicou em combate", state.pendingSet, nil)
check("avisou que vai esperar", avisou, true)

state.inCombat = false
fire("PLAYER_REGEN_ENABLED")
check("aplicou ao sair do combate", state.pendingSet, 4)
fire("EQUIPMENT_SWAP_FINISHED", true, 4)

print("== nada a fazer nao vira trabalho ==")
state.equippedSet, state.specIndex, state.activeLoadout[251] = 4, 2, 10
local msg
local comecou = ns.Data.Apply({ name = "Arena", spec = 2, talent = 10, gear = 4 },
    function(text) msg = text end)
check("nem comeca", comecou, false)
check("e diz por que", msg ~= nil, true)

print("== aparencia: as portas que recusam sem avisar ==")
-- O usuario relatou DUAS VEZES que a troca de aparencia "nao troca e nao gera nenhum erro" -- a
-- segunda vez ja com o passo conferindo o resultado. Sem erro, o passo so podia dizer "nao deu",
-- e o usuario ficava sem saber por que.
--
-- A fonte do 12.1.0 mostra TRES portas que recusam a troca em silencio, e a UI nativa do
-- conjunto consulta as tres antes de deixar clicar
-- (`Blizzard_Transmog/Blizzard_TransmogTemplates.lua:72-87,191-198`). Nenhuma delas devolve
-- erro: a chamada simplesmente nao faz nada.
do
    local function LimpaPortas()
        state.transmogCooldown = 0
        state.inStyleEvent = false
        state.lockedOutfits = {}
    end

    LimpaPortas()
    check("sem impedimento, nada e reportado", ns.Data.TransmogBlockedBy(71), nil)

    -- RECARGA. E a suspeita mais forte para quem esta TESTANDO: trocar de conjunto varias vezes
    -- seguidas e exatamente o que mantem a recarga de pe.
    state.transmogCooldown = 12
    local motivo = ns.Data.TransmogBlockedBy(71)
    check("a recarga e reportada", motivo ~= nil, true)
    -- A MENSAGEM NAO CONTA MAIS SEGUNDOS, e a troca e deliberada: contar exige `startTime` e
    -- `duration`, que sao SECRET dentro de mitica+ -- e era essa conta que travava tudo.
    check("e o motivo e a recarga", motivo ~= nil, true)

    -- E AS FORMAS QUE NAO SAO RECARGA. A Blizzard exige as TRES condicoes
    -- (`Blizzard_FrameXMLUtil/Cooldown.lua:3`), entao quem olhasse so `duration > 0` acusaria
    -- recarga onde ela nao ha -- e o passo passaria a recusar a troca por conta propria, que e
    -- um defeito PIOR que o original: em vez de nao trocar em silencio, nao trocaria com um
    -- motivo inventado.
    -- `startTime = 0` com uma duracao MAIOR que o relogio. Nao e caso de laboratorio: `GetTime()`
    -- conta desde que o cliente subiu, entao logo depois do login ele vale poucas centenas, e
    -- `0 + duracao - GetTime()` da positivo. Quem nao guardar o `startTime > 0` anuncia uma
    -- recarga inteira que nao existe -- e recusa a troca por um motivo inventado, que e pior que
    -- o defeito original.
    state.transmogCooldown = 1200
    state.cooldownShape = "semInicio"
    check("duration sem startTime NAO e recarga", ns.Data.TransmogBlockedBy(71), nil)
    state.transmogCooldown = 12
    state.cooldownShape = "desligada"
    check("recarga desligada NAO e recarga", ns.Data.TransmogBlockedBy(71), nil)
    state.cooldownShape = "normal"


    -- DENTRO DE MITICA+ OS CAMPOS DE TEMPO VEM OPACOS, e este e o teste que faltava -- o defeito
    -- que ele cobre e o relato inteiro do usuario: "as vezes nao troca, gera erro".
    --
    -- `C_Spell.GetSpellCooldown` e `SecretWhenCooldownsRestricted` (`SpellDocumentation.lua:271`),
    -- e o predicado vale para modo DESAFIO -- a chave inteira, nao so a luta. `startTime` e
    -- `duration` nao sao `NeverSecret`; `isActive` e (`SpellSharedDocumentation.lua:23-30`).
    --
    -- A versao anterior comparava os dois com zero e ainda SOMAVA um ao outro, com uma guarda de
    -- `type` que nao protegia nada: `type()` num secret devolve o TIPO REAL, entao ela passava e
    -- a comparacao estourava. E o estrago nao era a mensagem errada -- erro de Lua ali, com a
    -- corrente ja iniciada e nenhum prazo armado, deixava `running` preso PARA SEMPRE, e todo
    -- clique seguinte voltava MUDO.
    state.cooldownSecret = true
    state.transmogCooldown = 12
    local semEstourar, motivoSecreto = pcall(ns.Data.TransmogBlockedBy, 71)
    check("com campos opacos NAO estoura", semEstourar, true)
    check("e ainda assim reporta a recarga", motivoSecreto ~= nil, true)

    state.transmogCooldown = 0
    local ok2, semRecarga = pcall(ns.Data.TransmogBlockedBy, 71)
    check("e sem recarga, com campos opacos, nao inventa", ok2 and semRecarga, nil)
    state.cooldownSecret = false
    state.transmogCooldown = 12

    LimpaPortas()

    -- EVENTO DE ESTILO: a UI desabilita todo conjunto que nao seja do evento.
    state.inStyleEvent = true
    check("o evento de estilo e reportado", ns.Data.TransmogBlockedBy(71) ~= nil, true)
    LimpaPortas()

    -- CONJUNTO TRAVADO, e SO o conjunto travado: travar um nao pode impedir os outros.
    state.lockedOutfits[71] = true
    check("o conjunto travado e reportado", ns.Data.TransmogBlockedBy(71) ~= nil, true)
    check("e outro conjunto continua livre", ns.Data.TransmogBlockedBy(88), nil)
    LimpaPortas()

    -- `C_Spell` AUSENTE NAO PODE ESTOURAR. `pcall(C_Spell.GetSpellCooldown, ...)` indexa
    -- `C_Spell` ANTES do pcall: o pcall protege a chamada, nao a busca do argumento. Com
    -- `C_Spell` nulo isso e erro de Lua fora da protecao -- pego aqui, nao no jogo.
    local guardado = C_Spell
    C_Spell = nil
    local semErro = pcall(ns.Data.TransmogBlockedBy, 71)
    check("sem C_Spell nao estoura", semErro, true)
    C_Spell = guardado
end

print("== aparencia: a recusa silenciosa vira frase ==")
-- E o pedido de fundo do relato. O passo agora consulta as portas ANTES de chamar, e o relatorio
-- final traz o motivo em vez de "nao deu para aplicar a aparencia".
do
    state.transmogCooldown = 0
    state.inStyleEvent = false
    state.lockedOutfits = {}
    state.outfit = 70

    -- Sem sobrescrever `ChangeToOutfit`: o stub base ja consulta as portas, aplica quando estao
    -- abertas e dispara `TRANSMOG_DISPLAYED_OUTFIT_CHANGED`, que e o que o jogo faz. Sobrescrever
    -- aqui criava uma SEGUNDA versao do jogo dentro do teste, e foi ela que ficou para tras
    -- quando a confirmacao passou a ser por evento.

    -- COM A RECARGA DE PE: o passo tem que falhar DIZENDO a recarga, e nao "nao deu".
    state.transmogCooldown = 9
    local texto, houveErro
    ns.Data.Apply({ name = "So aparencia", transmog = 71 },
        function(t, isError) texto, houveErro = t, isError end)

    check("a troca bloqueada e reportada como erro", houveErro, true)
    check("e o texto traz o motivo, nao um 'nao deu' generico",
        texto and texto:lower():find("recarga") ~= nil, true)

    -- E SEM IMPEDIMENTO NENHUM ele TAMBEM falha, agora -- e essa e a mudanca de fundo da 0.10.0.
    -- O addon nao troca aparencia e nunca pode ter trocado: `ChangeToOutfit` e
    -- `ChangeDisplayedOutfit` sao PROTEGIDAS. Quem troca e o clique do jogador no botao seguro.
    -- O passo continua existindo para DIZER que a aparencia ficou para tras -- sem ele o conjunto
    -- se daria por aplicado com a roupa errada.
    state.transmogCooldown = 0
    state.outfit = 70
    local texto2, houveErro2
    ns.Data.Apply({ name = "So aparencia", transmog = 71 },
        function(t, isError) texto2, houveErro2 = t, isError end)

    check("sem o clique, a aparencia NAO troca", state.outfit, 70)
    check("e o addon diz isso em vez de se dar por pronto", houveErro2, true)
    check("explicando que so o botao troca",
        texto2 and texto2:lower():find("bot\195\163o carregar") ~= nil, true)

    state.outfit = 70
end

print("== um passo que falha NAO derruba os seguintes ==")
-- Relato: "as vezes da erro pra trocar o preset" e "o transmog nao ta funcionando". As duas
-- coisas eram A MESMA: a ordem e spec -> talentos -> itens -> aparencia, e uma falha nos
-- talentos chamava `Finish` na hora. A aparencia e o ULTIMO passo, entao quase nunca chegava a
-- rodar -- parecia que ela nao funcionava, quando na verdade nem era tentada.
--
-- O TESTE MUDOU DE ALVO na 0.10.0, e a razao vale registrar: ele media "a aparencia foi aplicada
-- mesmo com os talentos falhando". Nao pode mais medir isso -- o addon NAO aplica aparencia, a
-- API e protegida. Mas a regra que ele existe para proteger continua inteira, e o passo de ITENS
-- serve para prova-la igualmente bem: ele tambem vem depois dos talentos.
do
    state.specIndex, state.equippedSet = 2, 1
    state.activeLoadout[251] = 11
    state.pendingSet = nil

    -- Talentos falham por motivo do jogo.
    local realCanEdit = C_ClassTalents.CanEditTalents
    C_ClassTalents.CanEditTalents = function() return false, "Voce nao pode fazer isso agora." end

    -- `gear = 3` e nao `1`: o personagem ja esta com o 1, e passo que nao tem o que fazer PULA --
    -- o teste mediria o proprio estado inicial em vez de medir a corrente.
    local texto, houveErro
    ns.Data.Apply({ name = "Frost PvP", spec = 2, talent = 10, gear = 3 },
        function(t, isError) texto, houveErro = t, isError end)

    check("os itens foram aplicados mesmo com os talentos falhando", state.pendingSet, 3)
    fire("EQUIPMENT_SWAP_FINISHED", true, 3)

    check("e o addon avisou que algo falhou", houveErro, true)
    check("a mensagem diz o motivo que o JOGO deu",
        texto and texto:find("Voce nao pode fazer isso agora.", 1, true) ~= nil, true)
    check("e diz que o resto foi aplicado",
        texto and texto:find("Frost PvP", 1, true) ~= nil, true)

    C_ClassTalents.CanEditTalents = realCanEdit
end

print("== o motivo vem do jogo, nao da nossa frase generica ==")
-- `LoadConfig` devolve TRES valores -- `result, changeError, newLearnedNodeIDs` -- e o codigo
-- capturava so o primeiro, jogando fora justamente a string que diz por que nao deu.
do
    state.specIndex, state.activeLoadout[251] = 2, 11
    state.outfit = nil

    local realLoad = C_ClassTalents.LoadConfig
    C_ClassTalents.LoadConfig = function()
        return 0, "Nao e possivel trocar talentos aqui."      -- Error + motivo
    end

    local texto
    ns.Data.Apply({ name = "Tank", spec = 2, talent = 10 },
        function(t) texto = t end)

    check("o motivo do jogo chega ao jogador",
        texto and texto:find("Nao e possivel trocar talentos aqui.", 1, true) ~= nil, true)

    C_ClassTalents.LoadConfig = realLoad
end

print("== aparencia: o addon NAO troca, o clique troca ==")
-- ESTE E O BLOCO QUE MUDOU DE VERDADE NA 0.10.0, e vale registrar como se chegou aqui: tres
-- rodadas de teste in-game do usuario, "nao troca e nao gera nenhum erro" nas tres. A resposta nao
-- estava em nada dedutivel do codigo:
--
--   * dos 117 addons instalados, NENHUM chama `ChangeToOutfit` nem `ChangeDisplayedOutfit`. O
--     unico que troca aparencia, o `EnhanceQoLQuickActions`, monta um BOTAO SEGURO
--     (`Runtime.lua:4544,4593-4595`);
--   * o autor do Plumber: "The API to activate outfit C_TransmogOutfitInfo.ChangeDisplayedOutfit
--     is protected";
--   * o patch 12.0.5 adicionou uma acao segura `"outfit"` justamente para isso.
--
-- Ou seja: as duas portas que eu tentei sao PROTEGIDAS, e a terceira rodada nao teria acontecido
-- se eu tivesse procurado prior art no parque de addons antes de teorizar sobre a API.
do
    -- ESTADO EXPLICITO, e nao paridade de `Toggle`. Abrir sem fechar inverte o comportamento de
    -- todos os blocos seguintes, e o defeito aparece longe de onde nasceu -- foi o que aconteceu
    -- ao escrever este bloco: um teste de "estado vazio" trinta linhas abaixo comecou a falhar.
    if not ns.UI.IsShown() then ns.UI.Toggle() end

    ns.db.presets = {}
    ns.UI.Refresh()
    ns.UI.New()
    local comAparencia = ns.UI.Selected()
    comAparencia.name, comAparencia.transmog = "Com aparencia", 71
    ns.UI.New()
    local semAparencia = ns.UI.Selected()
    semAparencia.name, semAparencia.transmog = "Sem aparencia", nil
    ns.UI.Refresh()

    local function BotaoDe(indice)
        local list = ns.UI.DebugList and ns.UI.DebugList()
        return list and list.__rows and list.__rows[indice] and list.__rows[indice].load
    end

    local botao = BotaoDe(1)
    check("a linha tem botao de carregar", botao ~= nil, true)

    -- O BOTAO CARREGA A ACAO SEGURA. E o unico caminho que existe.
    check("o botao declara a acao de aparencia", botao.__attrs and botao.__attrs.type, "outfit")
    check("com o INDICE do conjunto, nao o id",
        botao.__attrs["outfit-index"], ns.Data.OutfitIndex(71))

    -- `change`, e NAO `toggle`. Em `SECURE_ACTIONS.outfit` o `toggle` vira
    -- `allowRemoveOutfit = true`, e ai pedir a aparencia que ja esta posta e tratado como LIMPAR
    -- (`SlashCommands.lua:1714`) -- carregar duas vezes o mesmo conjunto TIRARIA a roupa na
    -- segunda. E o tipo de defeito que so aparece no segundo clique.
    check("pedindo trocar, nao alternar", botao.__attrs.action, "change")

    -- CONJUNTO SEM APARENCIA desarma o botao. Deixar `type` armado com indice nulo faria o clique
    -- cair no ramo de outfit e nao fazer nada, em silencio.
    local botao2 = BotaoDe(2)
    check("conjunto sem aparencia nao arma nada", botao2.__attrs.type, nil)
    check("e nem deixa indice para tras", botao2.__attrs["outfit-index"], nil)

    -- APARENCIA APAGADA DO JOGO tambem desarma: o indice nao resolve mais.
    comAparencia.transmog = 999
    ns.UI.Refresh()
    check("aparencia que nao existe mais desarma o botao", BotaoDe(1).__attrs.type, nil)
    comAparencia.transmog = 71
    ns.UI.Refresh()
    check("e volta a armar quando ela existe", BotaoDe(1).__attrs.type, "outfit")

    -- EM COMBATE NAO SE MEXE em atributo de frame seguro -- e erro de Lua, nao aviso.
    state.inCombat = true
    comAparencia.transmog = nil
    ns.UI.Refresh()
    check("em combate o atributo NAO e tocado", BotaoDe(1).__attrs.type, "outfit")
    state.inCombat = false
    comAparencia.transmog = 71
    ns.UI.Refresh()

    -- O `UI.Load` TEM QUE DIZER que veio do clique. Ele e chamado do `PostClick` do botao seguro,
    -- ou seja a acao de aparencia JA foi disparada -- e sem essa bandeira o passo de aparencia
    -- confere na hora e acusa falha numa troca que esta a caminho. A bandeira e um argumento
    -- solto: e o tipo de coisa que se perde numa refatoracao sem nada acusar.
    state.specIndex, state.equippedSet, state.activeLoadout[251] = 2, 1, 10
    state.outfit = 70
    comAparencia.spec, comAparencia.talent, comAparencia.gear = 2, 10, 1
    ns.UI.Load(comAparencia)
    check("o clique manda a corrente ESPERAR a aparencia", ns.Data.IsApplying(), true)
    state.outfit = 71
    fire("TRANSMOG_DISPLAYED_OUTFIT_CHANGED")
    check("e a resposta fecha a corrente", ns.Data.IsApplying(), false)
    state.outfit = nil

    -- Deixa a janela FECHADA, que e como este bloco a encontrou.
    if ns.UI.IsShown() then ns.UI.Toggle() end
end

print("== aparencia: o passo confere e diz a verdade ==")
-- O passo continua na corrente mesmo sem poder agir, e o motivo e concreto: sem ele o conjunto se
-- daria por aplicado com a roupa errada. Antes ele CHAMAVA e mentia sobre poder; agora CONFERE.
do
    state.specIndex, state.equippedSet, state.activeLoadout[251] = 2, 1, 10

    -- QUANDO O CLIQUE PEGOU, o passo nao tem o que reclamar: a aparencia ja e a certa.
    --
    -- `gear = 3` de proposito: com tudo igual a corrente nem comeca ("nada a fazer"), e o teste
    -- mediria essa recusa em vez de medir o passo de aparencia.
    state.outfit = 71
    local houveErro1
    ns.Data.Apply({ name = "So aparencia", spec = 2, talent = 10, gear = 3, transmog = 71 },
        function(_, isError) if isError then houveErro1 = true end end)
    fire("EQUIPMENT_SWAP_FINISHED", true, 3)
    check("aparencia ja aplicada nao vira aviso", houveErro1, nil)
    state.equippedSet = 1

    -- QUANDO NAO PEGOU, ele diz -- e diz que quem troca e o botao.
    state.outfit = 70
    local texto, houveErro
    ns.Data.Apply({ name = "So aparencia", transmog = 71 },
        function(t, isError) texto, houveErro = t, isError end)
    check("aparencia que ficou para tras e reportada", houveErro, true)
    check("dizendo que so o botao troca",
        texto and texto:lower():find("bot\195\163o carregar") ~= nil, true)

    -- VINDO DO CLIQUE, ELE ESPERA em vez de acusar na hora. A acao segura roda no clique e o
    -- servidor responde depois; com os tres passos anteriores sem nada a fazer, a corrente chega
    -- aqui no MESMO quadro. Conferir na hora transformaria uma troca que funciona num aviso de
    -- falha -- pior que o defeito original, e era o que a primeira versao desta verificacao fazia.
    state.outfit = 70
    local vereditoClique
    ns.Data.Apply({ name = "So aparencia", transmog = 71 },
        function(_, isError) if isError ~= nil then vereditoClique = isError end end, true)
    check("vindo do clique, o passo ESPERA", ns.Data.IsApplying(), true)
    check("e nao deu veredito ainda", vereditoClique, false)

    -- E a resposta que chega fecha o passo, sem reclamacao.
    state.outfit = 71
    fire("TRANSMOG_DISPLAYED_OUTFIT_CHANGED")
    check("a resposta do servidor fecha o passo", ns.Data.IsApplying(), false)
    check("sem acusar falha", vereditoClique, false)

    -- E se a resposta NAO vier, o prazo reporta -- a espera nao pode ser eterna.
    state.outfit = 70
    local erroPrazo
    ns.Data.Apply({ name = "So aparencia", transmog = 71 },
        function(_, isError) if isError then erroPrazo = true end end, true)
    RunTimers()
    check("e sem resposta o prazo reporta", erroPrazo, true)

    -- E UMA PORTA FECHADA explica melhor que a frase geral: o clique seguro passa pelas MESMAS
    -- portas (recarga da magia 1247613, evento de estilo, conjunto travado), entao elas explicam
    -- tambem o clique que nao pegou.
    state.outfit = 70
    state.transmogCooldown = 9
    local texto2
    ns.Data.Apply({ name = "So aparencia", transmog = 71 },
        function(t) texto2 = t end)
    check("porta fechada explica melhor que a frase geral",
        texto2 and texto2:lower():find("recarga") ~= nil, true)
    state.transmogCooldown = 0

    -- APARENCIA APAGADA continua sendo o seu proprio motivo.
    state.outfit = 70
    local texto3
    ns.Data.Apply({ name = "So aparencia", transmog = 999 },
        function(t) texto3 = t end)
    check("aparencia apagada diz que nao existe mais",
        texto3 and texto3:lower():find("n\195\163o existe mais") ~= nil, true)

    state.outfit = nil
end


print("== talento nao entra na spec errada ==")
-- Relato de 07/09: "cliquei para trocar para o preset de tank e ja gerou erro e fez coisa
-- errada". O conjunto Tank pede spec 1; o jogador estava na 2.
--
-- Um loadout pertence a UMA especializacao. O passo resolvia pela spec ATUAL, entao quando a
-- troca de spec falhava, estourava o prazo, ou simplesmente ainda nao tinha virado, ele pegava a
-- spec VELHA e mandava `LoadConfig` com um id de OUTRA -- e o jogo reclama, com razao.
--
-- E o pior vinha depois: `UpdateLastSelectedSavedConfigID(specVelha, loadoutDaNova)` grava a
-- associacao errada NO JOGO. Isso sobrevive ao `/reload` e reaparece na proxima vez que o jogador
-- voltar aquela spec pela janela de talentos. E corromper estado alheio.
do
    state.specIndex = 2                    -- o jogador esta em Gelido
    state.activeLoadout[250] = nil         -- e a spec de Sangue nao tem loadout ativo
    state.activeLoadout[251] = 10
    state.pendingLoadout, state.pendingSpec = nil, nil

    -- A TROCA DE SPEC FALHA (o jogo recusa na hora).
    -- A SPEC E RECUSADA DE FORMA DEFINITIVA aqui (o jogo diz que nao da), e nao com o `false` do
    -- `SetSpecialization` -- esse agora faz o addon INSISTIR, e insistir e o comportamento certo.
    -- O que este bloco mede e outra coisa: sem a spec certa, o talento nao pode entrar.
    state.canChangeSpec = false

    local texto, houveErro
    ns.Data.Apply({ name = "Tank", spec = 1, talent = 11, gear = 3 },
        function(t, isError) texto, houveErro = t, isError end)

    state.canChangeSpec = true

    check("com a spec errada, o talento NAO e pedido", state.pendingLoadout, nil)
    check("e a memoria do jogo nao e corrompida", state.activeLoadout[251], 10)
    check("o addon avisa", houveErro, true)
    check("dizendo que a spec nao trocou",
        texto and texto:lower():find("especializa", 1, true) ~= nil, true)

    -- E OS ITENS SEGUEM: falhar a spec nao pode impedir o que ainda da para aplicar.
    check("mas os itens foram aplicados", state.pendingSet, 3)
end

print("== a corrente nao fecha passo com evento alheio ==")
-- Estes eventos sao GLOBAIS: disparam quando o JOGADOR mexe a mao, quando outro addon mexe, e --
-- o caso mais comum -- quando a propria troca de spec os enfileira. Fechar um passo com o evento
-- errado e "X esta pronto" com os talentos antigos.
do
    state.specIndex, state.equippedSet, state.activeLoadout[251] = 2, 1, 10
    state.pendingSet, state.pendingLoadout = nil, nil

    -- TALENTOS: o evento FECHA o passo, e isso e uma retirada deliberada.
    --
    -- A 0.13.0 filtrou pelo `configID`, porque a Blizzard avisa que a gravacao gera evento para o
    -- config base E depois para o loadout (`Blizzard_ClassTalentsFrame.lua:407-411`). Mas a fonte
    -- nao diz QUAL dos dois fecha, e o filtro recusou o que funcionava: o passo esperava ate o
    -- prazo. O usuario sentiu como "apertei duas, tres vezes pra funcionar".
    --
    -- Trocar um caminho que funciona por um palpite mais preciso e o pior negocio possivel. O
    -- diario grava o `arg1` de cada evento; quando houver dado, decide-se com dado.
    state.activeLoadout[251] = 10
    ns.Data.Apply({ name = "So talento", spec = 2, talent = 11 }, function() end)
    check("o passo de talentos esperou", ns.Data.IsApplying(), true)

    gravacaoTermina(999)
    check("o evento fecha o passo", ns.Data.IsApplying(), false)

    -- E A ESCRITA DE "QUAL LOADOUT VALE" SO ACONTECE DEPOIS DA CONFIRMACAO. Feita antes, e como o
    -- estado alheio foi corrompido -- e ela ainda envenenava a propria confirmacao, porque o
    -- addon escrevia a resposta e depois a lia como prova.
    check("e so entao o jogo registra o loadout", state.activeLoadout[251], 11)

    -- COM A SPEC ERRADA ELA NAO ACONTECE, nem mesmo na confirmacao: um loadout pertence a uma
    -- especializacao, e grava-lo em outra corrompe estado que sobrevive ao /reload.
    state.activeLoadout[250] = nil
    state.specIndex = 2
    ns.Data.Apply({ name = "Tank", spec = 1, talent = 12 }, function() end)
    fire("TRAIT_CONFIG_UPDATED", 999)
    check("spec errada nao grava nada", state.activeLoadout[251], 11)
    check("nem na spec alvo", state.activeLoadout[250], nil)

    -- FECHA A CORRENTE que este trecho deixou esperando a spec. Bloco de teste que sai deixando
    -- corrente aberta faz o SEGUINTE receber "ja ha uma troca em curso" -- e o defeito aparece
    -- longe de onde nasceu, que foi exatamente o que aconteceu ao escrever isto.
    state.specIndex = 1
    fire("ACTIVE_PLAYER_SPECIALIZATION_CHANGED")
    RunTimers()
    state.specIndex = 2
    check("a corrente anterior foi fechada", ns.Data.IsApplying(), false)

    -- ITENS: o payload e `result, setID`. Trocar de spec faz o jogo equipar sozinho o conjunto
    -- amarrado aquela spec, e o evento DESSA troca fechava o nosso passo antes do nosso entrar.
    state.equippedSet, state.activeLoadout[251] = 1, 10
    ns.Data.Apply({ name = "So itens", gear = 3 }, function() end)
    check("o passo de itens esperou", ns.Data.IsApplying(), true)

    fire("EQUIPMENT_SWAP_FINISHED", true, 7)   -- conjunto alheio
    check("evento de OUTRO conjunto nao fecha o passo", ns.Data.IsApplying(), true)

    fire("EQUIPMENT_SWAP_FINISHED", true, 3)
    check("e o do nosso conjunto fecha", ns.Data.IsApplying(), false)

    -- E UM `false` ALHEIO NAO MATA A CORRENTE. Antes ele chamava `Finish` e levava junto os
    -- passos seguintes e as falhas ja anotadas.
    state.equippedSet, state.activeLoadout[251] = 1, 10
    local texto, houveErro
    ns.Data.Apply({ name = "Itens e mais", gear = 3 },
        function(t, isError) texto, houveErro = t, isError end)
    fire("EQUIPMENT_SWAP_FINISHED", false, 3)
    check("falha nos itens vira anotacao, nao fim abrupto", houveErro, true)
    check("e a corrente chegou ao fim", ns.Data.IsApplying(), false)

    -- CAST DE SPEC QUE FALHA FORA DO NOSSO PASSO nao pode matar a corrente. Era o unico ramo sem
    -- guarda de passo: o clique do proprio jogador na janela de talentos derrubava a troca.
    state.equippedSet, state.activeLoadout[251] = 1, 10
    ns.Data.Apply({ name = "So itens", gear = 3 }, function() end)
    check("corrente em curso no passo de itens", ns.Data.IsApplying(), true)
    fire("SPECIALIZATION_CHANGE_CAST_FAILED")
    check("cast de spec alheio NAO mata a corrente", ns.Data.IsApplying(), true)
    fire("EQUIPMENT_SWAP_FINISHED", true, 3)
end

print("== erro num passo nao deixa o addon mudo ==")
-- O PIOR DEFEITO QUE ESTA CORRENTE TEVE, e ele explica o relato inteiro: um erro de Lua dentro
-- de um passo subia pelo `RunNext` e NADA zerava `running` -- so o `Finish`. A partir dai todo
-- clique em Carregar voltava mudo, porque `Data.Apply` recusa quando ha corrente em curso.
do
    state.specIndex, state.equippedSet, state.activeLoadout[251] = 2, 1, 10

    -- Estoura numa chamada que o passo faz SEM `pcall` -- `UseEquipmentSet` ja tem o dele, entao
    -- sabotar ela testaria a protecao errada. `EquipmentSetContainsLockedItems` e uma das duas
    -- chamadas nuas que a auditoria apontou (`Data.lua:514`).
    local realLocked = C_EquipmentSet.EquipmentSetContainsLockedItems
    C_EquipmentSet.EquipmentSetContainsLockedItems = function() error("estouro de proposito") end

    local texto, houveErro
    ns.Data.Apply({ name = "Vai estourar", gear = 3 },
        function(t, isError) texto, houveErro = t, isError end)

    check("o erro nao derruba o addon", houveErro, true)
    check("e a corrente NAO fica presa", ns.Data.IsApplying(), false)

    C_EquipmentSet.EquipmentSetContainsLockedItems = realLocked

    -- E O CLIQUE SEGUINTE FUNCIONA. Era isto que o jogador via como "o botao parou".
    state.equippedSet = 1
    local voltou = ns.Data.Apply({ name = "Agora vai", gear = 3 }, function() end)
    check("o clique seguinte volta a funcionar", voltou, true)
    fire("EQUIPMENT_SWAP_FINISHED", true, 3)

    -- E RECUSAR POR JA HAVER TROCA EM CURSO agora AVISA, em vez de voltar em silencio.
    state.equippedSet, state.activeLoadout[251] = 1, 10
    ns.Data.Apply({ name = "Primeira", gear = 3 }, function() end)
    local aviso
    ns.Data.Apply({ name = "Segunda", gear = 4 }, function(t, isError)
        if isError then aviso = t end
    end)
    check("o segundo clique e avisado, nao ignorado", aviso ~= nil, true)
    fire("EQUIPMENT_SWAP_FINISHED", true, 3)
end

print("== o erro vermelho do jogo nao aparece pela nossa chamada ==")
-- Relato: "quando troco o preset aparece uma mensagem do jogo mesmo 'Voce nao pode fazer isso
-- agora', vai confundir o usuario, ele vai achar que nao vai trocar nada, mas ta funcionando".
--
-- Ele esta certo: a recusa e TRANSITORIA e o addon ja insiste sozinho, entao o erro do jogo
-- descreve um estado que deixa de valer quatro segundos depois. Vermelho na tela dizendo "nao
-- pode" enquanto o addon resolve e contradicao pura.
--
-- `SuppressMessagesThisFrame` e da propria Blizzard e vale por UM QUADRO, desarmando sozinho
-- (`UIErrorsFrame.lua:182-189`). Nao e `UnregisterEvent`, que apagaria erro alheio por tempo
-- indeterminado -- o que se engole aqui e so o que a nossa linha seguinte provoca.
do
    state.specIndex, state.equippedSet = 2, 1
    state.canChangeSpec = true
    suppressedFrames = 0

    ns.Data.Apply({ name = "Tank", spec = 1 }, function() end)

    check("suprime o quadro da propria chamada", suppressedFrames >= 1, true)

    state.specIndex = 1
    fire("ACTIVE_PLAYER_SPECIALIZATION_CHANGED")

    -- E SO QUANDO CHAMA. Passo que nem tenta trocar de spec nao pode apagar erro nenhum -- o
    -- jogador tem direito aos erros que nao sao culpa nossa.
    suppressedFrames = 0
    ns.Data.Apply({ name = "So itens", gear = 3 }, function() end)
    check("mas nao suprime quando nem tenta", suppressedFrames, 0)
    fire("EQUIPMENT_SWAP_FINISHED", true, 3)
end

print("== o atalho do minimapa nao faz troca PARCIAL ==")
-- Relato: "quando abro pela primeira vez ele, do nada ele seta o item que ja deveria estar
-- setado". O atalho do minimapa (botao direito) aplicava o ultimo conjunto -- mas ele NAO e um
-- clique seguro, entao a aparencia nunca entrava. Consequencia em cadeia:
--
--   1. sem a aparencia, `IsLoaded` nunca dava verdadeiro;
--   2. com `IsLoaded` falso, o atalho REAPLICAVA tudo a cada uso;
--   3. e a troca era parcial, que e o pior dos dois mundos.
do
    ns.db.presets = {
        { name = "Com roupa", spec = 2, gear = 3, transmog = 71 },
        { name = "Sem roupa", spec = 2, gear = 4 },
    }
    state.specIndex, state.equippedSet = 2, 1
    state.pendingSet = nil
    if ns.UI.IsShown() then ns.UI.Toggle() end

    -- CONJUNTO COM APARENCIA: abre a janela em vez de aplicar pela metade.
    ns.db.last = "Com roupa"
    ns.LoadLast()
    check("nao aplica pela metade", state.pendingSet, nil)
    check("abre a janela", ns.UI.IsShown(), true)
    check("com o conjunto selecionado", ns.UI.Selected() and ns.UI.Selected().name, "Com roupa")

    -- CONJUNTO SEM APARENCIA: o atalho continua valendo, porque ali ele faz a troca INTEIRA.
    if ns.UI.IsShown() then ns.UI.Toggle() end
    ns.db.last = "Sem roupa"
    ns.LoadLast()
    check("sem aparencia, o atalho aplica mesmo", state.pendingSet, 4)
    fire("EQUIPMENT_SWAP_FINISHED", true, 4)
end

print("== o botao direito do minimapa LISTA, nao troca ==")
-- (!) RELATO DE USUARIO, COM VIDEO (23/09): "quando ele clica com o direito no icone do minimap
-- ta trocando a spec sozinha". Estava certo -- o direito chamava `LoadLast()`, que aplica.
--
-- E o desenvolvedor NAO conseguia reproduzir, por um motivo que estava no dado e nao no codigo:
-- TODOS os conjuntos dele tem aparencia, e conjunto com aparencia cai no ramo que abre a janela
-- em vez de aplicar. O dado dele escondia o defeito. Por isso o teste abaixo usa conjunto SEM
-- aparencia: e a unica forma de medir o que o usuario via.
do
    ns.db.presets = {
        -- Os dois na spec ATUAL de proposito: assim o passo de itens roda na hora e da para
        -- ler `pendingSet`. Com spec diferente a troca fica esperando o evento, e o teste
        -- mediria o relogio em vez de medir a escolha do menu.
        { name = "Primeiro", spec = 2, gear = 3 },
        { name = "Segundo", spec = 2, gear = 4 },
    }
    ns.db.last = "Primeiro"
    state.specIndex, state.equippedSet = 2, 1
    state.pendingSet = nil
    if ns.UI.IsShown() then ns.UI.Toggle() end
    MENU = nil

    ns.Minimap.Menu(nil)
    check("o direito monta um menu", MENU ~= nil, true)
    check("  e NAO troca nada ao abrir", state.pendingSet, nil)
    check("  listando todos os conjuntos", #MENU.itens, 2)
    check("  pelo titulo, na ordem", MENU.itens[1].texto .. "/" .. MENU.itens[2].texto,
        "Primeiro/Segundo")

    -- (!) E A TROCA SO ACONTECE NO ITEM ESCOLHIDO. Este e o par do teste acima: sem ele,
    -- "nao troca ao abrir" seria satisfeito por um menu que nao troca nunca.
    MENU.itens[2].acao()
    check("escolher um item troca para ELE", state.pendingSet, 4)
    fire("EQUIPMENT_SWAP_FINISHED", true, 4)

    -- (!) E PELO BOTAO DE VERDADE, nao chamando `Menu()` na mao.
    --
    -- A primeira versao destes testes chamava `ns.Minimap.Menu(nil)` direto, e a sabotagem
    -- denunciou: religar o clique direito em `LoadLast()` passava limpo. O menu estava provado;
    -- a LIGACAO entre o botao e ele, nao -- que e exatamente o que o usuario reportou.
    state.pendingSet = nil
    MENU = nil
    local botao = ns.Minimap.Create()
    botao.__scripts.OnClick(botao, "RightButton")
    check("o clique direito de verdade abre o menu", MENU ~= nil, true)
    check("  e nao troca nada", state.pendingSet, nil)

    -- E o esquerdo continua abrindo a janela.
    if ns.UI.IsShown() then ns.UI.Toggle() end
    botao.__scripts.OnClick(botao, "LeftButton")
    check("o esquerdo abre a janela", ns.UI.IsShown(), true)
    if ns.UI.IsShown() then ns.UI.Toggle() end

    -- Sem o menu novo do cliente, o direito abre a janela -- e nunca aplica pelas costas.
    local salvo = MenuUtil
    MenuUtil = nil
    state.pendingSet = nil
    if ns.UI.IsShown() then ns.UI.Toggle() end
    ns.Minimap.Menu(nil)
    check("cliente sem menu: abre a janela", ns.UI.IsShown(), true)
    check("  e mesmo assim nao troca", state.pendingSet, nil)
    MenuUtil = salvo

    -- Sem conjunto nenhum nao ha o que listar: idem.
    if ns.UI.IsShown() then ns.UI.Toggle() end
    local presets = ns.db.presets
    ns.db.presets = {}
    ns.Minimap.Menu(nil)
    check("sem conjuntos: abre a janela", ns.UI.IsShown(), true)
    ns.db.presets = presets
    if ns.UI.IsShown() then ns.UI.Toggle() end
end

print("== a recarga da magia de trocar de spec ==")
-- O DIARIO DO USUARIO MATOU A MINHA HIPOTESE ANTERIOR. Eu tinha usado
-- `C_SpecializationInfo.CanPlayerUseTalentSpecUI()`, que e o que a janela de talentos do jogo usa
-- para habilitar o botao "Ativar". Mas os numeros mostram que ela nao cobre este caso:
--
--   02:20:12  SetSpecialization(2) -> true    (sucesso)
--   02:20:22  SetSpecialization(1) -> false   (10s depois: recusado)
--   02:28:18  SetSpecialization(2) -> true    (sucesso)
--   02:28:26  SetSpecialization(1) -> false   ( 8s depois: recusado)
--
-- E o diario de 02:28:26 nao tem linha de bloqueio antes da chamada -- ou seja,
-- `CanPlayerUseTalentSpecUI` respondeu SIM e o jogo recusou assim mesmo. Aquela pergunta e sobre a
-- INTERFACE estar utilizavel, nao sobre a troca estar disponivel.
--
-- Quem responde e a RECARGA DA MAGIA de ativar especializacao. Nao ha constante para o id dela no
-- cliente, entao o addon o aprende com o jogo: `IsSpecializationActivateSpell` e o predicado que a
-- propria janela de talentos usa para reconhecer o cast dela.
do
    RocketSwapLogDB = RocketSwapLogDB or {}
    RocketSwapLogDB.specSpellID = nil
    state.canChangeSpec = true
    state.specSpellOnCooldown = true

    -- ANTES DE APRENDER o id nao da para consultar a recarga, e o addon nao inventa: segue
    -- deixando tentar, como fazia.
    check("sem conhecer a magia, nao bloqueia", ns.Data.CanChangeSpec(), true)

    -- APRENDE COM O JOGO: um cast do jogador termina, o predicado confirma que era o de spec.
    fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", state.specSpellID)
    check("aprendeu o id da magia", RocketSwapLogDB.specSpellID, state.specSpellID)

    -- E AGORA A RECARGA RESPONDE, que e o caso do relato.
    check("com a magia em recarga, nao deixa trocar", ns.Data.CanChangeSpec(), false)
    state.specSpellOnCooldown = false
    check("e passada a recarga, deixa", ns.Data.CanChangeSpec(), true)

    -- CAST DE OUTRA MAGIA nao vira o id: aprender errado seria pior que nao aprender.
    RocketSwapLogDB.specSpellID = nil
    fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-2", 12345)
    check("cast de outra magia nao e confundido", RocketSwapLogDB.specSpellID, nil)

    -- E CAST DE OUTRA UNIDADE tambem nao.
    fire("UNIT_SPELLCAST_SUCCEEDED", "target", "cast-3", state.specSpellID)
    check("cast de outra unidade nao conta", RocketSwapLogDB.specSpellID, nil)

    -- SECRET NAO VIRA ID. `UNIT_SPELLCAST_SUCCEEDED` e `SecretWhenUnitSpellCastRestricted`
    -- (`UnitDocumentation.lua:4702`): sob restricao o `spellID` vem opaco, e guardar isso em
    -- SavedVariables e caminho certo para erro.
    local guardado = issecretvalue
    issecretvalue = function(v) return v == "opaco" end
    ns.Data.NoteSpellCast("opaco")
    issecretvalue = guardado
    check("spellID opaco nao e guardado", RocketSwapLogDB.specSpellID, nil)

    fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-4", state.specSpellID)
    state.specSpellOnCooldown = false
end

print("== botao apagado quando o jogo nao deixa trocar de spec ==")
-- Ideia do usuario, depois de receber a mensagem de recusa: "se houver isso, tem que desabilitar
-- os botoes de carregar preset ate que possa ser feito". Ele esta certo -- botao que aceita
-- clique e depois responde "nao deu" e pior que botao apagado.
--
-- A condicao e a MESMA que a janela de talentos do jogo usa
-- (`C_SpecializationInfo.CanPlayerUseTalentSpecUI`), e ela devolve o motivo em texto, ja
-- traduzido pelo cliente. Antes o addon descobria a recusa CHAMANDO e levando nao.
do
    if not ns.UI.IsShown() then ns.UI.Toggle() end
    ns.db.presets = {}
    ns.UI.Refresh()

    ns.UI.New()
    local trocaSpec = ns.UI.Selected()
    trocaSpec.name, trocaSpec.spec, trocaSpec.gear = "Tank", 1, 3

    ns.UI.New()
    local soItens = ns.UI.Selected()
    soItens.name, soItens.spec, soItens.gear = "So itens", nil, 4

    state.specIndex = 2                  -- o conjunto Tank precisa TROCAR de spec
    state.canChangeSpec = false
    ns.UI.Refresh()

    local function BotaoDe(i)
        local list = ns.UI.DebugList and ns.UI.DebugList()
        return list and list.__rows and list.__rows[i] and list.__rows[i].load
    end

    check("o botao do conjunto que troca spec fica apagado",
        BotaoDe(1).__enabled, false)
    check("e diz por que, com o texto do jogo",
        BotaoDe(1).blockedReason, state.cannotChangeReason)

    -- SO O QUE DEPENDE DA SPEC. Apagar todos seria punir o inocente: um conjunto que so mexe em
    -- itens nao tem por que ficar bloqueado por uma restricao de especializacao.
    check("mas o que nao troca spec segue clicavel", BotaoDe(2).__enabled, true)
    check("e sem motivo pendurado", BotaoDe(2).blockedReason, nil)

    -- E VOLTA quando o jogo deixa -- apagado sem reavaliar seria pior que nao apagar.
    state.canChangeSpec = true
    ns.UI.Refresh()
    check("liberou, o botao volta", BotaoDe(1).__enabled, true)
    check("e o motivo some", BotaoDe(1).blockedReason, nil)

    -- E O PASSO USA A MESMA REGRA. Se a interface e o passo divergirem, o botao fica clicavel e a
    -- troca falha assim mesmo -- que e exatamente o que o usuario viveu.
    state.canChangeSpec = false
    state.pendingSpec = nil          -- limpa a sonda: interessa se ESTA corrente mexeu
    local texto, houveErro
    ns.Data.Apply({ name = "Tank", spec = 1, gear = 3 },
        function(t, isError) texto, houveErro = t, isError end)
    check("o passo tambem recusa antes de chamar", houveErro, true)
    check("com o motivo do jogo, nao com a nossa frase", texto, state.cannotChangeReason)
    check("e sem ter mexido em nada", state.pendingSpec, nil)

    state.canChangeSpec = true
    if ns.UI.IsShown() then ns.UI.Toggle() end
end

print("== a troca de itens confirma pelo EVENTO, nao pelo estado ==")
-- ESTE TESTE E A TRANSCRICAO DE OITO SEGUNDOS DO DIARIO DO USUARIO, 07/09 02:05:34-45:
--
--   02:05:34  passo   passo=gear  resultado=wait
--   02:05:35  evento  EQUIPMENT_SWAP_FINISHED  passoEmCurso=gear  paraNos=true  extra=true
--   02:05:37  recusado  motivo=ja ha uma troca em curso
--   02:05:40  recusado  ...  (e assim por mais oito segundos)
--
-- O jogo confirmou a troca COM SUCESSO e a corrente nao avancou. A 0.13.2 exigia, alem do
-- evento, que `Data.IsGearSetEquipped(preset.gear)` ja respondesse verdadeiro -- e no instante do
-- evento ele ainda respondia falso. A partir dali todo clique do jogador batia em "ja ha uma
-- troca em curso".
--
-- A LICAO E A MESMA DO RAMO DE TALENTOS, duas versoes antes: o estado do jogo pode ATRASAR em
-- relacao ao evento, e exigir que ele ja tenha virado transforma a confirmacao em armadilha. Foi
-- a segunda vez que troquei um caminho que funcionava por um palpite mais "honesto".
do
    state.specIndex, state.equippedSet, state.activeLoadout[251] = 2, 1, 10
    state.pendingSet = nil

    ns.Data.Apply({ name = "So itens", gear = 3 }, function() end)
    check("o passo de itens esperou", ns.Data.IsApplying(), true)

    -- O ESTADO AINDA NAO VIROU quando o evento chega -- e este e o ponto do teste.
    state.equippedSet = 1
    fire("EQUIPMENT_SWAP_FINISHED", true, 3)

    check("o evento fecha o passo mesmo com o estado atrasado", ns.Data.IsApplying(), false)

    -- E O CLIQUE SEGUINTE FUNCIONA. Era isto que o jogador vivia como "dei um clique e deu erro":
    -- a corrente presa recusava tudo depois.
    state.equippedSet = 1
    local voltou = ns.Data.Apply({ name = "De novo", gear = 3 }, function() end)
    check("o clique seguinte nao e recusado", voltou, true)
    fire("EQUIPMENT_SWAP_FINISHED", true, 3)
end

print("== o que o DIARIO REAL mostrou (07/09, 02:05) ==")
-- Estes tres testes nao saem de deducao: saem do arquivo que o usuario gerou jogando, lido em
-- `WTF/Account/.../SavedVariables/RocketSwap.lua`. Vinte e uma linhas, nove trocas.
do
    state.specIndex, state.equippedSet = 2, 1
    state.activeLoadout[251] = nil

    -- 1. `LoadConfig` DEVOLVE `NoChangesNecessary` NA MAIORIA DAS VEZES -- seis das nove trocas
    --    gravadas. Faz sentido: os nos da arvore ja estavam iguais.
    --
    --    E nesse caminho o passo nao espera evento nenhum. A 0.13.2 so registrava o loadout na
    --    confirmacao POR EVENTO, entao o jogo nunca ficava sabendo qual passou a valer: a janela
    --    de talentos seguia marcando o anterior, `IsLoaded` nunca dava verdadeiro, o check nao
    --    aparecia, e o jogador clicava de novo. E o "nao chega a trocar tudo certo".
    local realLoad = C_ClassTalents.LoadConfig
    C_ClassTalents.LoadConfig = function() return 1, nil, {} end   -- NoChangesNecessary

    ns.Data.Apply({ name = "So talento", spec = 2, talent = 11 }, function() end)

    check("sem mudanca a fazer, a corrente fecha na hora", ns.Data.IsApplying(), false)
    check("e o jogo REGISTRA qual loadout passou a valer", state.activeLoadout[251], 11)

    C_ClassTalents.LoadConfig = realLoad

    -- 2. `SetSpecialization` DEVOLVE `false` quando a troca vem logo depois de outra -- quatro das
    --    nove. Trocar de spec tem custo no jogo, e insistir nao adianta.
    state.activeLoadout[251] = 11
    state.pendingSet = nil          -- limpa a sonda: o que interessa e se ESTA corrente mexeu
    local realSet = C_SpecializationInfo.SetSpecialization
    C_SpecializationInfo.SetSpecialization = function() return false end

    state.pendingSet = nil
    local texto, houveErro
    ns.Data.Apply({ name = "Tank", spec = 1, talent = 12, gear = 3, transmog = 71 },
        function(t, isError) texto, houveErro = t, isError end)

    --    A RECUSA NAO VIRA ERRO: vira espera. Tentar de novo SEMPRE funcionou no diario --
    --    02:42:28 recusado, 02:42:37 aceito; 02:42:48 recusado, 02:42:52 aceito -- e as tres
    --    coisas que tentei usar para PREVER a recusa foram desmentidas pelo mesmo arquivo.
    check("a recusa nao vira erro na cara do jogador", houveErro, false)
    check("a corrente fica esperando para insistir", ns.Data.IsApplying(), true)
    check("e avisa que esta esperando",
        texto and texto:lower():find("esperando", 1, true) ~= nil, true)
    check("sem ter mexido nos itens ainda", state.pendingSet, nil)

    -- 3. E SE O JOGO ACEITAR NA PROXIMA, a corrente segue sozinha -- o jogador clicou UMA vez.
    -- MAS INSISTIR TEM TETO. Insistir para sempre e pior que desistir: a corrente ficaria presa e
    -- todo clique seguinte seria recusado -- exatamente o travamento que ja aconteceu duas vezes
    -- nesta sequencia, so que agora por escolha minha.
    local antes = ns.Data.IsApplying()
    check("comeca insistindo", antes, true)
    for _ = 1, 12 do RunTimers() end
    check("mas desiste em algum momento", ns.Data.IsApplying(), false)
    -- A frase final pode vir do teto de tentativas OU do prazo do passo -- os dois sao finais
    -- honestos, e os dois falam da especializacao. O que nao pode e a corrente ficar presa.
    check("dizendo que foi a especializacao",
        texto and texto:lower():find("especializa", 1, true) ~= nil, true)

    -- E DEPOIS DE DESISTIR, o clique seguinte funciona -- a corrente nao fica presa.
    state.specIndex = 2
    C_SpecializationInfo.SetSpecialization = realSet
    state.pendingSet = nil
    local voltou = ns.Data.Apply({ name = "Tank", spec = 1, gear = 3 }, function() end)
    check("e o clique seguinte nao e recusado", voltou, true)
    state.specIndex = 1
    fire("ACTIVE_PLAYER_SPECIALIZATION_CHANGED")
    fire("EQUIPMENT_SWAP_FINISHED", true, 3)

    C_SpecializationInfo.SetSpecialization = function() return false end
    state.specIndex = 2
    ns.Data.Apply({ name = "Tank", spec = 1, talent = 12, gear = 3, transmog = 71 },
        function(t, isError) texto, houveErro = t, isError end)

    C_SpecializationInfo.SetSpecialization = realSet
    RunTimers()                       -- a tentativa marcada acontece, e agora o jogo aceita
    state.specIndex = 1
    fire("ACTIVE_PLAYER_SPECIALIZATION_CHANGED")
    gravacaoTermina(999)
    fire("EQUIPMENT_SWAP_FINISHED", true, 3)
    check("e quando o jogo aceita, ela continua sozinha", ns.Data.IsApplying(), false)
    C_SpecializationInfo.SetSpecialization = function() return false end

    C_SpecializationInfo.SetSpecialization = realSet
    state.activeLoadout[251] = 10
end

print("== o diario responde POR QUE nao trocou ==")
-- Pergunta literal do usuario, depois de a troca falhar pela quarta vez: "tu ta salvando logs
-- para poder entender os problemas?". A resposta era NAO, e por isso as rodadas anteriores foram
-- eu adivinhando qual passo tinha falhado e ele me contando por escrito.
--
-- O QUE O DIARIO PRECISA RESPONDER, lendo o arquivo e nada mais: por que nao trocou. Isso exige,
-- em cada passo, TRES coisas -- o que o addon PEDIU, o que o jogo RESPONDEU, e como o passo
-- FECHOU. Sem as tres nao da para distinguir "o jogo recusou" de "o addon nem pediu" de "o jogo
-- aceitou e nao fez", que sao exatamente as tres hipoteses que ja custaram uma rodada cada.
do
    ns.Log.Clear()
    state.specIndex, state.equippedSet, state.activeLoadout[251] = 2, 1, 10

    -- Uma troca que FALHA no passo de talentos, com o jogo dando o motivo.
    local realLoad = C_ClassTalents.LoadConfig
    C_ClassTalents.LoadConfig = function()
        return 0, "Nao e possivel trocar talentos aqui."
    end

    ns.Data.Apply({ name = "Tank", spec = 2, talent = 11, gear = 3 }, function() end)
    fire("EQUIPMENT_SWAP_FINISHED", true, 3)

    C_ClassTalents.LoadConfig = realLoad

    local texto = table.concat(ns.Log.Tail(50), " ~ ")

    -- 1. O QUE O ADDON PEDIU, e o estado de antes. Sem esta linha nao da para ver que a troca nem
    --    precisava acontecer, nem que ela pedia algo que nao existe mais.
    check("o diario registra o conjunto pedido", texto:find("preset=Tank", 1, true) ~= nil, true)
    check("e o que cada campo queria contra o que havia",
        texto:find("querTalento=11", 1, true) ~= nil
        and texto:find("temTalento=10", 1, true) ~= nil, true)

    -- 2. O QUE O JOGO RESPONDEU. E o que separa "o jogo recusou" de "o addon nem pediu".
    check("registra a chamada ao jogo", texto:find("LoadConfig(11)", 1, true) ~= nil, true)
    check("e o retorno dela", texto:find("Nao e possivel trocar talentos aqui.", 1, true) ~= nil, true)

    -- 3. COMO O PASSO FECHOU, passo a passo.
    check("registra o resultado do passo", texto:find("passo=talent", 1, true) ~= nil, true)
    check("dizendo que falhou", texto:find("resultado=fail", 1, true) ~= nil, true)

    -- E O VEREDITO FINAL, com as falhas juntas.
    check("registra o fim da corrente", texto:find("event", 1, true) ~= nil, true)
    check("com o que falhou", texto:lower():find("falhas=", 1, true) ~= nil, true)
end

print("== o passo de itens olha o retorno, e o diario diz por que ==")
-- ⚑ ESTE BLOCO NASCEU DE UM DIARIO REAL, o de 09/09/2026. As 17:22:02 o jogo devolveu
-- `EQUIPMENT_SWAP_FINISHED(false, 1)` para o conjunto "Frost PvE ST"; as 00:00:26 do MESMO dia a
-- mesma corrente, com o mesmo conjunto e a mesma ordem de eventos, tinha devolvido `true`.
--
-- O diario registrava a recusa e NADA MAIS -- nem o retorno da chamada, nem o estado do conjunto.
-- As duas linhas eram indistinguiveis, e sem isso a proxima rodada volta a adivinhar. Dos tres
-- passos da corrente, itens era o unico que jogava fora o retorno da propria chamada, contra o
-- que o cabecalho do `Data.lua` manda por escrito: *"cada passo espera o evento de confirmacao E
-- olha o retorno"*.
do
    ns.Log.Clear()
    state.specIndex, state.equippedSet, state.activeLoadout[251] = 2, 1, 10
    state.lostItems = 0

    -- 1. O CAMINHO NORMAL registra a chamada E o retorno dela.
    ns.Data.Apply({ name = "Tank", spec = 2, talent = nil, gear = 3 }, function() end)
    fire("EQUIPMENT_SWAP_FINISHED", true, 3)

    local texto = table.concat(ns.Log.Tail(50), " ~ ")
    check("o diario registra a chamada de equipar",
        texto:find("UseEquipmentSet(3)", 1, true) ~= nil, true)
    check("  com o retorno do jogo", texto:find("retorno=true, true", 1, true) ~= nil, true)
    check("  e a contabilidade do conjunto antes da troca",
        texto:find("perdidas=0", 1, true) ~= nil, true)

    -- 2. RECUSA IMEDIATA: o jogo diz "nao" na chamada, e ai NAO VEM EVENTO NENHUM depois.
    --
    -- Sem olhar o retorno, o passo ficava "esperando" os 20 segundos do prazo por uma confirmacao
    -- que ninguem ia mandar, para no fim dizer "o jogo nao confirmou a tempo". E o mesmo defeito
    -- que a spec e os talentos ja tiveram, corrigido nos dois; aqui continuava de pe.
    ns.Log.Clear()
    state.equippedSet = 1
    state.refuseUseSet = true
    local erro
    ns.Data.Apply({ name = "Tank", spec = 2, talent = nil, gear = 3 }, function(text, isError)
        if isError then erro = text end
    end)
    check("recusa imediata nao fica esperando evento", ns.Data.IsApplying(), false)
    check("  e vira falha reportada", erro ~= nil, true)
    check("  com o retorno no diario",
        table.concat(ns.Log.Tail(50), " ~ "):find("retorno=true, false", 1, true) ~= nil, true)
    state.refuseUseSet = false

    -- 3. QUANDO O JOGO SABE O MOTIVO, A MENSAGEM DIZ O MOTIVO. `numLost` e "pecas que o jogador
    --    nao tem a mao agora" -- a unica causa que a API prova. Sem ela, a frase generica fica.
    --
    -- (!) O CONJUNTO QUEBRA NO MEIO DA TROCA, e nao antes: desde 0.31.0 o `Data.Apply` RECUSA
    -- comecar com peca perdida, entao a corrente so chega aqui quando a peca some depois que
    -- ela ja estava a caminho (vendida noutra janela, mochila cheia). O caminho continua vivo e
    -- continua precisando dizer o motivo -- o que mudou foi quando ele acontece.
    ns.Log.Clear()
    state.equippedSet = 1
    state.lostItems = 0
    erro = nil
    ns.Data.Apply({ name = "Tank", spec = 2, talent = nil, gear = 3 }, function(text, isError)
        if isError then erro = text end
    end)
    state.lostItems = 3
    fire("EQUIPMENT_SWAP_FINISHED", false, 3)
    check("a falha diz quantas pecas faltam",
        erro ~= nil and erro:find("3", 1, true) ~= nil, true)
    -- ⚑ PROCURA A LINHA DA RECUSA, e nao "perdidas=3" em qualquer lugar. A contagem tambem sai na
    -- linha de ANTES da chamada, entao a busca solta passava mesmo com o retrato da recusa
    -- apagado -- foi a sabotagem que denunciou. O que importa e o estado no instante em que o
    -- jogo disse nao: e o unico momento em que a resposta existe.
    local diario = table.concat(ns.Log.Tail(50), " ~ ")
    local ondeRecusou = diario:find("recusou", 1, true)
    check("  e o diario guarda o estado do conjunto na hora da recusa",
        ondeRecusou ~= nil and diario:find("perdidas=3", ondeRecusou, true) ~= nil, true)

    -- 4. E SEM PECA FALTANDO A FRASE GENERICA VOLTA. Inventar um motivo quando o jogo nao deu
    --    nenhum e pior que nao ter motivo: manda o jogador procurar o que nao existe.
    ns.Log.Clear()
    state.equippedSet, state.lostItems = 1, 0
    erro = nil
    ns.Data.Apply({ name = "Tank", spec = 2, talent = nil, gear = 3 }, function(text, isError)
        if isError then erro = text end
    end)
    fire("EQUIPMENT_SWAP_FINISHED", false, 3)
    check("sem peca faltando, nao inventa motivo",
        erro ~= nil and erro:find("%d") == nil, true)

    state.lostItems = 0
end

print("== o diario ve o evento que chega de fora ==")
-- Hipotese que eu nao tinha como testar antes: `TRAIT_CONFIG_UPDATED`,
-- `ACTIVE_PLAYER_SPECIALIZATION_CHANGED` e `EQUIPMENT_SWAP_FINISHED` sao GLOBAIS -- disparam
-- quando o JOGADOR mexe a mao ou quando outro addon mexe. Se um deles fechar um passo que nao era
-- nosso, o diario tem que mostrar.
do
    ns.Log.Clear()
    fire("TRAIT_CONFIG_UPDATED")            -- sem corrente em curso

    local texto = table.concat(ns.Log.Tail(10), " ~ ")
    check("registra evento mesmo sem troca em curso",
        texto:find("evento=TRAIT_CONFIG_UPDATED", 1, true) ~= nil, true)
    check("dizendo que nao era para nos", texto:find("paraNos=false", 1, true) ~= nil, true)
end

print("== o diario nao guarda valor opaco nem cresce sem limite ==")
do
    ns.Log.Clear()

    -- SECRET NUNCA ENTRA. Guardar valor opaco em SavedVariables e caminho certo para erro, e a
    -- regra vale para todo campo -- por isso `Describe` pergunta `issecretvalue` ANTES do `type`:
    -- para um valor opaco `type()` responde o tipo real, e testar so o tipo deixaria o `tostring`
    -- receber um secret.
    local realIsSecret = issecretvalue
    issecretvalue = function(v) return v == "opaco" end
    ns.Log.Call("spec", "teste", "opaco")
    issecretvalue = realIsSecret

    local texto = table.concat(ns.Log.Tail(3), " ~ ")
    check("valor opaco vira SECRET, nao o valor", texto:find("SECRET", 1, true) ~= nil, true)
    check("e o valor cru nao entra", texto:find("opaco", 1, true), nil)

    -- ANEL: o arquivo nao pode crescer sem limite. 500 linhas em 400 de teto tem que sobrar 400.
    for i = 1, 500 do ns.Log.Add("enche", { i = i }) end
    check("o diario para de crescer no teto", ns.Log.Count() <= 400, true)
    check("e mantem as ULTIMAS, nao as primeiras",
        table.concat(ns.Log.Tail(1), ""):find("i=500", 1, true) ~= nil, true)

    ns.Log.Clear()
    check("e limpar limpa mesmo", ns.Log.Count(), 0)
end

print("== o diario captura os erros DESTE addon ==")
-- ⚑ PEDIDO DO USUARIO, 09/09/2026: *"tu esta armazenando logs de ambos addons? fazendo aqueles
-- logs de tudo que faz e etc para capturar qualquer erro inesperado?"*. A resposta era NAO: o
-- diario so sabia o que a gente mandou anotar, e erro de Lua ficava fora dele. No mesmo dia isso
-- custou 1628 ocorrencias do mesmo erro passando despercebidas no arquivo de um addon de terceiro.
do
    local ADDON_PATH = "Interface/AddOns/" .. "RocketSwap"

    ns.Log.ClearErrors()

    -- MUNDO 1: sem !BugGrabber. Encadeia no handler que estiver valendo.
    local chamouAnterior = false
    mundoErro.mudo = false
    mundoErro.handler = function() chamouAnterior = true end
    ns.Log.__resetCapture()
    check("sem BugGrabber, encadeia no handler", ns.Log.CaptureErrors(), "handler")

    mundoErro.pilha = ADDON_PATH .. "/Data.lua:10: in function 'X'\n"
        .. "Interface/AddOns/Outro/Coisa.lua:3: in function <Coisa>"
    geterrorhandler()(ADDON_PATH .. "/Data.lua:10: deu ruim")

    local distintos, total = ns.Log.ErrorCount()
    check("o erro nosso entra no diario", distintos, 1)

    -- ⚑ NAO ROUBAR O ERRO DE QUEM JA TRATAVA. Substituir sem chamar o anterior apagaria o erro
    -- do BugSack/ElvUI do jogador -- estragar a ferramenta dos outros para ter a nossa.
    check("  e o handler anterior continua sendo chamado", chamouAnterior, true)

    local guardado = RocketSwapLogDB.erros[1]
    check("  com a pilha filtrada nos nossos quadros",
        guardado.pilha ~= nil and guardado.pilha:find("Outro/Coisa", 1, true) == nil, true)

    -- REPETICAO VIRA CONTAGEM. Sem isto, o caso real (1628 vezes o mesmo erro) varreria o anel
    -- inteiro e apagaria justamente o contexto que explica o defeito.
    geterrorhandler()(ADDON_PATH .. "/Data.lua:10: deu ruim")
    geterrorhandler()(ADDON_PATH .. "/Data.lua:10: deu ruim")
    distintos, total = ns.Log.ErrorCount()
    check("repeticao vira contagem, nao linha nova", distintos, 1)
    check("  e a contagem sobe", total, 3)

    -- ERRO DE OUTRO ADDON NAO E NOSSO. Guardar o alheio enche o arquivo do que nao vamos
    -- consertar, e -- pior -- faz parecer que o defeito e nosso.
    mundoErro.pilha = "Interface/AddOns/Outro/Coisa.lua:3: in function <Coisa>"
    geterrorhandler()("Interface/AddOns/Outro/Coisa.lua:3: erro alheio")
    distintos = ns.Log.ErrorCount()
    check("erro de outro addon nao entra", distintos, 1)

    -- MUNDO 2: com !BugGrabber. Ele NEUTRALIZA o seterrorhandler
    -- (`!BugGrabber/BugGrabber.lua:573-574`), entao o caminho tem que ser o callback dele.
    ns.Log.ClearErrors()
    local assinantes = {}
    EventRegistry = {
        RegisterCallback = function(_, evento, fn) assinantes[evento] = fn end,
    }
    BugGrabber = {
        erros = {},
        GetErrorByID = function(self, id) return self.erros[id] end,
    }
    mundoErro.mudo = true
    ns.Log.__resetCapture()
    check("com BugGrabber, assina o callback dele", ns.Log.CaptureErrors(), "buggrabber")

    BugGrabber.erros["x1"] = {
        message = ADDON_PATH .. "/Window.lua:882: bad argument",
        stack = ADDON_PATH .. "/Window.lua:882: in function 'Y'",
    }
    assinantes["BugGrabber.BugGrabbed"](nil, "x1")
    check("  e copia o erro que e nosso", ns.Log.ErrorCount(), 1)

    BugGrabber.erros["x2"] = {
        message = "Interface/AddOns/Outro/Coisa.lua:3: alheio",
        stack = "Interface/AddOns/Outro/Coisa.lua:3: in function <Coisa>",
    }
    assinantes["BugGrabber.BugGrabbed"](nil, "x2")
    check("  e so o que e nosso", ns.Log.ErrorCount(), 1)

    -- ⚑ MUNDO 3: `seterrorhandler` mudo e SEM BugGrabber. E o mundo que a conferencia existe para
    -- pegar. Declarar "handler" aqui seria a pior falha possivel num instrumento: ele afirmaria
    -- estar ligado, o arquivo sairia limpo, e a conclusao "nao houve erro" seria falsa.
    BugGrabber, EventRegistry = nil, nil
    mundoErro.mudo = true
    ns.Log.__resetCapture()
    check("seterrorhandler mudo e sem BugGrabber: admite que nao captura",
        ns.Log.CaptureErrors(), "nenhuma")

    mundoErro.mudo = false
    mundoErro.handler = nil
    ns.Log.ClearErrors()
end

print("== comandos ==")
for _, cmd in ipairs({ "", "list", "help", "icon", "i18n", "load Arena", "load nao-existe",
                       "log", "log clear", "transmog", "Arena",
                       -- `/rs gear` nas duas formas: a lista e o despejo de um slot (13/09). O
                       -- despejo mexe com `line.type`, `rightText` e valor secret -- e um `nil`
                       -- em qualquer um deles estoura no chat, na hora em que o usuario esta
                       -- justamente tentando relatar um defeito.
                       "gear", "gear 5", "gear 3" }) do
    local ok, err = pcall(SlashCmdList.ROCKETSWAP, cmd)
    print(ok and ("  ok    /rs " .. cmd) or ("  ERRO  /rs " .. cmd .. ": " .. tostring(err)))
    if not ok then os.exit(1) end
end

print("== icone verificado, nao chutado ==")
-- No simulador so o ultimo candidato existe: o addon tem que descer a lista ate ele, em vez
-- de usar o primeiro e desenhar nada.
local escolhido, verificado = ns.FirstIcon(ns.ICON_CANDIDATES)
check("caiu no candidato que existe", escolhido:find("MissileLarge_Red", 1, true) ~= nil, true)
check("e sabe que verificou", verificado, true)
check("lista de candidatos exposta", #ns.ICON_CANDIDATES >= 2, true)

print("== deteccao de peca de PvP ==")
-- A deteccao inteira depende de uma LINHA DE TOOLTIP casar com um padrao montado a partir de
-- uma string global. Tres coisas ja quebraram esse padrao em addons publicados, e as tres
-- estao reproduzidas aqui.

-- (1) A LINHA VEM EMBRULHADA EM CODIGO DE COR. O fmtToPattern do EnhanceQoL devolve
-- "^" .. pat .. "$", e por isso NAO casa nesse caso. O nosso padrao nao tem ancora.
VestirTudo(true)
ns.Gear.ClearCache()
check("peca de PvP e reconhecida mesmo com codigo de cor", ns.Gear.IsPvPItem(1), true)

VestirTudo(false)
ns.Gear.ClearCache()
check("peca sem a linha e reconhecida como PvE", ns.Gear.IsPvPItem(1), false)

-- (2) SLOT VAZIO NAO E "PvE". E desconhecido — e desconhecido nunca vira aviso.
equipped[1] = nil
ns.Gear.ClearCache()
check("slot vazio devolve desconhecido", ns.Gear.IsPvPItem(1), nil)

print("== tooltip que ainda nao carregou (defeito de 13/09, com print) ==")
-- ⚑ O DEFEITO, TRANSCRITO DO DESPEJO QUE O USUARIO MANDOU:
--
--     slot 5 (Torso): link: [Peitoral do Necrocavaleiro Pernicioso]
--     padrao montado: sim | padrao se prova: sim
--     leitura atual: false
--     1 linha(s):
--       1  tipo=41  Recuperando informacoes do item
--
-- O cliente devolve UMA linha de recado enquanto busca os dados. A guarda antiga (`#lines == 0`)
-- nao pega isso, nenhuma linha casa com o padrao, e a peca virava `false` -- no cache. Peca de PvP
-- acusada de PvE, de forma estavel, e sobrevivendo ate a troca de personagem.
do
    VestirTudo(true)              -- tudo de PvP
    ns.Gear.ClearCache()
    ns.Gear.__ResetPending()
    pedidos = {}
    equipped[5].loaded = false    -- ... mas os dados do peitoral ainda nao chegaram

    check("tooltip que ainda nao carregou nao decide nada", ns.Gear.IsPvPItem(5), nil)
    check("o addon pede o carregamento do item", pedidos[1005], 1)

    -- E NAO PEDE DE NOVO A CADA VARREDURA: sao varias por minuto (zona, ready check, troca).
    ns.Gear.IsPvPItem(5)
    ns.Gear.IsPvPItem(5)
    check("  e nao pede duas vezes o mesmo item", pedidos[1005], 1)

    -- ⚑ E O RESULTADO INCOMPLETO NAO PODE TER IDO PARA O CACHE: era isso que tornava o erro
    -- permanente. Depois de carregar, a leitura tem que valer sem ninguem limpar nada na mao.
    -- ⚑ E QUEM ESPERA TEM DE SER AVISADO, que e coisa diferente de "a leitura agora vale".
    --
    -- A primeira versao deste bloco so relia `IsPvPItem` depois de carregar -- e passava mesmo com
    -- o aviso arrancado, porque o retorno do carregamento limpa o cache ANTES de avisar. O check
    -- media o cache, nao a notificacao. Quem denunciou foi a sabotagem, de novo.
    local avisou = false
    local inscritoAntes = ns.Gear.onItemLoaded
    ns.Gear.onItemLoaded = function(...)
        avisou = true
        if inscritoAntes then return inscritoAntes(...) end
    end

    CarregarItem(5)
    check("carregado o item, quem espera e avisado", avisou, true)
    check("carregado o item, a leitura passa a valer", ns.Gear.IsPvPItem(5), true)

    ns.Gear.onItemLoaded = inscritoAntes

    -- E a peca vizinha, cujos dados sempre estiveram la, nao foi afetada pelo pedido.
    check("a peca que ja tinha dados segue lida", ns.Gear.IsPvPItem(6), true)

    VestirTudo(false)
    ns.Gear.ClearCache()
    ns.Gear.__ResetPending()
end

-- (3) Camisa e tabardo nao entram: nao tem atributo nem versao de PvP.
check("a lista de slots ignora camisa e tabardo",
    (function()
        for _, slot in ipairs(ns.Gear.SLOTS) do
            if slot == 4 or slot == 19 then return false end
        end
        return #ns.Gear.SLOTS == 16
    end)(), true)

print("== a regra: o que e erro em cada contexto ==")
VestirTudo(false)          -- tudo de PvE
ns.Gear.ClearCache()
local erradas = ns.Gear.Wrong(true)     -- estamos em PvP?
check("de PvE em PvP: os 16 slots estao errados", #erradas, 16)
erradas = ns.Gear.Wrong(false)          -- estamos em PvE?
check("de PvE em PvE: nada errado", #erradas, 0)

VestirTudo(true)           -- tudo de PvP
ns.Gear.ClearCache()
check("de PvP em PvE: os 16 errados", #ns.Gear.Wrong(false), 16)
check("de PvP em PvP: nada errado", #ns.Gear.Wrong(true), 0)

-- Caso realista: trocou tudo menos os berloques.
VestirTudo(true)
equipped[13].pvp, equipped[14].pvp = false, false
ns.Gear.ClearCache()
local mistas = ns.Gear.Wrong(true)
check("dois berloques de PvE numa arena", #mistas, 2)
check("e o aviso sabe QUAL slot", ns.Gear.SlotName(mistas[1].slot), "Berloque 1")

print("== a comporta so cala quando a DETECCAO nao se prova ==")
-- ⚑ AQUI ESTAVA O DEFEITO QUE O USUARIO RELATOU em 08/09/2026: *"o de pve no pvp, ainda nao vi
-- funcionar, quando dou fila em BG, arena, ele nao avisa nada sobre meus itens"*.
--
-- A regra era `#wrong < read`: TODOS errados = presume falha de deteccao. Medindo de 0 a 16
-- pecas de PvP, ela calava exatamente UMA das 17 configuracoes de cada lado -- e no lado do PvP
-- essa uma e `n = 0`, equipamento de PvE inteiro, que e justamente quem entra numa arena vindo
-- do PvE. Nao era filtro de ruido; era um recorte em cima do caso comum.
--
-- E a ambiguidade so existe de UM lado, por construcao: um `true` so nasce de um casamento do
-- padrao, e nenhuma falha de leitura sabe fabricar `true` -- so `false`. Entao "todas erradas"
-- em PvE sao 16 casamentos genuinos (nunca ambiguo), e em PvP sao zero casamentos (que e
-- exatamente o que a falha produz).
--
-- Quem desfaz isso e o padrao testando A SI MESMO, contra uma linha montada da propria global.
VestirTudo(false)
ns.Gear.ClearCache()
local todas, lidos = ns.Gear.Wrong(true)
check("de PvE inteiro numa arena, a leitura vale", ns.Gear.LooksReliable(todas, lidos), true)
check("  porque o padrao acha a linha que ele procura", ns.Gear.PatternWorks(), true)

VestirTudo(true)
equipped[13].pvp = false
ns.Gear.ClearCache()
local uma, lidos2 = ns.Gear.Wrong(true)
check("uma errada entre dezesseis = confiavel", ns.Gear.LooksReliable(uma, lidos2), true)

-- E COM O PADRAO QUEBRADO O SILENCIO CONTINUA. Esta e a metade da comporta que tinha razao: num
-- cliente cujo padrao nao casa, TODA peca le `false`, e gritar seria acusar dezesseis vezes.
do
    local realGlobal = PVP_ITEM_LEVEL_TOOLTIP
    local realWorks = ns.Gear.PatternWorks

    -- Um padrao que nunca casa com a linha que ele diz procurar.
    ns.Gear.PatternWorks = function() return false end

    VestirTudo(false)
    ns.Gear.ClearCache()
    local cegas, lidasCegas = ns.Gear.Wrong(true)
    check("padrao que nao se prova volta a calar", ns.Gear.LooksReliable(cegas, lidasCegas), false)
    check("  mesmo com os dezesseis slots lidos", lidasCegas, 16)

    ns.Gear.PatternWorks = realWorks
    PVP_ITEM_LEVEL_TOOLTIP = realGlobal
end

print("== fila e fila desde o primeiro segundo ==")
-- ⚑ RELATO LITERAL DO USUARIO: *"quando dou fila em BG, arena, ele nao avisa nada sobre meus
-- itens"*. E era literal mesmo.
--
-- `Alert.Context` so abria para os status "confirm" e "active" -- e "confirm" NAO e a espera na
-- fila: e o ESTOURO dela, o convite com contagem para aceitar. (O DBM prova em disco: ele so
-- monta a barra de "tempo restante para aceitar uma fila" quando o status vira "confirm", e mede
-- a com `GetBattlefieldPortExpiration`.) Enquanto o jogador esperava, o contexto era nil e o
-- aviso morria antes de ler uma unica peca.
--
-- A lista virou a do que NAO vale, de proposito: o nome literal do status de espera nao deu para
-- provar de disco -- nenhum addon instalado o compara -- e um teste positivo dependeria de
-- acertar esse nome.
do
    local realStatus = GetBattlefieldStatus
    local realInstance = state.instance
    state.instance = nil

    for _, situacao in ipairs({ "queued", "confirm", "active", "waiting" }) do
        GetBattlefieldStatus = function() return situacao end
        check("na fila (" .. situacao .. ") o contexto e de PvP", ns.Alert.Context(), "pvp")
    end

    for _, vazio in ipairs({ "none", "error" }) do
        GetBattlefieldStatus = function() return vazio end
        check("sem fila (" .. vazio .. ") o addon nao opina", ns.Alert.Context(), nil)
    end

    GetBattlefieldStatus = realStatus
    state.instance = realInstance
end

print("== modo guerra tem contexto e redacao proprios ==")
-- PEDIDO DO USUARIO: *"inclusive quando seto para pvp, habilitando o war mode on, sem avisos"*.
--
-- O mundo aberto era excluido de proposito ("o addon nao opina") e War Mode nao era consultado em
-- lugar nenhum do addon -- a unica mencao a `C_PvP` era um comentario dizendo que nenhuma API
-- responde se um item e de PvP. Nao era defeito: era buraco.
--
-- E ele NAO devolve "pvp". Com War Mode ligado a maior parte do tempo e PvE -- missao, world
-- quest, farm -- e dizer "numa partida de PvP" ali seria falso. Mesmo texto para duas situacoes
-- diferentes e o que transforma aviso em ruido.
do
    local realInstance = state.instance
    state.instance = nil

    local ligado = false
    C_PvP = { IsWarModeDesired = function() return ligado end }

    check("com modo guerra desligado, o addon nao opina", ns.Alert.Context(), nil)

    ligado = true
    check("com modo guerra ligado, o contexto existe", ns.Alert.Context(), "warmode")
    check("  e nao se confunde com uma partida", ns.Alert.Context() ~= "pvp", true)

    -- ⚑ E O AVISO NASCE CALADO AQUI (pedido de 12/09: *"tira o alerta dos itens de pvp em mundo
    -- aberto no war mode, ou transforma em opcao por padrao desmarcada"*). O contexto continua
    -- existindo -- e o que `/rs gear` mostra --, mas o aviso e opt-in.
    VestirTudo(false)
    ns.Gear.ClearCache()
    ns.Alert.Hide()
    check("de fabrica a opcao nasce desmarcada", ns.defaults.warnWarMode, false)

    ns.db.warnWarMode = nil                 -- como nasce em quem nunca viu a opcao
    ns.Alert.Check("teste")
    check("sem marcar a opcao, modo guerra nao avisa", ns.Alert.__Shown(), false)

    -- E O DIAGNOSTICO DIZ ISSO. Sem esta porta no retrato, `/rs gear` mostraria todas as comportas
    -- abertas e o aviso nao sairia -- o silencio que o diagnostico existe para nao ter.
    check("  e o diagnostico mostra a porta fechada",
        ns.Alert.Diagnose().avisoModoGuerra, false)

    -- MARCADA, o aviso volta -- e com a redacao do modo guerra.
    ns.db.warnWarMode = true
    ns.Alert.Hide()
    ns.Alert.Check("teste")
    check("marcando a opcao, o aviso aparece", ns.Alert.__Shown(), true)
    check("  com a redacao do modo guerra",
        ns.Alert.__Headline(), ns.L["PvE gear with War Mode on."])

    -- ⚑ E A COMPORTA E SO DO MODO GUERRA: uma partida de PvP nao pode emudecer junto. A opcao
    -- desmarcada com contexto "pvp" tem que continuar avisando.
    ns.db.warnWarMode = nil
    state.instance = "arena"
    ns.Gear.ClearCache()
    ns.Alert.Hide()
    ns.Alert.Check("teste")
    check("a partida de PvP continua avisando", ns.Alert.__Shown(), true)
    check("  com a redacao da partida", ns.Alert.__Headline(),
        ns.L["PvE gear in a PvP match."])
    state.instance = nil
    ns.Gear.ClearCache()

    -- O COMANDO LIGA E DESLIGA, como o das outras duas caixas.
    SlashCmdList.ROCKETSWAP("warn warmode")
    check("/rs warn warmode liga", ns.db.warnWarMode, true)
    SlashCmdList.ROCKETSWAP("warn warmode")
    check("  e desliga", ns.db.warnWarMode, false)
    ns.db.warnWarMode = nil

    -- ⚑ AS DUAS REGRAS DE TELA, que nao aparecem no comportamento do aviso.
    if not ns.UI.IsShown() then ns.UI.Toggle() end
    ns.UI.Refresh()
    local caixas = ns.UI.DebugToggles()

    -- NASCE DESMARCADA: copiar o `~= false` das vizinhas a deixaria marcada em quem nunca a viu,
    -- que e o oposto do pedido.
    check("a caixa do modo guerra nasce desmarcada", caixas.warMode:GetChecked(), false)

    -- E APAGADA SEM A MAE: caixa clicavel que nao faz nada e pior que caixa nenhuma.
    -- A mae agora e o aviso de PvP: Modo Guerra e mundo aberto com PvP ligado, entao os dois
    -- moram na mesma coluna e a dependencia e entre eles.
    ns.db.warnPvP = false
    ns.UI.Refresh()
    check("sem o aviso de equipamento de PvP, a sub-opcao fica apagada",
        caixas.warMode:IsEnabled(), false)

    ns.db.warnPvP = true
    ns.UI.Refresh()
    check("  e volta quando a mae e religada", caixas.warMode:IsEnabled(), true)

    -- ⚑ A GEOMETRIA, que e aritmetica e se confere aqui (skill `wow-ui-design`).
    local xMae = caixas.warnPvE:PointOffset("TOPLEFT")
    local xFilha, yFilha = caixas.warMode:PointOffset("TOPLEFT")
    local _, yMae = caixas.warnPvE:PointOffset("TOPLEFT")
    local _, yReady = caixas.ready:PointOffset("TOPLEFT")
    local _, yQueue = caixas.queue:PointOffset("TOPLEFT")

    -- (!) O RECUO DE FILHA SAIU, e a checagem dele com ele (22/09). Enquanto as duas caixas
    -- moravam na mesma pilha, o recuo de 15 px dizia "esta depende da de cima" sem palavra
    -- nenhuma. Em COLUNAS SEPARADAS ele nao diz mais nada -- quem diz e o estado apagado, que os
    -- dois checks acima ja trancam, e que e um sinal mais forte do que o recuo era.
    --
    -- O que entra no lugar: as colunas sao mesmo DUAS, e cada caixa esta na sua.
    -- DUAS COLUNAS DE VERDADE (0.35.0): PvE de um lado, PvP do outro, cada uma com o SEU aviso
    -- de equipamento. Antes era uma chave so para os dois conteudos, e por isso os titulos
    -- tinham que ser "Em qualquer conteudo" / "So em PvP".
    local xPvP = caixas.warnPvP:PointOffset("TOPLEFT")
    check("o aviso de PvP fica na segunda coluna", xPvP > xMae + 100, true)
    check("e o de PvE na primeira, junto do Ready Check",
        select(1, caixas.ready:PointOffset("TOPLEFT")), xMae)

    -- A PRIMEIRA LINHA DAS DUAS COLUNAS SE ALINHA: sem isso viram duas listas soltas lado a lado.
    local _, yPvP = caixas.warnPvP:PointOffset("TOPLEFT")
    check("a primeira linha das duas colunas se alinha", yPvP, yMae)

    -- E A SUB-OPCAO VOLTOU A SER FILHA, com a mae na MESMA coluna -- entao o recuo de 15 px
    -- volta a fazer sentido e volta a ser conferido.
    check("a sub-opcao e recuada como opcao filha", xFilha - xPvP, 15)
    check("e fica logo abaixo da mae dela", yMae - yFilha, yMae - yReady)

    -- LEI DA PROXIMIDADE dentro da coluna de PvP: o convite de fila vem depois da sub-opcao.
    check("o convite de fila fica abaixo da sub-opcao", yQueue < yFilha, true)

    -- E A FAIXA TEM DE CABER TODAS: altura fixa que nao acompanha o conteudo transborda em
    -- silencio -- foi o defeito que a terceira caixa criou e que este check tranca; a quarta
    -- (convite de fila, 18/09) passou por ele.
    -- ⚑ A ALTURA SAI DA PROPRIA FAIXA (`caixas` E o strip), e nao de `caixas.warn:GetParent()`:
    -- no simulador `GetParent` cai no `__index` generico e devolve um widget NOVO, com a altura
    -- padrao de 400 -- o check comparava 112 com 400 e passava com a faixa transbordando. A
    -- sabotagem e que denunciou, que e o unico jeito de descobrir check que mede a si mesmo.
    local CAIXA = 24
    check("a faixa de avisos cabe todas as caixas", -yQueue + CAIXA <= caixas:GetHeight(), true)
    if ns.UI.IsShown() then ns.UI.Toggle() end

    ligado = false
    C_PvP = nil
    state.instance = realInstance
end

print("== a diretiva gramatical vira coringa, e nao some ==")
-- O COMENTARIO E O CODIGO SE CONTRADIZIAM: o comentario dizia "vira coringa", `BuildPattern`
-- REMOVIA. Medido, o alcance e menor do que parece -- e o numero vale mais que a impressao:
--
--     diretiva no FIM   -> remover CASA (o casamento nao e ancorado, o prefixo basta)
--     diretiva no MEIO  -> remover NAO CASA, coringa casa
--
-- A forma coreana conhecida tem a diretiva no FIM, entao o defeito nao estava quebrando aquele
-- cliente. O que estava errado era a REGRA: diretiva nao e texto literal, e apaga-la so
-- funcionava por acidente de posicao. O teste usa a forma que separa as duas -- sintetica de
-- proposito, porque e a posicao, e nao o idioma, que decide.
do
    local realGlobal = PVP_ITEM_LEVEL_TOOLTIP

    PVP_ITEM_LEVEL_TOOLTIP = "PvP %d|1\236\156\188\235\161\156;\235\161\156; \235\160\136\235\178\168"
    ns.Gear.ClearCache()
    ns.Gear.__ResetPattern()
    check("diretiva no meio: o padrao ainda se prova", ns.Gear.PatternWorks(), true)

    -- E SEM A GLOBAL NAO HA DETECCAO NENHUMA. E o piso do autoteste: sem isto, um autoteste que
    -- respondesse "sim" para tudo passaria despercebido.
    PVP_ITEM_LEVEL_TOOLTIP = nil
    ns.Gear.ClearCache()
    ns.Gear.__ResetPattern()
    check("sem a global do jogo, a deteccao nao se prova", ns.Gear.PatternWorks(), false)
    check("  e o padrao nem existe", ns.Gear.PatternReady(), false)

    PVP_ITEM_LEVEL_TOOLTIP = realGlobal
    ns.Gear.ClearCache()
    ns.Gear.__ResetPattern()
end

print("== em combate o aviso nao NASCE, e o botao so aparece se der para trocar ==")
-- ⚑ ESTE TESTE NAO TESTAVA NADA ate 08/09/2026. Ele afirmava `ns.Alert.__shown ~= true`, e
-- `__shown` nunca era escrito em `Alert` -- so nos frames do simulador. `nil ~= true` e sempre
-- verdadeiro: o check passava com o aviso na tela ou fora dela.
--
-- Com a porta de verdade ele reprovou na primeira execucao, e por um motivo legitimo: um aviso
-- que ja estava aberto CONTINUA aberto quando o combate comeca. Isso e certo -- o dado nao
-- deixou de ser verdade porque a luta comecou -- entao o teste fecha o aviso antes de perguntar
-- se ele NASCE em combate, que e a afirmacao de verdade.
VestirTudo(false)
ns.Gear.ClearCache()
state.instance = "arena"
ns.Alert.Hide()
state.inCombat = true
ns.Alert.Check("teste")
check("em combate o aviso nao aparece", ns.Alert.__Shown(), false)
state.inCombat = false

-- E FORA DE COMBATE ELE APARECE, mesmo com a restricao de addon ativa -- que dentro de uma
-- partida de PvP fica ligada do comeco ao fim.
--
-- ⚑ A COMPORTA ERA `CanFix()`, e ela fecha com a restricao. A documentacao de API deste cliente
-- define `AddOnRestrictionType.PvPMatch` como "the player is in an active and incomplete PvP
-- match": uma janela fechada a partida inteira. Isso desligava o aviso durante TODA arena e TODO
-- campo de batalha -- e e parte da assimetria relatada, porque em PvE as restricoes equivalentes
-- (`Encounter`, `ChallengeMode`) deixam janelas livres entre encontros.
--
-- Saber nao depende de poder consertar: quem descobre no meio da partida ao menos sai e volta
-- certo. O que depende de poder consertar e o BOTAO.
do
    Enum.AddOnRestrictionType = Enum.AddOnRestrictionType
        or { PvPMatch = 1, Encounter = 2, ChallengeMode = 3 }
    Enum.AddOnRestrictionState = Enum.AddOnRestrictionState or { Inactive = 0, Active = 2 }

    local realRestricted = C_RestrictedActions
    C_RestrictedActions = {
        GetAddOnRestrictionState = function(kind)
            if kind == Enum.AddOnRestrictionType.PvPMatch then
                return Enum.AddOnRestrictionState.Active
            end
            return Enum.AddOnRestrictionState.Inactive
        end,
    }

    ns.Alert.Hide()
    ns.Alert.Check("teste")
    check("durante a restricao de PvP o aviso ainda aparece", ns.Alert.__Shown(), true)
    check("  mas o botao de consertar nao", ns.Alert.__FixShown(), false)

    C_RestrictedActions = realRestricted
    ns.Alert.Hide()
    ns.Alert.Check("teste")
    check("sem restricao o aviso continua aparecendo", ns.Alert.__Shown(), true)
end

state.instance = nil

print("== resumo do ready check ==")
-- Pedido do usuario: no ready check, dizer qual conjunto e qual spec estao em uso.
state.specIndex, state.activeLoadout[251], state.equippedSet = 2, 11, 1
local resumo = ns.Alert.Summary()
check("traz a spec", resumo:find("Gelido", 1, true) ~= nil, true)
check("traz o loadout de talentos", resumo:find("SBA ST", 1, true) ~= nil, true)
check("traz o conjunto de itens", resumo:find("Frost", 1, true) ~= nil, true)

-- E DIZ O QUE E O QUE. Pedido do usuario: "ta os nomes salvos soltos e nao sei o que e o que".
-- Tres nomes proprios em sequencia -- "Gelido · SBA ST · Frost" -- nao dizem qual e qual, e o
-- caso ruim e o comum: nada impede o conjunto de itens e o loadout de talentos de terem o
-- MESMO nome.
check("rotula a especializacao",
    resumo:find(ns.L["Specialization"] .. ": Gelido", 1, true) ~= nil, true)
check("rotula os talentos", resumo:find(ns.L["Talents"] .. ": ", 1, true) ~= nil, true)
check("rotula os itens", resumo:find(ns.L["Gear"] .. ": ", 1, true) ~= nil, true)

-- OS ROTULOS SAO OS DA PROPRIA JANELA DO ADDON. Nao e detalhe: quem abre `/rs` le essas tres
-- palavras ao lado dos tres combos, e o resumo usando outras obrigaria a aprender dois
-- vocabularios para a mesma coisa. Este check quebra se a janela e o resumo divergirem.
check("os rotulos sao os do editor",
    ns.L["Specialization"] ~= nil and ns.L["Talents"] ~= nil and ns.L["Gear"] ~= nil, true)

-- ITENS NAO VEM DO JOGO, e a razao esta registrada em `Locales/enUS.lua`: em pt-BR o cliente
-- chama LOADOUT DE TALENTOS de "equipamento" e CONJUNTO DE ITENS de "conjunto". O addon foge das
-- duas de proposito -- ele existe para quem ja confunde as duas coisas, e o pedido que trouxe
-- estes rotulos e essa confusao em pessoa.
check("itens nao usa palavra do jogo", ns.FROM_GAME["Gear"], nil)

-- UMA LINHA POR CAMPO NA CAIXA, tudo numa so no chat. A caixa tem altura livre e o chat nao.
local NL = string.char(10)
local emLinhas = ns.Alert.Summary(NL)
local quantas = select(2, emLinhas:gsub(NL, "")) + 1
check("a caixa quebra em tres linhas", quantas, 3)
check("e o chat continua em uma so", select(2, resumo:gsub(NL, "")), 0)

-- SEM CONJUNTO VESTIDO o resumo diz `Itens: (nenhum)` -- e nao mais "(sem conjunto de itens)".
--
-- A frase longa existia porque ELA era o unico contexto: sem rotulo, era a unica forma de saber
-- de que campo se tratava. Com o rotulo na frente ela repetia a propria etiqueta e arrastava duas
-- palavras que este addon evita: "loadout" (que o cliente traduz como "equipamento" em pt-BR) e
-- "conjunto" -- que aqui e o nome dos PRESETS, entao o campo e o conteiner dividiam o nome.
--
-- `L["(none)"]` ja existe e ja e o que os combos do editor mostram no mesmo caso.
state.equippedSet = 99
check("sem conjunto, diz (nenhum)",
    ns.Alert.Summary():find(ns.L["Gear"] .. ": " .. ns.L["(none)"], 1, true) ~= nil, true)
check("e NAO repete o rotulo na frase",
    ns.Alert.Summary():lower():find("conjunto de itens", 1, true), nil)

-- MAS `(nenhum)` ERA FALSO PARA QUEM SO TROCOU UMA PECA. Relato do usuario (15/09): trocar um
-- item de um conjunto salvo e dar ready check mostrava "Itens: (nenhum)" -- "uma mensagem errada,
-- porque ele ta com os itens so que um ou mais nao estao salvos".
--
-- `isEquipped` e tudo-ou-nada: uma peca fora derruba a flag das catorze. `numEquipped` nao --
-- e ela que separa "nao carreguei conjunto nenhum" de "troquei uma peca e nao salvei". Os dois
-- casos pedem acoes opostas (carregar x salvar), e a frase antiga os fundia.
state.wornPieces = { [1] = 13 }
check("com uma peca trocada, diz o nome do conjunto",
    ns.Alert.Summary():find(ns.L["Gear"] .. ": Frost (13", 1, true) ~= nil, true)
check("e nao diz mais (nenhum)",
    ns.Alert.Summary():find(ns.L["Gear"] .. ": " .. ns.L["(none)"], 1, true), nil)

-- MAIORIA SIMPLES OU NADA. Dois conjuntos de raide dividem anel, capa e joia sem ninguem ter
-- vestido nenhum dos dois; abaixo do corte a resposta honesta volta a ser `(nenhum)`.
state.wornPieces = { [1] = 7 }
check("metade das pecas nao basta",
    ns.Alert.Summary():find(ns.L["Gear"] .. ": " .. ns.L["(none)"], 1, true) ~= nil, true)

-- EMPATE NAO RESPONDE. Escolher "o primeiro" aqui seria sortear qual nome o jogador le.
state.wornPieces = { [1] = 13, [2] = 13 }
check("empate volta para (nenhum)",
    ns.Alert.Summary():find(ns.L["Gear"] .. ": " .. ns.L["(none)"], 1, true) ~= nil, true)

state.wornPieces = nil
state.equippedSet = 1

print("== resumo no convite da fila de PvP ==")
-- Pedido do usuario (18/09): *"quando chama para entrar na arena apos ter esperado na fila, tem
-- como dar o aviso de qual build ta setado?"*. E o mesmo resumo do ready check, no instante em
-- que ele vale mais: DENTRO da arena a restricao de addon fecha a troca do comeco ao fim da
-- partida, entao o convite e a ultima janela para arrumar a build.
--
-- `GetBattlefieldStatus(i) == "confirm"` e o convite na tela (mesmo caminho do DBM,
-- `DBM-Core.lua:3360-3364`); o 2o retorno e o mapa e o 3o, o tamanho do time.
do
    local real = GetBattlefieldStatus
    local status = "none"
    GetBattlefieldStatus = function() return status, "Nagrand Arena", 3 end

    wipe(shownPopups)
    wipe(hiddenPopups)
    ns.db.queuePop = true

    -- Fila andando: nao ha o que conferir ainda.
    ns.Alert.OnQueuePop()
    check("fila sem convite nao abre caixa", #shownPopups, 0)

    status = "confirm"
    ns.Alert.OnQueuePop()
    check("o convite abre a caixa", #shownPopups, 1)
    check("com o resumo dentro",
        shownPopups[1].text and shownPopups[1].text:find("Gelido", 1, true) ~= nil, true)
    check("e o titulo diz o mapa e o tamanho do time",
        shownPopups[1].text:find("Nagrand Arena (3v3)", 1, true) ~= nil, true)

    -- UMA VEZ POR CONVITE. `UPDATE_BATTLEFIELD_STATUS` dispara varias vezes com o mesmo convite
    -- (o relogio dele anda) -- e a caixa espera OK, entao sem trava cada disparo empilharia outra.
    ns.Alert.OnQueuePop()
    ns.Alert.OnQueuePop()
    check("disparo repetido nao empilha caixa", #shownPopups, 1)

    -- Saiu do convite: a caixa perde o assunto. Sem isto ela ficaria pendurada DENTRO da partida.
    status = "active"
    ns.Alert.OnQueuePop()
    check("entrou na partida e a caixa fecha", hiddenPopups[1], "ROCKETSWAP_READY_CHECK")

    -- E o proximo convite volta a avisar -- a trava e por convite, nao para sempre.
    status = "confirm"
    ns.Alert.OnQueuePop()
    check("o convite seguinte avisa de novo", #shownPopups, 2)

    -- DESLIGAVEL, como os outros dois avisos (/rs queue).
    status = "none"; ns.Alert.OnQueuePop()
    ns.db.queuePop = false
    status = "confirm"
    wipe(shownPopups)
    ns.Alert.OnQueuePop()
    check("desligado nao abre caixa nenhuma", #shownPopups, 0)

    ns.db.queuePop = true
    status = "none"
    ns.Alert.OnQueuePop()
    GetBattlefieldStatus = real
end

-- E O RESUMO ESPERA UM OK. Pedido do usuario: "como mostra o aviso e some, o usuario pode nem
-- ver". Ele tem razao -- o ready check e justamente o momento em que a pessoa esta olhando para
-- o botao de "Pronto", e chat e aviso de raide somem sozinhos.
do
    wipe(shownPopups)
    ns.db.readyCheck = true
    ns.Alert.OnReadyCheck()

    check("o ready check abre uma caixa", #shownPopups, 1)
    check("e e a nossa", shownPopups[1].which, "ROCKETSWAP_READY_CHECK")
    check("com o resumo dentro",
        shownPopups[1].text and shownPopups[1].text:find("Gelido", 1, true) ~= nil, true)

    -- E COM OS ROTULOS, uma linha por campo. Conferir so o `Summary` deixaria passar a caixa
    -- sendo montada com a versao de UMA LINHA -- que era o estado anterior e e o defeito
    -- relatado: "ta os nomes salvos soltos e nao sei o que e o que".
    local naCaixa = shownPopups[1].text
    check("a caixa rotula a especializacao",
        naCaixa:find(ns.L["Specialization"] .. ": ", 1, true) ~= nil, true)
    check("a caixa rotula os itens",
        naCaixa:find(ns.L["Gear"] .. ": ", 1, true) ~= nil, true)

    -- Tres campos em tres linhas, mais o titulo e a linha em branco antes dele.
    check("e poe um campo por linha",
        select(2, naCaixa:gsub(string.char(10), "")) >= 4, true)

    -- O TITULO DA CAIXA NAO LEVA DOIS-PONTOS. `L["ready check:"]` e PREFIXO de linha de chat, e
    -- la o dois-pontos esta certo; como titulo, seguido de linha em branco, fica pendurado. A
    -- linha de chat chegou a ter TRES: "RocketSwap: conferencia: Especializacao: Gelido".
    -- `string.char(10)` e nao um escape: o shell desta maquina come a barra invertida em
    -- heredoc, e o padrao chegou aqui com um 0x08 no lugar da quebra de linha. Construir o
    -- caractere pelo codigo nao depende de escape nenhum.
    local NL = string.char(10)
    local titulo = naCaixa:match("^(.-)" .. NL) or naCaixa
    check("o titulo da caixa nao termina em dois-pontos",
        titulo and titulo:sub(-1) ~= ":", true)
    check("e o titulo nomeia o CONTEUDO", titulo, ns.L["What you are using"])

    -- ⚑ E NAO USA A PALAVRA DOS PRESETS. `conjunto` e o nome do container aqui
    -- (`L["Presets"] = "Conjuntos"`), e a caixa mostra os CAMPOS que estao valendo -- que podem
    -- nao bater com preset nenhum. Chamar isso de "conjunto atual" mentiria justo na hora em que
    -- o descasamento e a informacao.
    check("  sem prometer um preset", titulo:lower():find("conjunto", 1, true), nil)

    -- A CAIXA NAO PODE FECHAR SOZINHA: e o unico motivo de ela existir.
    local dialogo = StaticPopupDialogs["ROCKETSWAP_READY_CHECK"]
    check("a caixa nao tem prazo", dialogo.timeout, 0)
    check("e aparece mesmo morto", dialogo.whileDead, 1)

    -- E DESLIGADO NAO ABRE NADA. A caixa e mais intrusiva que o chat; respeitar a opcao importa
    -- mais aqui do que importava antes.
    wipe(shownPopups)
    ns.db.readyCheck = false
    ns.Alert.OnReadyCheck()
    check("desligado nao abre caixa nenhuma", #shownPopups, 0)
    ns.db.readyCheck = true
end

print("== aparencia (transmog) e opcional ==")
-- Pedido do usuario: "poderia por como opcional o transmog salvo tambem?". Opcional de
-- verdade — conjunto sem aparencia definida NAO pode mexer na roupa.
check("duas aparencias utilizaveis", #ns.Data.GetOutfits(), 2)
check("a desabilitada nao entra na lista",
    (function()
        for _, o in ipairs(ns.Data.GetOutfits()) do
            if o.name == "Antigo" then return true end
        end
        return false
    end)(), false)
check("nome por id", ns.Data.OutfitName(88), "Arena")

-- O ID E O INDICE SAO DIFERENTES, e continuam sendo o ponto: o conjunto guarda o ID 88 e a acao
-- segura pede o INDICE 2. Guardar o indice apodreceria -- ele desloca quando uma aparencia e
-- apagada, e o comentario da propria Blizzard diz por que ("outfitIDs may have gaps").
check("o indice se resolve a partir do id", ns.Data.OutfitIndex(88), 2)
check("e o id que nao existe mais nao resolve", ns.Data.OutfitIndex(999), nil)

-- A ORDEM DOS PASSOS MUDOU DE SIGNIFICADO na 0.10.0, e o teste antigo media a ordem errada.
--
-- Ele travava "os itens vao primeiro, a roupa depois", com a razao de que aplicar a roupa antes
-- seria escrever por cima do que o passo de itens ainda vai mudar. Essa razao era boa enquanto o
-- ADDON aplicava a roupa. Ele nao aplica mais: a aparencia entra no proprio clique, ou seja
-- ANTES de tudo, e nao ha como ser diferente -- a acao segura roda no clique e o resto no
-- PostClick.
--
-- O que sobra a travar e o que continua nosso: os itens so vao depois da spec e dos talentos.
state.equippedSet, state.pendingSet = 1, nil
state.specIndex = 1
ns.Data.Apply({ name = "Arena", spec = 2, gear = 4 }, function() end)
check("os itens NAO vao antes da spec", state.pendingSet, nil)
state.specIndex = 2
fire("ACTIVE_PLAYER_SPECIALIZATION_CHANGED")
check("e vao depois dela", state.pendingSet, 4)
state.equippedSet = 4
fire("EQUIPMENT_SWAP_FINISHED", true, 4)

-- Aparencia apagada entre o salvamento e o uso: tem que avisar, e com o motivo proprio.
state.outfit = 71
local erroRoupa
ns.Data.Apply({ name = "Fantasma", spec = 2, transmog = 999 }, function(t, isErr)
    if isErr then erroRoupa = t end
end)
check("aparencia inexistente avisa", erroRoupa ~= nil, true)
check("dizendo que ela nao existe mais",
    erroRoupa and erroRoupa:lower():find("n\195\163o existe mais") ~= nil, true)

print("== janela: estado vazio ==")
-- Reclamacao literal do usuario: "fica tudo vazio quando nao tem nada". Com zero conjuntos a
-- janela mostra UM bloco central, e nada mais — nem lista, nem rotulos orfaos.
ns.db.presets = {}
-- ABRE SE ESTIVER FECHADA, em vez de alternar. `Toggle` alterna, e este bloco dependia -- sem
-- dizer -- de a janela estar fechada quando chegasse aqui. Quem a abria era o teste de COMANDOS
-- trinta linhas acima (`/rs` sem argumento alterna a janela), a dezenas de linhas de distancia.
-- Mexer em qualquer bloco anterior quebrava este, e o erro apontava para o lugar errado.
if not ns.UI.IsShown() then ns.UI.Toggle() end
ns.UI.Refresh()
check("nenhum conjunto selecionado com a lista vazia", ns.UI.Selected(), nil)

print("== as caixas de aviso ficam visiveis SEM conjunto nenhum ==")
-- O motivo de existirem: os dois avisos sao o que o addon faz por quem nunca cria conjunto.
-- Se eles so existissem em /rs warn e /rs ready, ninguem descobriria. E se sumissem junto com
-- a lista na tela vazia, sumiriam exatamente no caso que os justifica.
check("ligados por padrao",
    ns.db.warnPvE ~= false and ns.db.warnPvP ~= false and ns.db.readyCheck ~= false, true)
check("a faixa existe", ns.UI.DebugToggles() ~= nil, true)
check("e nao e escondida com a lista vazia",
    ns.UI.DebugToggles().__shown ~= false, true)

-- Desmarcar escreve no banco, e o aviso obedece. A caixa e a de PvP porque o cenario abaixo e
-- uma arena: desde 0.35.0 cada conteudo tem a sua, e desligar a de PvE nao calaria esta.
local caixa = ns.UI.DebugToggles().warnPvP
caixa.__checked = false
caixa.__scripts.OnClick(caixa)
check("desmarcar desliga o aviso de PvP", ns.db.warnPvP, false)

state.instance = "arena"
VestirTudo(false)
ns.Gear.ClearCache()
ns.Alert.Check("teste")
check("e com ele desligado o addon nao avisa", ns.Alert.__Shown(), false)

caixa.__checked = true
caixa.__scripts.OnClick(caixa)
check("remarcar religa", ns.db.warnPvP, true)
state.instance = nil

print("== janela: selecao automatica ==")
-- Os bugs 2 e 3 (rotulo sem campo, texto colado) vinham do estado "nada selecionado". Ele
-- deixou de existir: com pelo menos um conjunto a lista seleciona o primeiro sozinha. Se
-- alguem tirar essa selecao automatica, este teste cai e os dois bugs voltam juntos.
ns.UI.New()
check("criar ja seleciona", ns.UI.Selected() ~= nil, true)
check("o conjunto novo nasce com a spec atual", ns.UI.Selected().spec, 2)
check("e com o conjunto de itens vestido", ns.UI.Selected().gear, 4)

ns.UI.Refresh()
check("refresh mantem a selecao", ns.UI.Selected() ~= nil, true)

print("== janela: apagar usa a TABELA, nao o indice ==")
-- Bug latente da versao anterior: `selected` era um indice, e `table.remove` desloca os
-- indices — apagar um fazia a selecao apontar para outro conjunto. Agora ela guarda a
-- propria tabela do conjunto.
ns.db.presets = {}
for _, nome in ipairs({ "Um", "Dois", "Tres" }) do
    ns.UI.New()
    ns.UI.Selected().name = nome
end
ns.UI.Refresh()
check("tres conjuntos", #ns.db.presets, 3)

local alvo = ns.UI.Selected()
check("ha um selecionado", alvo ~= nil, true)
ns.UI.Delete()
check("sobraram dois", #ns.db.presets, 2)
check("saiu exatamente o que estava selecionado",
    ns.db.presets[1] ~= alvo and ns.db.presets[2] ~= alvo, true)

print("== janela: o que o teste in-game reprovou ==")
-- Quatro bugs relatados pelo usuario, todos com o mesmo tipo de causa: eu confiei numa API
-- sem ler o retorno dela, e o simulador antigo confirmou a minha versao em vez da real.
-- Estes checks falham se qualquer um deles voltar.

ns.db.presets = {}
if not ns.UI.IsShown() then ns.UI.Toggle() end   -- abre se preciso; nao alterna
ns.UI.New(); ns.UI.Selected().name = "Mitica"
ns.UI.New(); ns.UI.Selected().name = "Arena"
ns.UI.Refresh()
check("dois conjuntos", #ns.db.presets, 2)

-- (1) "nao consigo clicar em outros conjuntos": a linha nao tinha OnClick nenhum. O
-- AddSelectionBehavior gerencia o ESTADO da selecao, nao captura o clique.
check("a linha responde ao clique",
    (function()
        local list = ns.UI.DebugList and ns.UI.DebugList()
        if not list or not list.__rows or not list.__rows[2] then return "sem linhas" end
        local row = list.__rows[2]
        if not row.__scripts.OnClick then return "sem OnClick" end
        row.__scripts.OnClick(row)
        return ns.UI.Selected() == ns.db.presets[2]
    end)(), true)

-- (2) "quando seleciono a especializacao, nada muda": Current() devolvia a LISTA vazia do
-- GetSelectedElementData, entao o set escrevia numa tabela descartavel.
local alvo = ns.UI.Selected()
check("ha um conjunto de verdade selecionado", type(alvo) == "table" and alvo.name ~= nil, true)
check("e ele esta na lista", alvo == ns.db.presets[2], true)

alvo.spec = 3
ns.UI.AfterEdit()
check("escrever a spec pega no conjunto certo", ns.db.presets[2].spec, 3)

-- (3) "o combo de talentos nao traz nada": sem spec valida, GetLoadouts(nil) devolve vazio.
-- Com a spec certa (Gelido = indice 2, id 251), tem que trazer os tres loadouts.
alvo.spec = 2
local spec = ns.Data.GetSpecByIndex(alvo.spec)
check("a spec resolve", spec ~= nil and spec.id, 251)
check("e ai o combo de talentos tem itens", #ns.Data.GetLoadouts(spec.id), 3)
check("sem spec, nao tem (era o sintoma)", #ns.Data.GetLoadouts(nil), 0)

-- (4) "a delecao nao funcionou": Delete procurava a tabela vazia na lista e nao achava.
local antes = #ns.db.presets
local paraApagar = ns.UI.Selected()
ns.UI.Delete()
check("apagou um", #ns.db.presets, antes - 1)
check("e foi o selecionado", ns.db.presets[1] ~= paraApagar, true)

print("== recusa do LoadConfig sem motivo e transitoria ==")
-- O DEFEITO RELATADO EM 07/09 21:1x, e o usuario descreveu o sintoma melhor que qualquer log:
-- *"ele trocou tudo, exceto pelo talento, acabou ficando o talento de PVE do Frost... deve ter
-- pego a primeira build, que era de pve"*.
--
-- O diario mostrou a causa exata:
--
--     SetSpecialization(2)   -> true
--     ACTIVE_PLAYER_SPECIALIZATION_CHANGED
--     LoadConfig(66832448)   -> result = 0 (Error), changeError = nil
--
-- `Error` e 0 mesmo (`ClassTalentsDocumentation.lua:501`), entao chamar de falha estava certo.
-- Errado era DESISTIR: `changeError` veio nil -- o jogo recusou sem dizer por que, logo depois de
-- reescrever a arvore inteira ao trocar a spec. Como o loadout nunca entrou, o jogo ficou com a
-- build que ja estava ativa naquela spec: a de PvE.
do
    state.specIndex, state.equippedSet = 1, 9
    state.activeLoadout[251] = 10

    -- Duas recusas sem motivo, e depois o jogo aceita.
    state.loadRefusals, state.loadError = 2, nil

    local ultimo
    ns.Data.Apply({ name = "Frost PvP", spec = 2, talent = 11 }, function(t) ultimo = t end)

    state.specIndex = 2
    fire("ACTIVE_PLAYER_SPECIALIZATION_CHANGED")

    -- Primeira recusa: o passo NAO pode ter desistido.
    local passos = ns.Data.GetProgress()
    check("recusado sem motivo, o talento continua em andamento", passos[2].state, "doing")
    check("e o addon esta insistindo", state.loadRefusals, 1)

    RunTimers(5)          -- segunda tentativa, recusada de novo
    RunTimers(5)          -- terceira, e agora o jogo aceita
    check("o jogo aceitou na terceira", state.pendingLoadout, 11)

    gravacaoTermina(999)
    passos = ns.Data.GetProgress()
    check("e o passo fecha como concluido", passos[2].state, "done")

    state.loadRefusals = 0
end

print("== gravar talento e um cast: os itens esperam ele acabar ==")
-- O DEFEITO DE 11/09 17:19:53 (*"fui usar o rocketswap pra trocar de tank para pvp frost e nao
-- deu, gerou erro"*), e o de 09/09 17:22:02 e 17:58:14, todos com a mesma forma:
--
--     ACTIVE_PLAYER_SPECIALIZATION_CHANGED
--     LoadConfig              -> LoadInProgress
--     TRAIT_CONFIG_UPDATED 59714245   \  eco da troca de spec, no mesmo instante --
--     TRAIT_CONFIG_UPDATED 59714244   /  o addon fechava o passo no primeiro
--     EQUIPMENT_SWAP_FINISHED -> false     (16 pecas na bolsa, 0 perdidas)
--     TRAIT_CONFIG_UPDATED 59714245      5 s depois: a gravacao terminando de verdade
--
-- O stub nao produzia o eco, entao o teste mandava UM evento e ele era, por construcao, o
-- verdadeiro. O que o simulador nao sabe representar, o teste nao ve.
local function abreGravacao()
    state.specIndex, state.equippedSet = 1, 9
    state.pendingSet, state.pendingLoadout = nil, nil
    state.activeLoadout[251] = 10
    ns.Data.Apply({ name = "Frost PvP", spec = 2, talent = 11, gear = 4 }, function() end)
    state.specIndex = 2
    fire("ACTIVE_PLAYER_SPECIALIZATION_CHANGED")
    -- o eco, como o jogo o manda: dois eventos, no instante da troca, com o id do verdadeiro
    fire("TRAIT_CONFIG_UPDATED", 59714245)
    fire("TRAIT_CONFIG_UPDATED", 59714244)
end

do
    abreGravacao()
    check("a troca de spec abriu a gravacao", state.pendingLoadout, 11)
    check("o eco da troca de spec nao pede os itens", state.pendingSet, nil)
    check("nem da os talentos por gravados", estadoDoPasso("talent"), "doing")
    check("nem marca o loadout como selecionado", state.activeLoadout[251], 10)

    fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-a", 12345)
    fire("UNIT_SPELLCAST_SUCCEEDED", "target", "cast-b", 384255)
    check("cast alheio nao fecha a gravacao", state.pendingSet, nil)

    fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-c", 384255)
    check("o fim do cast de gravacao libera os itens", state.pendingSet, 4)
    check("e so entao o loadout vira o selecionado", state.activeLoadout[251], 11)

    state.equippedSet = 4
    fire("EQUIPMENT_SWAP_FINISHED", true, 4)
    check("e a corrente termina", ns.Data.IsApplying(), false)
end

do
    -- A RESERVA: sem o cast visivel, o `TRAIT_CONFIG_UPDATED` tardio fecha.
    abreGravacao()
    check("o eco sozinho nao fecha", state.pendingSet, nil)
    AdvanceClock(5)
    fire("TRAIT_CONFIG_UPDATED", 59714245)
    check("o evento tardio fecha a gravacao", state.pendingSet, 4)
    state.equippedSet = 4
    fire("EQUIPMENT_SWAP_FINISHED", true, 4)
    check("e a corrente termina pela reserva", ns.Data.IsApplying(), false)
end

do
    -- A GRAVACAO QUE FALHA vira falha anotada, e os itens seguem.
    abreGravacao()
    fire("CONFIG_COMMIT_FAILED", 59714245)
    check("gravacao que falha vira falha anotada", estadoDoPasso("talent"), "failed")
    check("e os itens seguem mesmo assim", state.pendingSet, 4)
    state.equippedSet = 4
    fire("EQUIPMENT_SWAP_FINISHED", true, 4)
    check("e a corrente nao fica presa", ns.Data.IsApplying(), false)
end

do
    -- NA INSISTENCIA NAO HA GRAVACAO NOSSA. `LoadConfig` devolveu `Error` sem motivo, o addon vai
    -- perguntar de novo em 4 s, e o eco chega no meio. As tres correntes do diario que tomaram
    -- esse caminho fecharam NO ECO e anunciaram "pronto" -- sem nada que provasse que os talentos
    -- entraram.
    state.loadRefusals, state.loadError = 1, nil
    abreGravacao()
    check("recusado, o talento nao foi carregado", state.pendingLoadout, nil)
    check("o eco nao confirma o que o jogo recusou", estadoDoPasso("talent"), "doing")
    check("nem marca o loadout", state.activeLoadout[251], 10)
    check("nem pede os itens", state.pendingSet, nil)

    RunTimers(5)                      -- a insistencia pergunta de novo, e o jogo aceita
    check("a insistencia abriu a gravacao", state.pendingLoadout, 11)
    fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-d", 384255)
    check("e o fim do cast fecha como sempre", state.pendingSet, 4)
    state.equippedSet = 4
    fire("EQUIPMENT_SWAP_FINISHED", true, 4)
    check("e a corrente termina depois da insistencia", ns.Data.IsApplying(), false)
    state.loadRefusals = 0
end

print("== o cast que acabou de terminar ainda consta ==")
-- O DEFEITO DE 11/09 17:45:47, Tank -> Frost PvE ST, a primeira troca que exercitou a 0.22.0:
--
--     17:46:01  UNIT_SPELLCAST_SUCCEEDED 384255   gravou por=cast segundos=5.2
--     17:46:01  passo gear -> fail "voce esta conjurando algo"
--
-- O SUCCEEDED chega com o cast ainda constando em `UnitCastingInfo`; so o STOP o encerra
-- (`CastingBarFrame.lua:459,482-483`). O stub devolvia sempre nil, entao isso nao existia aqui.
do
    abreGravacao()
    state.casting = 384255
    fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-e", 384255)
    check("o cast em curso nao derruba os itens", estadoDoPasso("gear"), "doing")
    check("mas tambem nao equipa por cima dele", state.pendingSet, nil)

    state.casting = nil
    fire("UNIT_SPELLCAST_STOP", "player", "cast-e", 384255)
    check("o fim do cast libera os itens", state.pendingSet, 4)
    state.equippedSet = 4
    fire("EQUIPMENT_SWAP_FINISHED", true, 4)
    check("e a corrente termina sem falha", ns.Data.IsApplying(), false)
end

do
    -- FIM DE CAST DE OUTRA UNIDADE nao conta; e quem NAO PARA DE CONJURAR faz o passo desistir no
    -- teto, em vez de a corrente ficar pendurada.
    abreGravacao()
    state.casting = 384255
    fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-f", 384255)
    fire("UNIT_SPELLCAST_STOP", "target", "cast-g", 1)
    check("fim de cast de outra unidade nao libera", state.pendingSet, nil)

    for i = 1, 5 do fire("UNIT_SPELLCAST_STOP", "player", "cast-h" .. i, 1) end
    check("cast sem fim desiste no teto", state.pendingSet, nil)
    check("e a corrente nao fica presa com cast sem fim", ns.Data.IsApplying(), false)
    state.casting = nil
end

print("== prazo vencido nao acusa o que ja esta aplicado ==")
-- ⚑ A MAIOR FONTE DE "ERRO" QUE O JOGADOR VE SEM QUE NADA TENHA DADO ERRADO. O evento de
-- confirmacao pode nao chegar (ou chegar e nao ser nosso) com a troca JA FEITA -- e o addon
-- anunciava "o jogo nao confirmou a tempo" sobre uma spec que virou. Pedido do usuario:
-- *"devo conseguir fazer as trocas sem que tenha erros"*.
do
    state.specIndex, state.equippedSet = 1, 9
    state.pendingSet, state.pendingLoadout, state.pendingSpec = nil, nil, nil
    state.activeLoadout[251] = 10

    local houveErro
    ns.Data.Apply({ name = "Frost PvP", spec = 2, gear = 4 },
        function(_, isError) houveErro = isError end)

    state.specIndex = 2           -- o jogo virou a spec e NAO mandou evento nenhum
    RunTimers()                   -- o prazo do passo vence
    check("prazo vencido com a spec ja virada nao vira falha",
        estadoDoPasso("spec"), "done")
    check("e a corrente segue para os itens", state.pendingSet, 4)

    state.equippedSet = 4
    fire("EQUIPMENT_SWAP_FINISHED", true, 4)
    check("terminando sem erro para o jogador", houveErro, false)
end

print("== combate no meio da corrente pausa, nao falha ==")
-- `Data.Apply` ja enfileirava o clique feito EM combate; entrar em combate DEPOIS de comecar nao
-- era reavaliado, e o jogo recusava passo por passo -- resultado parcial e uma fila de mensagens
-- de erro, tres delas descrevendo a mesma causa.
do
    state.specIndex, state.equippedSet = 1, 9
    state.pendingSet, state.pendingSpec = nil, nil

    ns.Data.Apply({ name = "Frost PvP", spec = 2, gear = 4 }, function() end)
    state.inCombat = true
    state.specIndex = 2
    fire("ACTIVE_PLAYER_SPECIALIZATION_CHANGED")

    check("combate no meio pausa em vez de falhar", state.pendingSet, nil)
    -- ⚑ E PAUSA O PASSO QUE TEM TRABALHO, NAO UM PASSO VAZIO. A primeira versao pausava no passo
    -- de TALENTOS deste conjunto (que so define spec e itens): parado durante a luta inteira num
    -- passo que ia ser pulado, e invisivel na tela -- o painel so desenha o que o conjunto define.
    --
    -- ⚑ E ESTE CHECK VEM ANTES DO DE ANDAMENTO DE PROPOSITO: quando a pausa pega o passo errado,
    -- o de andamento tambem reprova (o passo certo fica "pending"), e a sabotagem apontaria para
    -- o check generico em vez do que descreve o defeito.
    --
    -- A ULTIMA linha, e nao as duas ultimas: a penultima e o `passo=talent resultado=skip`, que e
    -- justamente o certo -- o passo vazio passa e nao para nada.
    local ultima = ns.Log.Tail(1)[1] or ""
    check("e pausa o passo que tem trabalho, nao um passo vazio",
        ultima:find("pausado", 1, true) ~= nil
            and ultima:find("passo=gear", 1, true) ~= nil, true)

    check("o passo pausado segue em andamento", estadoDoPasso("gear"), "doing")
    check("e a corrente nao morreu", ns.Data.IsApplying(), true)

    state.inCombat = false
    fire("PLAYER_REGEN_ENABLED")
    check("acabou a luta, o passo vai", state.pendingSet, 4)
    state.equippedSet = 4
    fire("EQUIPMENT_SWAP_FINISHED", true, 4)
    check("e termina normalmente depois do combate", ns.Data.IsApplying(), false)
end

print("== id apagado tem frase propria ==")
-- APAGADO E DIFERENTE DE RECUSADO: a frase genarica manda o jogador procurar peca faltando onde o
-- problema e que ele apagou o loadout/conjunto. A aparencia ja dizia; estas duas nao.
do
    state.specIndex, state.equippedSet = 2, 1
    state.activeLoadout[251] = 10

    local texto
    ns.Data.Apply({ name = "Fantasma", talent = 777 }, function(t) texto = t end)
    check("loadout apagado diz que nao existe mais",
        texto ~= nil and texto:find("existe mais", 1, true) ~= nil, true)

    texto = nil
    ns.Data.Apply({ name = "Fantasma2", gear = 77 }, function(t) texto = t end)
    check("conjunto de itens apagado diz que nao existe mais",
        texto ~= nil and texto:find("existe mais", 1, true) ~= nil, true)
end

print("== recarga da magia de spec espera, nao aborta ==")
-- A recarga acaba em segundos e a insistencia ja existe; abortar era devolver erro ao jogador por
-- algo que se resolve esperando. Motivo EM TEXTO continua abortando -- ai o jogo explicou.
do
    state.specIndex, state.equippedSet = 1, 9
    state.pendingSpec, state.pendingSet = nil, nil
    RocketSwapLogDB.specSpellID = state.specSpellID     -- o addon ja aprendeu a magia
    state.specSpellOnCooldown = true

    local houveErro
    ns.Data.Apply({ name = "Frost PvP", spec = 2, gear = 4 },
        function(_, isError) houveErro = isError end)
    check("na recarga o passo nao aborta", ns.Data.IsApplying(), true)
    check("e nada foi pedido ao jogo", state.pendingSpec, nil)

    state.specSpellOnCooldown = false
    RunTimers(5)                  -- a insistencia tenta de novo
    check("passada a recarga, a troca vai", state.pendingSpec, 2)

    state.specIndex = 2
    fire("ACTIVE_PLAYER_SPECIALIZATION_CHANGED")
    state.equippedSet = 4
    fire("EQUIPMENT_SWAP_FINISHED", true, 4)
    check("e termina sem erro depois da recarga", houveErro, false)
end

print("== cast de troca de spec cortado tenta de novo ==")
-- ⚑ ANDAR CORTA O CAST, e `SPECIALIZATION_CHANGE_CAST_FAILED` nao cobre isso -- a janela nativa
-- descobre pelos eventos de cast filtrando `IsSpecializationActivateSpell`
-- (`Blizzard_ClassSpecializationsFrame.lua:185-190`). Sem isto, andar custava os 45 s do prazo e
-- terminava com "o jogo nao confirmou a tempo", sem o jogador ter feito nada de errado.
do
    state.specIndex, state.equippedSet = 1, 9
    state.pendingSpec, state.pendingSet = nil, nil

    ns.Data.Apply({ name = "Frost PvP", spec = 2, gear = 4 }, function() end)
    check("pediu a troca de spec", state.pendingSpec, 2)

    state.pendingSpec = nil
    fire("UNIT_SPELLCAST_INTERRUPTED", "player", "cast-i", state.specSpellID)
    check("cast cortado pede a troca de novo", state.pendingSpec, 2)

    state.pendingSpec = nil
    fire("UNIT_SPELLCAST_INTERRUPTED", "player", "cast-j", 12345)
    check("cast de outra magia nao mexe na corrente", state.pendingSpec, nil)

    -- O TETO: corte atras de corte nao pendura a corrente.
    for i = 1, 4 do
        fire("UNIT_SPELLCAST_FAILED", "player", "cast-k" .. i, state.specSpellID)
    end
    check("no teto desiste e segue para os itens", state.pendingSet, 4)
    state.equippedSet = 4
    fire("EQUIPMENT_SWAP_FINISHED", true, 4)
    check("e nao fica presa depois dos cortes", ns.Data.IsApplying(), false)
end

print("== interrupcao por /reload deixa marca no diario ==")
-- `running` e memoria: no /reload a corrente evapora, o `Finish` nao roda e o diario terminava no
-- ultimo passo. Quem le depois nao distinguia "ficou pela metade" de "o addon travou".
do
    state.specIndex, state.equippedSet = 1, 9
    state.pendingSet, state.pendingSpec = nil, nil
    ns.Log.Clear()

    ns.Data.Apply({ name = "Frost PvP", spec = 2, gear = 4 }, function() end)
    fire("PLAYER_LEAVING_WORLD")

    local texto = table.concat(ns.Log.Tail(6), " ~ ")
    check("a interrupcao vira linha no diario",
        texto:find("interrompido", 1, true) ~= nil, true)
    check("e o evento em si nao mata a corrente", ns.Data.IsApplying(), true)

    state.specIndex = 2
    fire("ACTIVE_PLAYER_SPECIALIZATION_CHANGED")
    state.equippedSet = 4
    fire("EQUIPMENT_SWAP_FINISHED", true, 4)
end

do
    -- COM MOTIVO DECLARADO, NAO INSISTE. Quando o jogo diz o que houve -- combate, area errada --
    -- repetir a pergunta ja respondida so atrasa a resposta ao jogador.
    state.specIndex, state.equippedSet = 2, 9
    state.activeLoadout[251] = 10
    state.loadRefusals, state.loadError = 3, "Voce nao pode fazer isso em combate"

    local ultimo
    ns.Data.Apply({ name = "So talento", talent = 11 }, function(t) ultimo = t end)

    local passos = ns.Data.GetProgress()
    check("com motivo, falha na hora", passos[1].state, "failed")
    check("e a mensagem usa as palavras do jogo",
        (ultimo or ""):find("combate") ~= nil, true)
    check("nao gastou tentativa nenhuma a mais", state.loadRefusals, 2)

    state.loadRefusals, state.loadError = 0, nil
end

do
    -- O TETO. Se a recusa nunca passar, o passo desiste -- e desiste como FALHA, nao ficando
    -- pendurado em andamento para sempre.
    state.specIndex, state.equippedSet = 2, 9
    state.activeLoadout[251] = 10
    state.loadRefusals, state.loadError = 99, nil

    local ultimo
    ns.Data.Apply({ name = "Teimoso", talent = 11 }, function(t) ultimo = t end)
    for _ = 1, 10 do RunTimers(5) end

    check("desistiu depois do teto", ns.Data.IsApplying(), false)
    check("e o passo ficou como falha", ns.Data.GetProgress()[1].state, "failed")
    check("com a frase de desistencia",
        (ultimo or ""):find("continuou recusando carregar") ~= nil, true)

    state.loadRefusals = 0
end

print("== o painel de etapas: a troca vista de fora ==")
-- Pedido do usuario: *"quando clica para carregar, ele demora para iniciar o cast, o usuario vai
-- pensar que nada aconteceu... algo animado e bem didatico que o usuario entenda"* que a troca
-- *"e um processo de troca por etapas"*.
--
-- O simulador nao desenha; o que estes checks travam sao as afirmacoes que o painel FAZ, e cada
-- uma delas ja foi falsa em alguma versao desta corrente.

ns.db.presets = {}
if not ns.UI.IsShown() then ns.UI.Toggle() end
local painel = ns.UI.DebugProgress()
check("a janela tem o painel", painel ~= nil, true)

-- QUEM FECHA O PAINEL NAO E QUEM O ABRIU. A secao anterior deixou uma troca terminada com o
-- painel aberto; o quadro seguinte tem que dar conta dela sozinho. E o motivo de o `OnUpdate`
-- morar na JANELA e nao no painel: `OnUpdate` de frame escondido nao roda, e o painel comeca
-- escondido -- preso nele, o progresso nunca apareceria nem sumiria por conta propria.
TickUI()
check("a troca que terminou ainda mostra o resultado", painel:IsShown(), true)
AdvanceClock(ns.UI.DebugMetrics().hold + 1)
TickUI()
check("e o quadro seguinte fecha o painel sozinho", painel:IsShown(), false)

do
    -- O MUNDO ANTES DA TROCA. Sem acertar isto o passo de talentos recusa por estar na spec
    -- errada, e o teste mediria uma falha DELE em vez do painel.
    state.specIndex, state.equippedSet, state.outfit = 2, 9, nil

    -- E UM CONJUNTO DE VERDADE, SELECIONADO. Sem ele o editor ja estaria escondido por nao ter o
    -- que editar, e o check "o editor cede a coluna" passaria sem o painel ter feito nada.
    ns.UI.New()
    local preset = ns.UI.Selected()
    preset.name, preset.spec, preset.talent, preset.gear, preset.transmog = "Tank", 1, 12, 3, nil
    ns.UI.RefreshEditor()
    local _, ed = ns.UI.DebugProgress()
    check("com conjunto selecionado, o editor esta em cena", ed.name:IsShown(), true)

    ns.Data.Apply(preset, function() end)
    check("e o quadro seguinte abre o painel, sem ninguem mandar", (function()
        TickUI()
        return painel:IsShown()
    end)(), true)

    -- SO OS PASSOS QUE O CONJUNTO PEDE. Este conjunto nao tem aparencia, entao ele NAO ganha uma
    -- quarta linha dizendo "nada a mudar" -- linha que so nega e ruido, e enterra as que importam.
    local passos, info = ns.Data.GetProgress()
    check("tres passos, nao quatro", #passos, 3)
    check("e nenhum deles e a aparencia", passos[3].key, "gear")

    check("a troca esta viva", info.live, true)
    check("o primeiro passo esta em andamento", passos[1].state, "doing")
    check("e os seguintes ainda nao", passos[3].state, "pending")

    -- O EDITOR CEDE A COLUNA. Nao e so para nao sobrepor: mexer nos combos do conjunto que esta
    -- sendo aplicado muda o alvo no meio do caminho, e a corrente ja leu o que ia ler.
    check("o editor sai de cena enquanto o painel esta nela", ed.name:IsShown(), false)

    -- O PASSO EM ANDAMENTO PULSA, e so ele.
    check("pulsa exatamente um passo", (function()
        local n = 0
        for _, row in ipairs(painel.rows) do if row.__pulsing then n = n + 1 end end
        return n
    end)(), 1)

    -- O RELOGIO ANDA. E a resposta a "aconteceu alguma coisa?" nos segundos em que o addon esta
    -- de proposito esperando o jogo liberar a troca de spec.
    local antes = painel.clock:GetText()
    AdvanceClock(7)
    ns.UI.RefreshProgress()
    check("o relogio anda", painel.clock:GetText() ~= antes, true)

    state.specIndex = 1                      -- o jogo virou a spec de verdade
    fire("ACTIVE_PLAYER_SPECIALIZATION_CHANGED")
    passos = ns.Data.GetProgress()
    check("spec confirmada vira concluida", passos[1].state, "done")
    check("e o passo seguinte assume o andamento", passos[2].state, "doing")

    gravacaoTermina(999)
    check("talentos confirmados", ns.Data.GetProgress()[2].state, "done")

    fire("EQUIPMENT_SWAP_FINISHED", true, 3)
    passos = ns.Data.GetProgress()
    check("itens confirmados", passos[3].state, "done")

    ns.UI.RefreshProgress()
    check("o rotulo e o mesmo do editor", painel.rows[1].label:GetText(), ns.L["Specialization"])
    check("a altura acompanha as tres etapas", painel:GetHeight(),
        ns.UI.DebugMetrics().row * 3 + ns.UI.DebugMetrics().titleGap + 16)

    -- A PAUSA. O resultado fica na tela tempo de ser lido -- senao o painel some no instante em
    -- que ele finalmente tem algo a dizer.
    local _, depois = ns.Data.GetProgress()
    check("a troca acabou", depois.live, false)
    check("mas o resultado continua na tela", painel:IsShown(), true)
    check("e nada mais pulsa", (function()
        for _, row in ipairs(painel.rows) do if row.__pulsing then return true end end
        return false
    end)(), false)

    AdvanceClock(ns.UI.DebugMetrics().hold + 1)
    ns.UI.RefreshProgress()
    check("passada a pausa, o painel devolve a coluna", painel:IsShown(), false)
    check("e o editor volta com ela", ed.name:IsShown(), true)
end

print("== 'pulado' nao pode mentir sobre o que acabou de mudar ==")
-- O DEFEITO: `Steps.*` devolve "skip" por tres razoes, e as tres viravam a mesma frase na tela.
-- A da aparencia e a pior: quem troca a roupa e o clique seguro, no primeiro instante; quando o
-- passo dela roda, dois passos depois, a roupa ja esta certa e ele devolve "skip". O painel
-- anunciava "Aparencia -- nada a mudar" sobre a peca que aquele clique acabara de trocar.
do
    state.specIndex, state.equippedSet, state.outfit = 2, 9, 70

    -- `byClick = true`: a acao segura de aparencia JA disparou no proprio clique. Sem essa
    -- bandeira o passo recusa por nao poder agir, e o teste mediria outra coisa.
    local preset = { name = "Com roupa", spec = 1, transmog = 71 }
    ns.Data.Apply(preset, function() end, true)

    -- A ORDEM REAL, e ela e o coracao do defeito: a roupa troca no PRIMEIRO instante (foi o
    -- clique), e a resposta do jogo chega enquanto a corrente ainda esta no passo de spec --
    -- onde ela e descartada de proposito, porque o passo em curso nao e o da aparencia.
    state.outfit = 71
    fire("TRANSMOG_DISPLAYED_OUTFIT_CHANGED")

    state.specIndex = 1
    fire("ACTIVE_PLAYER_SPECIALIZATION_CHANGED")

    -- Agora o passo da aparencia roda, ve que ja esta certo e devolve "skip". O que a tela NAO
    -- pode dizer e "nada a mudar": mudou, e por causa deste mesmo clique.
    local passos = ns.Data.GetProgress()
    check("a aparencia mudou no meio do caminho", passos[2].state, "done")

    state.outfit = nil
end

do
    -- E O CASO EM QUE "nada a mudar" E VERDADE: ja estava certo ANTES de o clique acontecer.
    state.specIndex, state.equippedSet, state.outfit = 2, 9, 71

    local preset = { name = "Ja vestido", spec = 1, transmog = 71 }
    ns.Data.Apply(preset, function() end, true)
    ns.UI.RefreshProgress()          -- com a troca VIVA, senao o painel nem abre

    state.specIndex = 1
    fire("ACTIVE_PLAYER_SPECIALIZATION_CHANGED")

    local passos = ns.Data.GetProgress()
    check("o que ja estava certo antes e que e 'nada a mudar'", passos[2].state, "skipped")
    check("e pulado nao tem arte de falha", ns.UI.DebugMetrics().states.skipped.atlas, nil)

    ns.UI.RefreshProgress()
    check("e o rotulo diz por que",
        painel.rows[2].label:GetText():find("nada a mudar") ~= nil, true)

    state.outfit = nil
end

do
    -- CONJUNTO SO DE ITENS: uma linha, nao quatro.
    state.equippedSet = 9
    ns.Data.Apply({ name = "So itens", gear = 3 }, function() end)
    check("uma etapa, uma linha", #ns.Data.GetProgress(), 1)
    ns.UI.RefreshProgress()
    check("o painel abriu", painel:IsShown(), true)
    check("e as outras vagas ficam fechadas", painel.rows[2]:IsShown(), false)
    fire("EQUIPMENT_SWAP_FINISHED", true, 3)
end

do
    -- O PRAZO VENCIDO NAO PODE VIRAR VISTO VERDE. Este e o defeito que eu mesmo plantei ao ligar
    -- o painel: o prazo chama `RunNext`, e o `RunNext` fecha como "done" o passo que ainda estava
    -- em "doing" -- porque e assim que ele registra uma confirmacao do jogo. Sem marcar a falha
    -- antes, um passo que o jogo NUNCA confirmou ganharia um checkmark ao lado da mensagem de
    -- falha logo abaixo dele.
    state.equippedSet = 9
    ns.Data.Apply({ name = "Vai vencer", gear = 3 }, function() end)
    check("itens em andamento", ns.Data.GetProgress()[1].state, "doing")

    RunTimers()          -- o prazo do passo vence sem o evento chegar

    local passos = ns.Data.GetProgress()
    check("prazo vencido e FALHA, nao conclusao", passos[1].state, "failed")
    check("e nao ficou passo pendurado em andamento", (function()
        for _, passo in ipairs(passos) do
            if passo.state == "doing" then return passo.key end
        end
        return false
    end)(), false)
end

do
    -- DESISTENCIA TAMBEM NAO DEIXA PASSO PENDURADO. Quando o jogo recusa a troca de spec ate o
    -- teto de tentativas, a corrente desiste -- e o passo fica em "doing" ate alguem resolver.
    -- Quem resolve e o `Finish`, e a regra dele e a mesma do prazo: passo que estava em andamento
    -- na hora do fim e passo que NAO confirmou.
    state.specIndex, state.equippedSet = 2, 9
    state.refuseSpec = true
    local ultimo
    ns.Data.Apply({ name = "Recusado", spec = 1 }, function(t) ultimo = t end)
    check("a spec esta insistindo", ns.Data.GetProgress()[1].state, "doing")

    -- INSISTIR NAO MUDA O QUE A TELA DIZ. Uma versao anterior trocava o relogio por
    -- "tentativa 2 de 8" aqui, e o usuario pediu para tirar: e mecanica interna, o jogador nao
    -- decide nada com ela, e um contador subindo sugere problema onde ha so espera normal.
    -- O relogio continua contando segundos, que e a unica coisa que ele precisa dizer.
    RunTimers(5)                       -- uma reinsistencia, e o jogo recusa de novo
    ns.UI.RefreshProgress()
    local _, info = ns.Data.GetProgress()
    check("o addon esta mesmo insistindo", info.tries > 0, true)
    check("e ainda assim o relogio so conta segundos",
        painel.clock:GetText():match("^%d+s$") ~= nil, true)

    -- SO AS REINSISTENCIAS (4 s), nunca o prazo do passo (45 s). E a diferenca entre medir a
    -- DESISTENCIA -- insistiu ate o teto e parou -- e medir o prazo vencido, que e outro caminho
    -- e ja tem teste proprio logo acima.
    for _ = 1, 12 do RunTimers(5) end
    state.refuseSpec = false

    check("desistiu", ns.Data.IsApplying(), false)
    -- E FOI PELO CAMINHO CERTO. Sem conferir a frase, este bloco passaria tambem quando a
    -- corrente terminasse por PRAZO -- que e o outro caminho, ja coberto acima, e que marca o
    -- passo por uma linha diferente. Dois caminhos, dois testes.
    check("terminou por desistencia, nao por prazo",
        (ultimo or ""):find("continuou recusando") ~= nil, true)
    check("o passo abandonado e falha, nao andamento", ns.Data.GetProgress()[1].state, "failed")
end

print("== o painel: o ritmo, o lugar e a arte ==")
do
    local m = ns.UI.DebugMetrics()

    -- A RAZAO, e nao os numeros crus (skill `wow-ui-design`): o vao entre as tintas de duas
    -- linhas vizinhas contra o vao que separa o titulo do bloco. Foi 1,5x que produziu o
    -- "ta tudo muito junto e grudado"; o piso praticado pela Blizzard e 2x.
    local vaoEntreLinhas = m.row - m.icon                     -- 22 - 16 = 6
    local vaoDoTitulo = m.titleGap + (m.row - m.icon) / 2     -- 13 + 3 = 16
    check("vao entre linhas", vaoEntreLinhas, 6)
    check("o titulo se separa do bloco em pelo menos o dobro",
        vaoDoTitulo >= vaoEntreLinhas * 2, true)
    check("a calha icone->rotulo e a minima praticada", m.iconGap >= 5, true)

    -- O LUGAR. O painel tem que nascer na MESMA coluna do editor -- comparado contra o widget, e
    -- nao contra a constante, senao o check compara o numero consigo mesmo.
    local _, ed = ns.UI.DebugProgress()
    local painelX = painel:PointOffset("TOPLEFT")
    local editorX = ed.spec:PointOffset("TOPLEFT")
    check("o painel nasce na coluna do editor", painelX, editorX)

    -- E NAO INVADE A FAIXA DE AVISOS. E a colisao VERTICAL, que e exatamente a que a skill diz
    -- ter escapado tres vezes por o probe guardar so `x` e `width`.
    local _, painelY = painel:PointOffset("TOPLEFT")
    local _, avisosY = ns.UI.DebugToggles():PointOffset("TOPLEFT")
    local alturaCheia = m.row * 4 + m.titleGap + 16
    check("com as quatro etapas ele ainda para antes dos Avisos",
        -painelY + alturaCheia <= -avisosY, true)

    -- TODO ATLAS CITADO EXISTE. `SetAtlas` falha em silencio, entao um nome errado nao daria erro
    -- nenhum -- so um retangulo vazio no lugar do visto.
    -- ⚑ ORDEM FIXA, e nao a de `pairs`. Ela varia entre EXECUCOES no LuaJIT, e com ela variava a
    -- ordem destas linhas na saida. Os checks passam de qualquer jeito -- mas o `sabotar.py` casa a
    -- saida por TEXTO para decidir qual check reprovou primeiro, e saida que muda de ordem sem o
    -- codigo mudar torna a suite de sabotagem irrepetivel. Suite instavel nao distingue "o teste
    -- nao pega" de "deu azar agora". (Mesmo defeito achado no RocketMeter em 10/09/2026.)
    local estados = {}
    for estado in pairs(m.states) do estados[#estados + 1] = estado end
    table.sort(estados)

    for _, estado in ipairs(estados) do
        local visual = m.states[estado]
        if visual.atlas then
            check("o atlas de " .. estado .. " existe",
                ns.SetAtlasSafe(painel.rows[1].icon, visual.atlas), true)
        end
    end

    -- E A CONFERENCIA CONFERE MESMO: nome inventado tem que reprovar. Sem este check, um
    -- `SetAtlasSafe` que devolvesse `true` sempre passaria nos tres de cima.
    check("atlas inventado reprova",
        ns.SetAtlasSafe(painel.rows[1].icon, "nao-existe-este-atlas"), false)
end

print("== janela: o resto do ciclo ==")
for _, step in ipairs({
    { "UI.Refresh", function() ns.UI.Refresh() end },
    { "UI.RefreshEditor", function() ns.UI.RefreshEditor() end },
    { "UI.AfterEdit", function() ns.UI.AfterEdit() end },
    { "UI.SaveName", function() ns.UI.SaveName() end },
    { "UI.Toggle (fechar)", function() ns.UI.Toggle() end },
}) do
    local ok, err = pcall(step[2])
    print(ok and ("  ok    " .. step[1]) or ("  ERRO  " .. step[1] .. ": " .. tostring(err)))
    if not ok then os.exit(1) end
end



print("== localizacao: rotulos que vem do jogo ==")
-- Mesmo bloco do RocketMeter (padronizado em 05/09/2026). `FROM_GAME` troca nossos rotulos
-- pelas palavras que o CLIENTE ja traduziu. A guarda de tipo e a que nao pode ser removida:
-- sem ela, `text:find` recebe `nil` e levanta erro NA CARGA — e como e aqui que `ns.L` nasce,
-- o addon inteiro morre junto.
--
-- Roda em namespace proprio, carregando so o enUS.lua: num cliente pt-BR o ptBR.lua sobrescreve
-- as chaves, entao pelo `L` de verdade este caminho e invisivel.
do
    local saved, touched = {}, {}
    local function setglobal(name, value)
        if not touched[name] then
            saved[name], touched[name] = _G[name], true
        end
        _G[name] = value
    end

    setglobal("SPECIALIZATION", "Spezialisierung")   -- 1. global limpa
    setglobal("TALENTS", nil)                        -- 2. nao existe neste cliente
    setglobal("APPEARANCE_LABEL", "%d. %s")          -- 3. modelo de frase, nao rotulo
    setglobal("DELETE", "")                          -- 4. existe mas esta vazia

    local probe = {}
    assert(loadfile("Locales/enUS.lua"))(ADDON, probe)
    local PL = probe.L

    check("global limpa vira o rotulo", PL["Specialization"], "Spezialisierung")
    check("global ausente cai no ingles, nao em nil", PL["Talents"], "Talents")
    check("global com marcador de formato e recusada", PL["Appearance"], "Appearance")
    check("global vazia e recusada", PL["Delete"], "Delete")

    local why = {}
    for _, row in ipairs(probe.CheckGameStrings()) do
        why[row.tag] = row.why or false
    end
    check("ausente entra no relatorio", why["TALENTS"], "ausente")
    check("com formato entra no relatorio", why["APPEARANCE_LABEL"], "modelo de frase")
    check("vazia entra no relatorio", why["DELETE"], "vazia")
    check("limpa NAO entra no relatorio", why["SPECIALIZATION"], false)

    -- Conferir nao pode ESCREVER: o `/rs i18n` roda muito depois da carga, e reaplicar ali
    -- apagaria o que o ptBR.lua sobrescreveu. A isca e a SPECIALIZATION acima, que esta
    -- valida de proposito -- sem uma global valida, a sabotagem nao teria o que sobrescrever.
    local antes = ns.L["Specialization"]
    ns.CheckGameStrings()
    check("conferir NAO reaplica por cima da traducao", ns.L["Specialization"], antes)

    -- Chave de FROM_GAME que o codigo nao usa e peso morto que ninguem descobre sozinho.
    local usedKeys = {}
    for _, file in ipairs(files) do
        local fh = io.open(file)
        for key in fh:read("*a"):gmatch('L%[%s*"([^"]*)"%s*%]') do
            usedKeys[key] = true
        end
        fh:close()
    end
    local orphan = false
    for key in pairs(probe.FROM_GAME) do
        if not usedKeys[key] then
            orphan = key
        end
    end
    check("nenhuma chave de FROM_GAME esta morta", orphan, false)

    for name in pairs(touched) do
        _G[name] = saved[name]
    end
end

--------------------------------------------------------------------------------
-- (!) O CAST DUPLO (defeito relatado em 21/09, diagnosticado no diario do usuario)
--
-- O botao Carregar troca a aparencia por acao segura NO CLIQUE, e isso conjura a magia
-- 1247613. O jogo nao deixa comecar outra conjuracao com uma em voo, entao a primeira
-- `SetSpecialization` era recusada em 10 de 10 trocas gravadas -- e o jogador via duas barras
-- de conjuracao com quatro segundos de nada entre elas.
--
-- O passo de spec agora ESPERA a conjuracao sair do caminho antes de pedir. Este teste trava
-- as duas metades: nao pedir enquanto conjura, e pedir UMA vez quando ela para.
--------------------------------------------------------------------------------
do
    print("")
    print("-- cast em voo: o passo de spec espera em vez de pedir e ser recusado")

    local pedidos = 0
    local realSet = C_SpecializationInfo.SetSpecialization
    C_SpecializationInfo.SetSpecialization = function(i)
        pedidos = pedidos + 1
        return realSet(i)
    end

    state.specIndex = 1
    state.refuseSpec = false
    state.casting = 1247613          -- a conjuracao de aparencia, como no clique real

    ns.Data.Apply({ name = "Frost PvP", spec = 2 }, function() end, true)
    check("com conjuracao em voo, nao pede a troca", pedidos, 0)

    AdvanceClock(0.25); RunTimers(0.25)
    check("enquanto conjura, continua sem pedir", pedidos, 0)

    state.casting = nil
    AdvanceClock(0.25); RunTimers(0.25)
    check("quando a conjuracao acaba, pede uma vez", pedidos, 1)

    -- Esperar conjuracao NAO pode consumir tentativa de insistencia: sao coisas diferentes,
    -- e gastar tentativa aqui encurtaria o orcamento de quem realmente precisa dele.
    local _, info = ns.Data.GetProgress()
    check("esperar conjuracao nao gasta tentativa", info and info.tries or 0, 0)

    C_SpecializationInfo.SetSpecialization = realSet
    state.casting = nil
end

--------------------------------------------------------------------------------
-- O PAINEL FLUTUANTE DA TROCA
--
-- Ele nao tem dado proprio: le `Data.GetProgress()`, o mesmo da janela. O que este teste trava
-- e o que so existe nele -- a barra, que anda POR PASSO e nao por tempo, e o sumico automatico.
--------------------------------------------------------------------------------
do
    print("")
    print("-- painel flutuante de progresso")

    -- ENCERRA O QUE FICOU DE PE. O `Apply` recusa comecar com troca em curso, e sem esta
    -- limpeza o teste abaixo leria o progresso da troca ANTERIOR achando que era a dele.
    for _ = 1, 40 do
        if not ns.Data.IsApplying() then break end
        AdvanceClock(60); RunTimers(999)
    end
    check("a troca anterior encerrou antes deste teste", ns.Data.IsApplying(), false)

    state.specIndex = 1
    state.refuseSpec = false
    state.casting = nil

    ns.Data.Apply({ name = "Frost PvP", spec = 2, talent = 10, gear = 3, transmog = 71 },
        function() end, true)

    local painel = ns.Progress.Frame()
    check("o painel abre quando a troca comeca", painel ~= nil and painel:IsShown(), true)

    -- A barra com tudo pendente nao pode ja estar cheia -- nem vazia de largura zero, que some
    -- a textura e o jogo reclama.
    local largura = painel.trilho.fill:GetWidth()
    check("a barra comeca praticamente vazia", largura <= 2, true)

    -- Quatro passos: cada um fechado vale um quarto. Isto e o que torna a barra honesta -- ela
    -- afirma quantos passos fecharam, nao quanto tempo falta, que ninguem sabe.
    local passos = ns.Data.GetProgress()
    check("o conjunto pede quatro passos", #passos, 4)

    -- A CONTA DA BARRA. Ela anda por PASSO FECHADO, nunca por tempo: a corrente nao sabe
    -- quanto vai demorar (o diario real mostrou a mesma troca aceita ora em 4, ora em 14
    -- segundos), e barra que corre contra um relogio inventado trava no meio e mente.
    local function lista(...)
        local out = {}
        for i, estado in ipairs({ ... }) do out[i] = { key = "k" .. i, state = estado } end
        return out
    end

    check("tudo pendente: barra vazia",
        ns.Progress.DebugBarFill(lista("pending", "pending", "pending", "pending")), 0)
    check("dois de quatro fechados: metade",
        ns.Progress.DebugBarFill(lista("done", "done", "doing", "pending")), 0.5)
    -- Pulado NAO e falha, mas e passo FECHADO: ele nao pode segurar a barra.
    check("pulado conta como fechado",
        ns.Progress.DebugBarFill(lista("skipped", "skipped", "pending", "pending")), 0.5)
    check("falhado tambem fecha a fatia",
        ns.Progress.DebugBarFill(lista("failed", "done", "done", "done")), 1)
    check("nenhum passo: barra vazia, sem dividir por zero",
        ns.Progress.DebugBarFill(lista()), 0)

    -- O GRITO DE VITORIA nos tres segundos finais. Troca o conteudo do painel inteiro: naquele
    -- ponto a lista de passos ja cumpriu o papel dela, e o que falta dizer e uma coisa so.
    for _ = 1, 40 do
        if not ns.Data.IsApplying() then break end
        AdvanceClock(60); RunTimers(999)
    end
    TickUI(0.2)

    -- Uma troca que TERMINA BEM, para o grito ter caminho. So itens: o jogo confirma com o
    -- evento, a corrente fecha, e a comemoracao e o desfecho correto.
    state.equippedSet = 9
    ns.Data.Apply({ name = "So itens", gear = 4 }, function() end, true)
    TickUI(0.2)
    local alturaDurante = painel:GetHeight()
    fire("EQUIPMENT_SWAP_FINISHED", true, 4)
    TickUI(0.2)

    -- A ALTURA NAO MUDA NO DESFECHO. Encolher faz o painel pular na tela bem no instante em que
    -- o olho volta para ele, e salto de layout se le como defeito, nao como fim.
    check("a janela nao muda de tamanho no fim", painel:GetHeight(), alturaDurante)

    check("troca bem-sucedida: o grito aparece", painel.shout:IsShown(), true)
    check("e diz o que o usuario pediu", painel.shout:GetText(), ns.Progress.DebugShout())
    -- UMA CARA DE CADA VEZ: sobrepor o grito as linhas de passo deixaria os dois ilegiveis.
    -- A BARRA FICA. Ela e a unica coisa da tela de progresso que ainda diz algo depois do fim.
    check("a barra continua na tela", painel.trilho:IsShown(), true)
    check("e cheia", painel.trilho.fill:GetWidth(), painel.trilho:GetWidth())
    local r, g, b = painel.trilho.fill:GetVertexColor()
    check("e verde, nao mais dourada", g > r and g > b, true)

    check("o titulo sai da frente", painel.title:IsShown(), false)
    -- SO A FRASE. "Trocando para X" ao lado dela estaria no tempo errado: nessa altura ja
    -- trocou, e o painel anunciaria como presente o que acabou de virar passado.
    check("e nada mais sobra na tela", painel.done, nil)
    check("nem o relogio", painel.clock:IsShown(), false)
    -- A frase pode ocupar duas linhas: na largura do painel ela nao cabe inteira, e encolher a
    -- fonte para forcar uma linha so tiraria dela o tamanho, que e o recado.
    check("a frase pode quebrar em duas linhas", painel.shout.__wordWrap, true)

    -- E ele nao fica para sempre: os tres segundos passam e o painel some.
    AdvanceClock(4)
    TickUI(0.2)
    check("passados os tres segundos, o painel some", painel:IsShown(), false)

    local venceu = true
    for _, p in ipairs(ns.Data.GetProgress() or {}) do
        if p.state == "failed" then venceu = false end
    end

    -- E A OUTRA METADE, que importa mais: falha NAO comemora. O painel tem que continuar
    -- mostrando qual passo nao deu, e sem prazo para sumir.
    ns.Data.Apply({ name = "Vai falhar", spec = 2, talent = 10, gear = 3, transmog = 71 },
        function() end, true)
    for _ = 1, 40 do
        if not ns.Data.IsApplying() then break end
        AdvanceClock(60); RunTimers(999)
    end
    TickUI(0.2)

    local falhou = false
    for _, p in ipairs(ns.Data.GetProgress() or {}) do
        if p.state == "failed" then falhou = true end
    end
    check("o cenario de falha realmente falhou", falhou, true)
    check("falhou: nao comemora", painel.shout:IsShown(), false)
    -- A lista de passos, e nao a barra: a barra fica na tela nos dois desfechos agora.
    check("e a lista de passos continua a vista", painel.rows[1]:IsShown(), true)

    AdvanceClock(10)
    TickUI(0.2)
    check("e falha nao tem prazo para sumir", painel:IsShown(), true)
end


--------------------------------------------------------------------------------
-- (!) CONJUNTO DE ITENS COM PECA PERDIDA (defeito relatado em 22/09)
--
-- O jogador trocou uma peca e vendeu a anterior sem salvar o conjunto. O jogo poe o nome do
-- conjunto em vermelho; o addon trocava assim mesmo, e o passo nunca fechava com o "V" --
-- porque com peca perdida o `isEquipped` do jogo nunca fica true. A roupa mudava e a tela
-- dizia que nao. Decisao do usuario: NAO TROCAR, avisar e mandar consertar primeiro.
--------------------------------------------------------------------------------
do
    print("")
    print("-- conjunto com peca perdida: recusa antes de comecar")

    for _ = 1, 40 do
        if not ns.Data.IsApplying() then break end
        AdvanceClock(60); RunTimers(999)
    end

    state.equippedSet = 9
    state.lostItems = 2
    state.wornPieces = { [3] = 12 }      -- 12 vestidas + 2 perdidas = 14: da para consertar

    local erroRecusa
    local comecou = ns.Data.Apply({ name = "Tank", spec = nil, talent = nil, gear = 3 },
        function(text, isError) if isError then erroRecusa = text end end, true)

    check("a troca NAO comeca", comecou, false)
    check("e nem fica corrente em curso", ns.Data.IsApplying(), false)
    check("o aviso diz quantas pecas faltam",
        erroRecusa ~= nil and erroRecusa:find("2", 1, true) ~= nil, true)

    -- O diagnostico separa "da para consertar" de "nao da", e e ele que decide se o addon
    -- pode salvar por cima: salvar grava a roupa ATUAL no conjunto, entao so e conserto
    -- quando voce ja esta vestindo o conjunto inteiro menos o que sumiu.
    local problema = ns.Data.GearSetProblem(3)
    check("o diagnostico acha o problema", problema ~= nil, true)
    check("  e conta as pecas", problema.perdidas, 2)
    check("  e diz que da para consertar", problema.consertavel, true)

    -- VESTINDO OUTRA COISA: salvar destruiria o conjunto. O diagnostico tem que dizer NAO.
    state.wornPieces = { [3] = 1 }
    local outro = ns.Data.GearSetProblem(3)
    check("vestindo outra coisa, NAO se oferece para salvar", outro.consertavel, false)

    -- O BOTAO MUDA DE PAPEL. Com peca perdida, "Carregar" e recusado de qualquer jeito, entao
    -- deixar esse rotulo ali seria oferecer uma acao que nao acontece.
    state.wornPieces = { [3] = 12 }     -- de volta ao caso consertavel
    local quebrado = { name = "Tank", gear = 3 }
    check("com peca perdida o botao vira 'salvar'", ns.Data.GearFixAction(quebrado), "save")

    -- Sem poder salvar com seguranca, ele leva ao Gerenciador em vez de agir sozinho: salvar
    -- vestindo outra coisa gravaria a roupa errada por cima do conjunto.
    state.wornPieces = { [3] = 1 }
    check("vestindo outra coisa, leva ao gerenciador", ns.Data.GearFixAction(quebrado), "manager")
    state.wornPieces = { [3] = 12 }

    -- E O BOTAO CARREGAR FICA APAGADO. Pedido literal do usuario: *"se tiver com erro de
    -- equipamentos, o botao de carregar fica indisponivel para trocar"*. E a mesma regra que ele
    -- ja tinha dado para a restricao de spec: botao que aceita clique e depois responde "nao
    -- deu" e pior que botao apagado.
    check("com peca perdida, Carregar fica bloqueado",
        ns.Data.LoadBlockedReason(quebrado) ~= nil, true)
    check("  e o motivo diz quantas pecas faltam",
        ns.Data.LoadBlockedReason(quebrado):find("2", 1, true) ~= nil, true)

    -- Conjunto sao: o botao continua sendo o de carregar.
    state.lostItems = 0
    check("conjunto inteiro nao muda o botao", ns.Data.GearFixAction(quebrado), nil)
    check("e com o conjunto inteiro, Carregar volta", ns.Data.LoadBlockedReason(quebrado), nil)
    state.lostItems = 2

    -- Conjunto inteiro: nenhum problema, nenhuma recusa.
    state.lostItems = 0
    state.wornPieces = nil
    check("conjunto inteiro nao tem problema", ns.Data.GearSetProblem(3), nil)

    for _ = 1, 40 do
        if not ns.Data.IsApplying() then break end
        AdvanceClock(60); RunTimers(999)
    end
end


--------------------------------------------------------------------------------
-- O CARD DA LISTA: a altura acompanha os campos que o conjunto define
--
-- Geometria e aritmetica e se confere em disco. Reservar quatro linhas sempre deixaria tres
-- vazias num conjunto so de itens, e espaco guardado para conteudo que nao existe e o que mais
-- faz uma janela parecer quebrada.
--------------------------------------------------------------------------------
do
    print("")
    print("-- card da lista: altura por conteudo")

    local m = ns.UI.DebugCardMetrics()
    -- A "base" do card: o titulo com os respiros, ate onde o bloco de campos comeca. O icone
    -- fica AO LADO do bloco, entao ele nao soma altura -- mas e o PISO dela.
    local base = m.top + m.pad

    state.lostItems = 0
    state.wornPieces = nil

    local soItens = { name = "So itens", gear = 3 }
    local tudo = { name = "Tudo", spec = 2, talent = 10, gear = 3, transmog = 71 }

    -- (!) O BLOCO DE CAMPOS COMECA ABAIXO DO TITULO, e isto nao pode sair de `m.top` sozinho:
    -- `base` e derivado dele, entao um `CARD_TOP` errado passaria nos dois lados da conta. A
    -- invariante e outra -- tem que caber o respiro MAIS a tinta do titulo antes do primeiro
    -- campo, senao o titulo e a primeira linha se sobrepoem.
    check("os campos comecam abaixo do titulo", m.top >= m.pad + m.name, true)

    -- E O ICONE ENCOSTA NO TITULO: ancorado no TOPO do bloco de campos, nao no meio dele. Ja
    -- esteve centralizado, e com quatro campos isso o empurrava 14 px para baixo, boiando ao
    -- lado da segunda linha.
    if not ns.UI.IsShown() then ns.UI.Toggle() end
    ns.UI.Refresh()
    TickUI(0.2)
    local linha = ns.UI.DebugLastRow()
    check("o harness alcanca uma linha de verdade", linha ~= nil, true)
    if linha then
        local xIcone, yIcone = linha.icon:PointOffset("TOPLEFT")
        local _, yNome = linha.name:PointOffset("TOPLEFT")
        check("o icone encosta no titulo", -yIcone, m.top)
        check("  ou seja, logo abaixo dele", -yIcone > -yNome, true)

        -- (!) O ICONE PREENCHE O BLOCO DE CAMPOS: com quatro linhas ele mede as quatro. Antes
        -- eram 32 fixos e sobrava um vazio embaixo dele.
        -- O NUMERO DE CAMPOS VEM DA LINHA, e nao de um 4 cravado: o conjunto desta fixture
        -- pode ter tres, e um literal aqui faria o teste reprovar a verdade.
        local campos = 0
        for _, fs in ipairs(linha.lines) do
            if fs:IsShown() then campos = campos + 1 end
        end
        check("a linha tem campos para medir", campos > 0, true)
        check("o icone tem a altura do bloco de campos",
            linha.icon:GetHeight(), math.max(m.line * campos, m.icon))
        check("  e e quadrado", linha.icon:GetWidth(), linha.icon:GetHeight())

        -- E O RECUO DO TEXTO NAO ACOMPANHA O ICONE: se acompanhasse, cards com numeros de
        -- campos diferentes comecariam o texto em X diferentes, e o alinhamento ENTRE cards e o
        -- que faz uma lista parecer uma lista.
        local xCampo = linha.lines[1]:PointOffset("TOPLEFT")
        check("o texto comeca no recuo fixo", xCampo, m.left)
        check("  que cabe o maior icone", m.left >= m.iconX + m.iconMax, true)
        -- (!) A CENTRALIZACAO SE AFIRMA COM IGUALDADE, e nao com `>=`. A primeira versao deste
        -- check aceitava qualquer x a direita da margem -- inclusive o icone colado nela, que e
        -- justamente o defeito que ele deveria pegar. A sabotagem denunciou.
        local esperado = m.iconX + math.floor((m.iconMax - linha.icon:GetHeight()) / 2)
        check("  e o icone menor se centraliza nessa coluna", xIcone, esperado)
    end

    -- COM UM CAMPO SO, QUEM MANDA E O ICONE: uma linha mede 15 e o icone 32, e sem esse piso
    -- ele vazaria o card por baixo.
    check("um campo: o icone e o piso da altura", ns.UI.DebugCardHeight(soItens), base + m.icon)
    check("quatro campos: as linhas passam o icone",
        ns.UI.DebugCardHeight(tudo), base + m.line * 4)

    -- E O TEXTO NAO PODE TRANSBORDAR A LINHA: o teto e derivado da largura da lista justamente
    -- para isso, e um teto escolhido a olho maior que a lista nao encurtaria nada -- so deixaria
    -- o texto sair pela borda, que e pior que a linha comprida.
    check("o texto cabe na largura da lista", m.left + m.textW <= m.listW - 14, true)
    check("e o card de quatro e mais alto que o de uma",
        ns.UI.DebugCardHeight(tudo) > ns.UI.DebugCardHeight(soItens), true)

    -- A faixa do aviso ocupa lugar: sem somar a altura dela, ela sairia POR CIMA da ultima
    -- linha do card, que e exatamente o tipo de colisao vertical que a skill manda travar.
    state.lostItems = 2
    state.wornPieces = { [3] = 12 }
    check("com peca perdida o card cresce a faixa do aviso",
        ns.UI.DebugCardHeight(soItens), base + m.icon + m.warn)
    check("  e a faixa cabe onde foi reservada", m.warn >= 22, true)

    -- TRES CARDS INTEIROS CABEM SEM ROLAR. Pedido do usuario, e e o unico numero da janela que
    -- ele enxerga: "quantos conjuntos vejo de uma vez".
    --
    -- (!) O inset da lista tinha altura FIXA e nao acompanhava a janela -- aumentar `HEIGHT` na
    -- rodada anterior nao deu um pixel a mais de lista. Agora a lista manda na janela, e este
    -- teste e que garante que continue assim: mexer no card sem mexer na janela reprova.
    -- (!) O NUMERO E LITERAL, e nao `m.visiveis`. A primeira versao comparava a constante com
    -- ela mesma: baixar CARDS_VISIVEIS para 2 mudava os DOIS lados e o teste continuava verde.
    -- Teste tautologico nao afirma nada -- ele so repete a implementacao com outras palavras.
    --
    -- E a altura conferida e a REAL do inset (`listTop` - `listBottom`), nao a variavel que a
    -- calculou: e o inset que o jogador ve, e foi um inset de altura fixa que causou o problema.
    local alturaReal = m.listTop - m.listBottom
    local cabem = math.floor((alturaReal - 6 + m.spacing) / (m.cardMax + m.spacing))
    check("cabem TRES cards inteiros na lista", cabem >= 3, true)
    check("  e nao muito mais que tres (janela nao incha a toa)", cabem <= 4, true)
    -- A conta e feita sobre o card de quatro campos SEM aviso, e isso e escolha: com aviso ele
    -- mede 116, e dimensionar por ele deixaria a janela 72 px mais alta para todo mundo por
    -- causa de um estado que e erro e e para durar pouco.
    state.lostItems = 0
    check("  e a conta usa o card de quatro campos",
        m.cardMax, ns.UI.DebugCardHeight(tudo))
    state.lostItems = 2
    check("  o card com aviso e maior, e por isso rola",
        ns.UI.DebugCardHeight(tudo) > m.cardMax, true)
    check("  e a faixa de avisos comeca ABAIXO do inset", m.stripY < m.listBottom, true)
    -- (!) A CONTA USA AS CONSTANTES, e nao os numeros que elas valiam quando o teste nasceu.
    -- A faixa de avisos ja mediu 86, 118, 142 e agora 106; um literal aqui viraria falso a cada
    -- vez que ela mudasse, e o teste passaria a reprovar a verdade em vez do defeito.
    check("  e a janela cabe tudo isso", m.height >= -m.stripY + m.stripH + m.footer, true)

    -- (!) E UM TETO, que ate agora nao existia. Desde que a janela passou a ser DERIVADA do card,
    -- qualquer folga a mais no card empurra a janela junto -- e ninguem percebe lendo o diff.
    -- Dobrar o icone, por exemplo, levaria a janela a 690 e ela sairia da tela de quem joga em
    -- 1280x720 com escala padrao (768 de altura util, menos a barra de acao).
    --
    -- 640 e o limite pratico: o Guia de Aventuras da Blizzard, que e das janelas mais altas do
    -- jogo, mede 638.
    check("  e a janela nao passa do teto de tela pequena", m.height <= 640, true)

    -- (!) E UM TETO DE LARGURA TAMBEM. A altura ja tinha o dela desde 0.34.1; a largura nao, e
    -- ela ja subiu duas vezes num dia (520 -> 620 -> 680). O criterio e o mesmo: caber em quem
    -- joga em 1280x720 com escala padrao, onde sobram cerca de 1024 de largura util. 760 deixa
    -- margem para a janela nao nascer colada nas bordas.
    check("  nem do teto de largura", m.width <= 760, true)

    -- E A COLUNA DA DIREITA NAO PODE SER ESPREMIDA pelo crescimento da lista: o ganho de largura
    -- vai todo para a lista, mas se `COL_X` nao andar junto com `WIDTH` a coluna do editor
    -- encolhe em silencio e os combos de 200 px comecam a vazar pela borda.
    check("  e a coluna do editor continua cabendo os combos",
        m.width - m.colX - 20 >= 200, true)

    state.lostItems = 0
    state.wornPieces = nil
end


--------------------------------------------------------------------------------
-- AVISO DE EQUIPAMENTO: UMA CHAVE POR CONTEUDO (0.35.0)
--
-- Era uma chave so para PvE e PvP. Quem faz mitica+ toda noite e PvP de vez em quando queria o
-- aviso ligado num e calado no outro, e tinha que escolher os dois juntos.
--------------------------------------------------------------------------------
do
    print("")
    print("-- aviso de equipamento por conteudo")

    ns.db.warnPvE, ns.db.warnPvP = true, false
    ns.Gear.ClearCache()

    state.instance = "arena"
    VestirTudo(false)
    ns.Alert.Check("teste")
    check("PvP desligado cala em arena", ns.Alert.__Shown(), false)

    state.instance = "party"
    ns.Gear.ClearCache()
    VestirTudo(true)
    ns.Alert.Check("teste")
    check("e PvE ligado continua avisando em masmorra", ns.Alert.__Shown(), true)

    -- E O INVERSO, que e o que prova que as duas chaves sao mesmo independentes.
    ns.Alert.Hide()
    ns.db.warnPvE, ns.db.warnPvP = false, true
    ns.Gear.ClearCache()
    ns.Alert.Check("teste")
    check("PvE desligado cala em masmorra", ns.Alert.__Shown(), false)

    state.instance = "arena"
    ns.Gear.ClearCache()
    VestirTudo(false)
    ns.Alert.Check("teste")
    check("e PvP ligado continua avisando em arena", ns.Alert.__Shown(), true)

    -- A MIGRACAO: quem tinha DESLIGADO o aviso antigo nao pode ver ele voltar sozinho.
    RocketSwapDB.warn = false
    RocketSwapDB.warnPvE, RocketSwapDB.warnPvP = nil, nil
    ns.frame.__scripts.OnEvent(ns.frame, "ADDON_LOADED", "RocketSwap")
    check("a migracao herda o desligado das duas", RocketSwapDB.warnPvE, false)
    check("  nas duas mesmo", RocketSwapDB.warnPvP, false)
    check("  e a chave velha some", RocketSwapDB.warn, nil)

    ns.db.warnPvE, ns.db.warnPvP = true, true
    ns.Alert.Hide()
end


--------------------------------------------------------------------------------
-- O PACOTE NAO LEVA O DIARIO (23/09). Regra do usuario: *"quando forem publicados nao devem gerar
-- os logs"*. As regras do empacotador aplicadas ao .toc (README do BigWigsMods/packager, "In TOC
-- files"): o bloco `#@debug@` sai inteiro; do `#@non-debug@` sai o "# " de cada linha.
--------------------------------------------------------------------------------
do
    print("\n== o diario so existe em desenvolvimento ==")
    check("em desenvolvimento o diario e o de verdade", ns.Log.enabled, true)

    local pacote, dentroDebug, dentroNon = {}, false, false
    for linha in io.lines(ADDON .. ".toc") do
        linha = linha:gsub("%s+$", "")
        if linha == "#@debug@" then dentroDebug = true
        elseif linha == "#@end-debug@" then dentroDebug = false
        elseif linha == "#@non-debug@" then dentroNon = true
        elseif linha == "#@end-non-debug@" then dentroNon = false
        elseif not dentroDebug then
            pacote[#pacote + 1] = dentroNon and linha:gsub("^# ", "") or linha
        end
    end
    local temLog, declaraLog = false, false
    for _, linha in ipairs(pacote) do
        if linha:match("Log%.lua$") then temLog = true end
        if linha:match("^## SavedVariables") and linha:find("LogDB", 1, true) then declaraLog = true end
    end
    check("o .toc empacotado nao carrega Log.lua", temLog, false)
    check("  nem declara o RocketSwapLogDB", declaraLog, false)
    local pkg = io.open(".pkgmeta"):read("*a")
    check("  e o .pkgmeta nem poe o Log.lua no zip", pkg:find("%- Log%.lua") ~= nil, true)

    -- Sem o Log.lua: o substituto engole tudo e nenhum banco de diario nasce.
    local real = ns.Log
    ns.Log = setmetatable({ enabled = false }, { __index = function() return function() end end })
    RocketSwapLogDB = nil
    local ok1 = pcall(ns.Log.Add, "teste", { a = 1 })
    local ok2 = pcall(ns.Log.Call, "passo", "chamada", true)
    local ok3 = pcall(SlashCmdList.ROCKETSWAP, "log")
    check("sem o diario, as chamadas a ele nao quebram", ok1 and ok2, true)
    check("  e /rs log so explica que e de desenvolvimento", ok3, true)
    check("  e nenhum banco de diario e criado", RocketSwapLogDB, nil)
    ns.Log = real
end

print("\nTudo carregou e rodou sem erro de Lua.")
