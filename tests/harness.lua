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

    function self.SetScript(_, name, fn) self.__scripts[name] = fn end
    function self.GetScript(_, name) return self.__scripts[name] end
    function self.RegisterEvent(_, event) self.__events[event] = true end
    function self.CreateFontString(_, _, template)
        local fs = widget("FontString")
        fs.__hasFont = template ~= nil
        function fs.SetFont() fs.__hasFont = true end
        function fs.SetText(_, ...)
            if not fs.__hasFont then error("FontString:SetText(): Font not set", 2) end
            return ...
        end
        function fs.HasFocus() return false end
        return fs
    end
    function self.CreateTexture() return widget("Texture") end
    function self.GetName() return ADDON .. kind end
    function self.GetPoint() return "CENTER", nil, "CENTER", 0, 0 end
    function self.IsShown() return self.__shown == true end
    function self.SetShown(_, v) self.__shown = v end
    function self.Show() self.__shown = true end
    function self.Hide() self.__shown = false end
    function self.GetWidth() return 280 end
    function self.GetHeight() return 400 end
    function self.GetEffectiveScale() return 1 end
    function self.GetCenter() return 400, 300 end
    function self.GetFrameLevel() return 1 end
    function self.GetHighlightTexture() return widget("Texture") end
    function self.GetNormalTexture() return widget("Texture") end
    function self.GetText() return self.__text or "" end
    function self.SetText(_, t) self.__text = t end
    function self.HasFocus() return false end

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
GameTooltip = widget("GameTooltip")
UISpecialFrames = {}
SlashCmdList = {}
unpack = unpack or table.unpack
format = string.format

function GameTooltip_Hide() end
function GetLocale() return "ptBR" end
function GetCursorPosition() return 400, 300 end
function CopyTable(t)
    local out = {}
    for k, v in pairs(t) do out[k] = type(v) == "table" and CopyTable(v) or v end
    return out
