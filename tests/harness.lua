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

-- Que peca esta em cada slot, e se ela e de PvP. O teste mexe nisto.
local equipped = {}
local function VestirTudo(ehPvP)
    equipped = {}
    for _, slot in ipairs({ 1,2,3,5,6,7,8,9,10,11,12,13,14,15,16,17 }) do
        equipped[slot] = { link = "item:" .. slot, pvp = ehPvP }
    end
end
VestirTudo(false)

function GetInventoryItemLink(_, slot)
    return equipped[slot] and equipped[slot].link
end

C_TooltipInfo = {
    GetInventoryItem = function(_, slot)
        local item = equipped[slot]
        if not item then return nil end
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

UIErrorsFrame = { AddExternalWarningMessage = function() end }
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
    LoadConfig = function(configID)
        state.pendingLoadout = configID
        return 2, nil, {}        -- LoadInProgress: confirma por evento
    end,
    -- `CanEditTalents` devolve `canEdit, changeError`. Sem ela no simulador, a pre-checagem do
    -- addon era pulada em silencio e o teste nunca via esse caminho.
    CanEditTalents = function() return true, nil end,
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
local fakeNow = 1000
function GetTime() return fakeNow end

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

local realIsSecretBase = issecretvalue
function issecretvalue(v) return v == SECRET or realIsSecretBase(v) end

local realType = type
function type(v)
    if v == SECRET then return "number" end     -- o tipo REAL, como no jogo
    return realType(v)
end

C_Spell = {
    GetSpellCooldown = function()
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
function RunTimers()
    local pendentes = timers
    timers = {}
    for _, t in ipairs(pendentes) do
        if not t.cancelled then t.fn() end
    end
end
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
fire = function(event, ...)
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
    local realSet = C_SpecializationInfo.SetSpecialization
    C_SpecializationInfo.SetSpecialization = function() return false end

    local texto, houveErro
    ns.Data.Apply({ name = "Tank", spec = 1, talent = 11, gear = 3 },
        function(t, isError) texto, houveErro = t, isError end)
    fire("EQUIPMENT_SWAP_FINISHED", true, 3)

    C_SpecializationInfo.SetSpecialization = realSet

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

    -- TALENTOS: o evento carrega `configID`, e a Blizzard avisa por escrito que ele chega mais de
    -- uma vez por gravacao -- o do config base da spec vem ANTES do loadout
    -- (`Blizzard_ClassTalentsFrame.lua:407-411`). Fechavamos no primeiro.
    ns.Data.Apply({ name = "So talento", spec = 2, talent = 11 }, function() end)
    check("o passo de talentos esperou", ns.Data.IsApplying(), true)

    fire("TRAIT_CONFIG_UPDATED", 999)          -- de outro config
    check("evento de OUTRO config nao fecha o passo", ns.Data.IsApplying(), true)

    state.activeLoadout[251] = 11
    fire("TRAIT_CONFIG_UPDATED", state.activeConfigID)
    check("e o do config ativo fecha", ns.Data.IsApplying(), false)

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

print("== comandos ==")
for _, cmd in ipairs({ "", "list", "help", "icon", "i18n", "load Arena", "load nao-existe",
                       "log", "log clear", "transmog", "Arena" }) do
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

print("== a comporta que impede o addon de gritar quando a leitura falha ==")
-- Se TODO slot lido deu errado, e muito mais provavel que a deteccao tenha falhado (idioma
-- cujo padrao nao casa, tooltip nao carregada) do que o jogador estar com 16 pecas erradas.
-- Sem esta comporta, um cliente em coreano veria o addon gritar em toda arena.
VestirTudo(false)
ns.Gear.ClearCache()
local todas, lidos = ns.Gear.Wrong(true)
check("todos errados = leitura suspeita", ns.Gear.LooksReliable(todas, lidos), false)

VestirTudo(true)
equipped[13].pvp = false
ns.Gear.ClearCache()
local uma, lidos2 = ns.Gear.Wrong(true)
check("uma errada entre dezesseis = confiavel", ns.Gear.LooksReliable(uma, lidos2), true)

print("== o aviso so aparece quando ainda da para consertar ==")
VestirTudo(false)
ns.Gear.ClearCache()
state.instance = "arena"
state.inCombat = true
ns.Alert.Check("teste")
check("em combate o aviso cala", ns.Alert.__shown ~= true, true)
state.inCombat = false
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
state.equippedSet = 1

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
    check("e ainda diz que e a conferencia", titulo, ns.L["Ready check"])

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
check("ligados por padrao", ns.db.warn ~= false and ns.db.readyCheck ~= false, true)
check("a faixa existe", ns.UI.DebugToggles() ~= nil, true)
check("e nao e escondida com a lista vazia",
    ns.UI.DebugToggles().__shown ~= false, true)

-- Desmarcar escreve no banco, e o aviso obedece.
local caixa = ns.UI.DebugToggles().warn
caixa.__checked = false
caixa.__scripts.OnClick(caixa)
check("desmarcar desliga o aviso", ns.db.warn, false)

state.instance = "arena"
VestirTudo(false)
ns.Gear.ClearCache()
ns.Alert.Check("teste")
check("e com ele desligado o addon nao avisa", ns.Alert.__shown ~= true, true)

caixa.__checked = true
caixa.__scripts.OnClick(caixa)
check("remarcar religa", ns.db.warn, true)
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

print("\nTudo carregou e rodou sem erro de Lua.")
