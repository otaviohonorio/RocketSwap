-- RocketSwap | Core.lua
-- Namespace do addon: tudo que for compartilhado entre arquivos vai em `ns`.
local ADDON, ns = ...
local L = ns.L

-- A versao vem do .toc, nunca de uma constante aqui: numero em dois lugares vira numero
-- errado em um deles. (Padronizado com o RocketMeter em 05/09/2026.)
ns.version = C_AddOns.GetAddOnMetadata(ADDON, "Version") or "0.0.0"

ns.defaults = {
    presets = {},        -- { { name, spec, talent, gear }, ... }
    last = nil,          -- nome do ultimo conjunto carregado, para o clique direito
    minimap = { angle = 210 },
    pos = nil,

    -- Os dois avisos, ligados por padrao: eles sao o que o addon faz por quem nunca criar
    -- um conjunto. Desligaveis por /rs warn e /rs ready.
    warn = true,          -- equipamento errado para o conteudo
    readyCheck = true,    -- resumo do que voce esta usando, no ready check
    queuePop = true,      -- o mesmo resumo quando a fila de PvP estoura (convite na tela)

    -- ⚑ MODO GUERRA NASCE CALADO (pedido de 12/09: *"tira o alerta dos itens de pvp em mundo
    -- aberto no war mode, ou transforma em opcao por padrao desmarcada"*).
    --
    -- O contexto FICA -- ele existe por pedido dele mesmo, de 08/09 (*"inclusive quando seto para
    -- pvp, habilitando o war mode on, sem avisos"*) --, mas o aviso dele passa a ser opt-in. A
    -- razao esta na diferenca entre as duas situacoes: partida de PvP e uma janela fechada em que
    -- o equipamento errado custa a partida; modo guerra e o mundo aberto, onde a maior parte do
    -- tempo e missao e farm, e o aviso aparece sem que nada esteja acontecendo.
    warnWarMode = false,  -- avisar tambem com Modo Guerra ligado, no mundo aberto
    muted = {},           -- situacoes que o usuario mandou calar
    mutedSlots = {},      -- slots que o usuario mandou calar
}

function ns.Print(...)
    print("|cffffd100" .. ADDON .. "|r:", ...)
end

--------------------------------------------------------------------------------
-- Fila de combate: trocar spec, talentos ou itens e proibido com o combate travado.
--------------------------------------------------------------------------------
local queue = {}

function ns.RunWhenSafe(fn)
    if InCombatLockdown() then
        queue[#queue + 1] = fn
    else
        fn()
    end
end

local function FlushQueue()
    if #queue == 0 then return end
    local pending = queue
    queue = {}
    for i = 1, #pending do
        pending[i]()
    end
end

--------------------------------------------------------------------------------
-- Icone: escolher sem chutar
--------------------------------------------------------------------------------
---Devolve o primeiro caminho de textura da lista que EXISTE neste cliente.
---
---`SetTexture` com caminho inexistente falha em SILENCIO — o botao fica vazio e nada avisa.
---Nome de icone e o tipo de coisa que eu nao consigo confirmar em disco (as texturas moram
---no CASC, nao na pasta de addons), entao ate aqui eu estava torcendo.
---
---`GetFileIDFromPath` resolve isso: devolve o id do arquivo, ou nil se o caminho nao existe.
---E API documentada do 12.1.0 (`ClientDocumentation.lua:29`) e um addon instalado a usa
---exatamente como teste de existencia (`MountJournalEnhanced/UI/SettingsDropDown.lua:88`).
---@param paths string[] candidatos, do preferido para o ultimo recurso
---@return string|nil caminho, boolean verificado
function ns.FirstIcon(paths)
    if type(GetFileIDFromPath) ~= "function" then
        return paths[#paths], false     -- sem como verificar: usa o ultimo recurso
    end

    for _, path in ipairs(paths) do
        local ok, id = pcall(GetFileIDFromPath, path)
        if ok and id then return path, true end
    end
    return paths[#paths], false
end

--------------------------------------------------------------------------------
---Aplica um atlas SO SE ele existir neste cliente, e diz se conseguiu.
---
---Esta funcao ja era chamada em dois lugares (`UI.lua:365` e `:472`) e **nunca existiu**: a
---guarda `if not ns.SetAtlasSafe` sempre caia no plano B, entao o divisor da coluna nunca chegou
---a tentar a arte da Blizzard. Codigo que se le como "tenta o atlas, senao usa a cor" fazendo
---so a segunda metade -- e sem nada acusando, porque a guarda estava certa.
---
---`SetAtlas` com nome inexistente falha em SILENCIO e deixa a textura em branco, que e o
---sintoma mais dificil de diagnosticar: nao ha erro, so um retangulo vazio. `GetAtlasInfo`
---devolve nil para atlas que nao existe, e `GetAtlas()` depois do `SetAtlas` confirma que
---pegou -- as duas conferencias, porque uma sozinha ja deixou passar um cabecalho azul aqui.
---@param texture table
---@param atlas string
---@return boolean aplicou
function ns.SetAtlasSafe(texture, atlas)
    if not texture or not atlas or not texture.SetAtlas then return false end

    if C_Texture and C_Texture.GetAtlasInfo then
        local ok, info = pcall(C_Texture.GetAtlasInfo, atlas)
        if not ok or not info then return false end
    end

    if not pcall(texture.SetAtlas, texture, atlas) then return false end
    if not texture.GetAtlas then return false end
    return texture:GetAtlas() ~= nil
end

--------------------------------------------------------------------------------
---Carrega o conjunto usado por ultimo. E o que o botao direito do minimapa faz: o caso
---comum e alternar entre dois conjuntos, e para isso nao vale abrir janela.
function ns.LoadLast()
    local wanted = ns.db and ns.db.last
    if not wanted then
        ns.UI.Toggle()
        return
    end
    for _, preset in ipairs(ns.db.presets) do
        if preset.name == wanted then
            -- CONJUNTO COM APARENCIA NAO SE APLICA POR AQUI, e a razao e concreta: a troca de
            -- aparencia so acontece no clique do BOTAO SEGURO, e este atalho nao e um. O que
            -- acontecia era pior que nao funcionar:
            --
            --   1. a aparencia nunca entrava, entao `IsLoaded` nunca dava verdadeiro;
            --   2. com `IsLoaded` falso, o atalho REAPLICAVA tudo a cada uso -- e o jogador via
            --      "do nada ele seta o item que ja deveria estar setado", que foi o relato;
            --   3. e ainda era uma troca parcial, que e o pior dos dois mundos.
            --
            -- Entao o atalho abre a janela com esse conjunto selecionado. Um clique a mais, e o
            -- clique certo -- o que faz a troca INTEIRA.
            if preset.transmog then
                ns.UI.Toggle()
                ns.UI.Select(preset)
                ns.Print(format(L["click Load to switch to %s completely."], preset.name or "?"))
                return
            end

            ns.Data.Apply(preset, function(text, isError)
                ns.UI.SetStatus(text, isError)
                if isError then ns.Print(text) end
            end)
            return
        end
    end
    ns.UI.Toggle()
end

--------------------------------------------------------------------------------
-- Eventos
--------------------------------------------------------------------------------
local handlers = {}

function handlers:ADDON_LOADED(addon)
    if addon ~= ADDON then return end

    -- SavedVariables so existem a partir daqui.
    RocketSwapDB = RocketSwapDB or {}
    for k, v in pairs(ns.defaults) do
        if RocketSwapDB[k] == nil then
            RocketSwapDB[k] = type(v) == "table" and CopyTable(v) or v
        end
    end
    ns.db = RocketSwapDB

    -- O CABECALHO DO DIARIO: versao, idioma e quando comecou. Sem isto o arquivo chegava sem
    -- dizer de que build ele e -- e a primeira coisa que se pergunta ao ler um log e "de quando
    -- e isso?". `Log.Init` existia e nao tinha chamador.
    if ns.Log then ns.Log.Init() end
end

function handlers:PLAYER_LOGIN()
    ns.Minimap.Create()
    ns.Alert.Create()
    ns.Print(format(L["loaded. %d preset(s). Type /rs."], #ns.db.presets))
end

function handlers:PLAYER_REGEN_ENABLED()
    FlushQueue()
end

-- Trocas feitas a mao (pela ficha ou pela janela de talentos) mudam qual conjunto esta
-- ativo. A janela precisa acompanhar, senao o "check" fica mentindo.
function handlers:EQUIPMENT_SETS_CHANGED()
    ns.UI.Refresh()
    ns.Minimap.Refresh()
end
function handlers:PLAYER_EQUIPMENT_CHANGED()
    ns.UI.Refresh()
    ns.Minimap.Refresh()
end
function handlers:TRAIT_CONFIG_UPDATED() ns.UI.Refresh() end
function handlers:ACTIVE_PLAYER_SPECIALIZATION_CHANGED() ns.UI.Refresh() end

-- OS EVENTOS QUE MUDAM "DA PARA TROCAR DE SPEC AGORA?".
--
-- O botao Carregar fica apagado enquanto o jogo nao deixa, e apagado sem reavaliar seria pior que
-- nao apagar: o jogador ficaria com um botao morto sem saber quando volta. Estes tres sao os que
-- a propria janela de talentos escuta para reabilitar o botao dela
-- (`Blizzard_ClassSpecializationsFrame.lua:69-73`), mais o fim de combate, que ja esta acima.
--
-- `PLAYER_SPECIALIZATION_CHANGED` alem do `ACTIVE_...`: o primeiro cobre o processo INTEIRO da
-- troca (a Blizzard registra os dois, e o comentario dela diz que este "needs to always be
-- registered so that the entire spec change process is always captured").
function handlers:PLAYER_SPECIALIZATION_CHANGED() ns.UI.Refresh() end

-- Andar cancela o cast de troca de spec, e `SPECIALIZATION_CHANGE_CAST_FAILED` nao cobre isso --
-- e por isso que a janela nativa escuta estes dois.
-- APRENDE A MAGIA DE TROCAR DE SPEC. Nao ha constante para ela na documentacao do cliente -- o
-- que ha e o predicado `IsSpecializationActivateSpell`, que a janela de talentos usa para
-- reconhecer o cast dela. Entao o addon pergunta ao jogo, uma vez, e guarda.
--
-- Sem isso nao da para saber quando a troca volta a ser possivel, e o botao ou fica apagado de
-- menos (o caso relatado) ou apagado demais.
function handlers:UNIT_SPELLCAST_SUCCEEDED(unit, _castGUID, spellID)
    if unit ~= "player" then return end
    ns.Data.NoteSpellCast(spellID)
    ns.UI.Refresh()
end

function handlers:UNIT_SPELLCAST_FAILED() ns.UI.Refresh() end
function handlers:UNIT_SPELLCAST_INTERRUPTED() ns.UI.Refresh() end

-- E o fim do prazo/recarga nao dispara evento proprio: `SPELL_UPDATE_COOLDOWN` e o que avisa que
-- alguma recarga andou, e e o gancho que o medidor nativo usa para redesenhar o cooldown do botao
-- de conjunto de aparencia (`Blizzard_TransmogTemplates.lua:57-61`).
function handlers:SPELL_UPDATE_COOLDOWN() ns.UI.Refresh() end

local frame = CreateFrame("Frame", ADDON .. "EventFrame")
for event in pairs(handlers) do
    frame:RegisterEvent(event)
end
frame:SetScript("OnEvent", function(self, event, ...)
    handlers[event](self, ...)
end)

ns.frame = frame