end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function tinsert(t, v) t[#t + 1] = v end
function UnitCastingInfo() return nil end
-- Resolve caminho de textura em FileID, ou nil se nao existir. E como o addon evita icone
-- fantasma: aqui so o ultimo candidato "existe", para o fallback ser exercitado.
function GetFileIDFromPath(path)
    return path:find("MissileLarge_Red", 1, true) and 12345 or nil
end

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
    function view.SetPadding() end
    function view.SetElementInitializer(_, _, fn) view.__init = fn end
    return view
end

ScrollUtil = {
    InitScrollBoxListWithScrollBar = function(list, _, view)
        list.__view = view
        list.__rows = {}
        function list.SetDataProvider(_, provider)
            list.__rows = {}
            for i, data in ipairs(provider.__items or {}) do
                local row = CreateFrame("Button", nil, list)
                row.GetElementData = function() return data end
                list.__rows[i] = row
                if view.__init then view.__init(row, data) end
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
    specIndex = 2,               -- Gelido
    equippedSet = 1,             -- Frost
    outfit = 71,                 -- aparencia ativa
    activeLoadout = { [251] = 11, [252] = nil, [250] = nil },
}

function InCombatLockdown() return state.inCombat end

local SPECS = {
    { index = 1, id = 250, name = "Sangue",  icon = 1 },
    { index = 2, id = 251, name = "Gelido",  icon = 2 },
    { index = 3, id = 252, name = "Profano", icon = 3 },
}

C_SpecializationInfo = {
    GetNumSpecializations = function() return #SPECS end,
    GetSpecialization = function() return state.specIndex end,
    GetSpecializationInfo = function(i)
        local s = SPECS[i]
        if not s then return nil end
        return s.id, s.name, "desc", s.icon
    end,
    SetSpecialization = function(i)
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
    UpdateLastSelectedSavedConfigID = function(specID, configID)
        state.activeLoadout[specID] = configID
    end,
    LoadConfig = function(configID)
        state.pendingLoadout = configID
        return 2                 -- LoadInProgress: confirma por evento
    end,
}

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

C_EquipmentSet = {
    GetEquipmentSetIDs = function()
        local out = {}
        for _, s in ipairs(SETS) do out[#out + 1] = s.setID end
        return out
    end,
    GetEquipmentSetInfo = function(setID)
        for _, s in ipairs(SETS) do
            if s.setID == setID then
                return s.name, s.icon, setID, state.equippedSet == setID
            end
        end
        return nil
    end,
    EquipmentSetContainsLockedItems = function() return state.locked == true end,
    UseEquipmentSet = function(setID)
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

C_TransmogOutfitInfo = {
    GetOutfitsInfo = function() return OUTFITS end,
    GetActiveOutfitID = function() return state.outfit end,
    ChangeToOutfit = function(index)
        for _, o in ipairs(OUTFITS) do
            if o.playerFacingOutfitIndex == index then state.pendingOutfit = o.outfitID end
        end
        return true
    end,
}

Enum = { LoadConfigResult = { Error = 0, NoChangesNecessary = 1, LoadInProgress = 2, Ready = 3 } }

-- C_Timer com relogio manual: o teste controla quando o prazo estoura.
local timers = {}
C_Timer = {
    NewTimer = function(seconds, fn)
        local t = { at = seconds, fn = fn, cancelled = false }
        function t.Cancel() t.cancelled = true end
        timers[#timers + 1] = t
        return t
    end,
    After = function(_, fn) fn() end,
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
local function fire(event, ...)
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

local function check(label, got, want)
    local ok = got == want
    print(ok and ("  ok    " .. label .. " = " .. tostring(got))
        or ("  ERRO  " .. label .. ": esperado " .. tostring(want) .. ", veio " .. tostring(got)))
    if not ok then os.exit(1) end
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
fire("TRAIT_CONFIG_UPDATED", 10)
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
fire("TRAIT_CONFIG_UPDATED", 10)
fire("EQUIPMENT_SWAP_FINISHED", false, 4)
check("a falha de equipar foi reportada", erro ~= nil, true)
check("e o addon nao ficou preso aplicando", ns.Data.IsApplying(), false)

print("== peca travada e cast em andamento ==")
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

print("== comandos ==")
for _, cmd in ipairs({ "", "list", "help", "icon", "load Arena", "load nao-existe", "Arena" }) do
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

state.outfit, state.pendingOutfit = 71, nil
local semRoupa = { name = "Sem roupa", spec = 2, talent = nil, gear = 2 }
state.equippedSet = 1
ns.Data.Apply(semRoupa, function() end)
fire("EQUIPMENT_SWAP_FINISHED", true, 2)
check("conjunto sem aparencia nao troca a roupa", state.pendingOutfit, nil)

-- O ID e o INDICE sao diferentes: o conjunto guarda o ID 88, e a troca tem que pedir o
-- indice 2. Guardar o indice apodreceria quando uma aparencia fosse apagada.
state.equippedSet = 1
local comRoupa = { name = "Arena", spec = 2, talent = nil, gear = 2, transmog = 88 }
ns.Data.Apply(comRoupa, function() end)
fire("EQUIPMENT_SWAP_FINISHED", true, 2)
check("pediu a aparencia certa pelo INDICE", state.pendingOutfit, 88)

-- E a aparencia vem depois dos itens: aplicar a roupa antes seria escrever por cima do que o
-- passo de itens ainda vai mudar.
state.equippedSet, state.outfit, state.pendingOutfit, state.pendingSet = 1, 71, nil, nil
ns.Data.Apply({ name = "Arena", spec = 2, gear = 4, transmog = 88 }, function() end)
check("os itens vao primeiro", state.pendingSet, 4)
check("e a roupa ainda nao foi", state.pendingOutfit, nil)
state.equippedSet = 4
fire("EQUIPMENT_SWAP_FINISHED", true, 4)
check("so entao a roupa", state.pendingOutfit, 88)

-- Aparencia apagada entre o salvamento e o uso: tem que avisar, nao vestir outra.
state.outfit, state.pendingOutfit = 71, nil
local erroRoupa
ns.Data.Apply({ name = "Fantasma", spec = 2, transmog = 999 }, function(t, isErr)
    if isErr then erroRoupa = t end
end)
check("aparencia inexistente avisa", erroRoupa ~= nil, true)
check("e nao veste outra", state.pendingOutfit, nil)

print("== janela: estado vazio ==")
-- Reclamacao literal do usuario: "fica tudo vazio quando nao tem nada". Com zero conjuntos a
-- janela mostra UM bloco central, e nada mais — nem lista, nem rotulos orfaos.
ns.db.presets = {}
ns.UI.Toggle()
check("nenhum conjunto selecionado com a lista vazia", ns.UI.Selected(), nil)

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
ns.UI.Toggle()
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


print("\nTudo carregou e rodou sem erro de Lua.")
