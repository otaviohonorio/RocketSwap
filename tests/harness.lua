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
function CreateFrame(frameType, name, parent, template)
    local f = widget(frameType or "Frame")
    f.__name, f.__template = name, template
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

-- Estado simulado do personagem: um Cavaleiro da Morte com os mesmos conjuntos e loadouts
-- do print que o usuario mandou. Frost e PvP sao a MESMA spec — que e o caso que o jogo
-- nao consegue expressar sozinho, e a razao deste addon existir.
local state = {
    inCombat = false,
    specIndex = 2,               -- Gelido
    equippedSet = 1,             -- Frost
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

print("== janela ==")
for _, step in ipairs({
    { "UI.Toggle (abrir)", function() ns.UI.Toggle() end },
    { "UI.New", function() ns.UI.New() end },
    { "UI.Save sem nome", function() ns.UI.Save() end },
    { "UI.Refresh", function() ns.UI.Refresh() end },
    { "UI.Delete", function() ns.UI.Delete() end },
    { "UI.Toggle (fechar)", function() ns.UI.Toggle() end },
}) do
    local ok, err = pcall(step[2])
    print(ok and ("  ok    " .. step[1]) or ("  ERRO  " .. step[1] .. ": " .. tostring(err)))
    if not ok then os.exit(1) end
end

print("\nTudo carregou e rodou sem erro de Lua.")
