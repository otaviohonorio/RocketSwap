-- RocketSwap | Core.lua
-- Namespace do addon: tudo que for compartilhado entre arquivos vai em `ns`.
local ADDON, ns = ...
local L = ns.L

ns.defaults = {
    presets = {},        -- { { name, spec, talent, gear }, ... }
    last = nil,          -- nome do ultimo conjunto carregado, para o clique direito
    minimap = { angle = 210 },
    pos = nil,
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
end

function handlers:PLAYER_LOGIN()
    ns.Minimap.Create()
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

local frame = CreateFrame("Frame", ADDON .. "EventFrame")
for event in pairs(handlers) do
    frame:RegisterEvent(event)
end
frame:SetScript("OnEvent", function(self, event, ...)
    handlers[event](self, ...)
end)

ns.frame = frame
