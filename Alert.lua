-- RocketSwap | Alert.lua
-- Dois avisos, e os dois funcionam SEM que o jogador crie um conjunto:
--
--   1. Equipamento errado para o conteúdo — de PvE em arena, de PvP em masmorra.
--   2. No ready check, um resumo do que você está usando, para o grupo conferir antes de puxar.
--
-- O MODO DE FALHA DESTE ARQUIVO NÃO É ERRO DE LUA — é o usuário desligar porque encheu o saco.
-- O critério de aceitação é: quem fez tudo certo por duas semanas viu o addon zero vezes.
-- Daí as quatro comportas antes de qualquer pixel:
--
--   a) DÁ PARA CONSERTAR? Em combate, ou com a restrição já ativa, o aviso cala. Aviso sobre o
--      que não tem mais conserto é ruído puro.
--   b) A LEITURA É CONFIÁVEL? Se todo slot lido deu errado, é a detecção que falhou, não o
--      jogador que errou dezesseis peças (ver `Gear.LooksReliable`).
--   c) JÁ AVISEI ISSO? Mesma situação, mesma natureza: cala.
--   d) O USUÁRIO MANDOU CALAR? Silêncio persistido, por slot e por situação.
--
-- `ADDON_RESTRICTION_STATE_CHANGED` é a última chamada: a documentação da Blizzard diz que ele
-- dispara **antes** da restrição ativar. E `IsAddOnRestrictionActive` "will always return false
-- during dispatch" desse evento — por isso lemos o `state` do payload, nunca a função.
local ADDON, ns = ...
local L = ns.L

local Alert = {}
ns.Alert = Alert

local frame, ui
local lastKey            -- a última situação avisada, para não repetir

--------------------------------------------------------------------------------
-- Contexto
--------------------------------------------------------------------------------
---Onde estamos? "pvp", "pve" ou nil (mundo aberto: o addon não opina).
function Alert.Context()
    local inInstance, instanceType = IsInInstance()
    if inInstance then
        if instanceType == "arena" or instanceType == "pvp" then return "pvp" end
        if instanceType == "party" or instanceType == "raid" then return "pve" end
        return nil
    end

    -- Fila de PvP aceita, ainda fora da instância: é o melhor momento do aviso, porque dá
    -- tempo de trocar antes de entrar.
    if GetMaxBattlefieldID then
        for i = 1, (GetMaxBattlefieldID() or 0) do
            local status = GetBattlefieldStatus(i)
            if status == "confirm" or status == "active" then return "pvp" end
        end
    end
    return nil
end

---Dá para consertar agora?
local function CanFix()
    if InCombatLockdown() then return false end

    if C_RestrictedActions and C_RestrictedActions.GetAddOnRestrictionState and Enum
        and Enum.AddOnRestrictionType and Enum.AddOnRestrictionState then
        for _, kind in ipairs({ Enum.AddOnRestrictionType.PvPMatch,
                               Enum.AddOnRestrictionType.Encounter,
                               Enum.AddOnRestrictionType.ChallengeMode }) do
            local ok, state = pcall(C_RestrictedActions.GetAddOnRestrictionState, kind)
            if ok and state == Enum.AddOnRestrictionState.Active then return false end
        end
    end
    return true
end

--------------------------------------------------------------------------------
-- A janela do aviso
--------------------------------------------------------------------------------
local function Build()
    if ui then return ui end

    ui = CreateFrame("Frame", ADDON .. "Alert", UIParent, "ButtonFrameTemplate")
    ui:SetSize(360, 190)
    ui:SetPoint("TOP", UIParent, "TOP", 0, -180)
    ui:SetFrameStrata("DIALOG")
    ui:SetMovable(true)
    ui:EnableMouse(true)
    ui:RegisterForDrag("LeftButton")
    ui:SetScript("OnDragStart", ui.StartMoving)
    ui:SetScript("OnDragStop", ui.StopMovingOrSizing)
    ui:Hide()

    if ui.SetTitle then ui:SetTitle(ADDON) end
    if ui.SetPortraitToAsset then ui:SetPortraitToAsset(ns.FirstIcon(ns.ICON_CANDIDATES)) end
    if ui.Inset then ui.Inset:Hide() end

    ui.headline = ui:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    ui.headline:SetPoint("TOPLEFT", 60, -30)
    ui.headline:SetPoint("RIGHT", -14, 0)
    ui.headline:SetJustifyH("LEFT")
    ui.headline:SetTextColor(1, 0.82, 0)

    ui.body = ui:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ui.body:SetPoint("TOPLEFT", 14, -64)
    ui.body:SetPoint("RIGHT", -14, 0)
    ui.body:SetJustifyH("LEFT")
    ui.body:SetSpacing(3)

    ui.fix = CreateFrame("Button", nil, ui, "UIPanelButtonTemplate")
    ui.fix:SetSize(150, 22)
    ui.fix:SetPoint("BOTTOMLEFT", 14, 8)

    ui.mute = CreateFrame("Button", nil, ui, "UIPanelButtonTemplate")
    ui.mute:SetSize(150, 22)
    ui.mute:SetPoint("BOTTOMRIGHT", -14, 8)
    ui.mute:SetText(L["Don't warn here"])
    ui.mute:SetScript("OnClick", function()
        if lastKey then
            ns.db.muted = ns.db.muted or {}
            ns.db.muted[lastKey] = true
        end
        ui:Hide()
    end)

    tinsert(UISpecialFrames, ui:GetName())
    return ui
end

function Alert.Hide()
    if ui then ui:Hide() end
end

--------------------------------------------------------------------------------
-- Aviso de equipamento errado
--------------------------------------------------------------------------------
---Um conjunto que sirva para o contexto, se o jogador tiver criado algum. É o que transforma
---o aviso de "você errou" em "quer que eu conserte?". Sem conjuntos, o aviso só aponta.
local function PresetFor(context)
    for _, preset in ipairs(ns.db.presets or {}) do
        if preset.gear then
            local wrong, read = ns.Gear.Wrong(context == "pvp")
            -- Um conjunto serve se, aplicado, ele resolveria: usamos o próprio nome como
            -- pista quando não dá para simular (não dá — as peças do conjunto não estão
            -- vestidas). Nome é heurística, e por isso é só sugestão de botão, nunca ação
            -- automática.
            local name = (preset.name or ""):lower()
            local looksPvP = name:find("pvp") or name:find("arena") or name:find("bg")
                or name:find("campo")
            if (context == "pvp") == (looksPvP ~= nil) then
                return preset, wrong, read
            end
        end
    end
    return nil
end

function Alert.Check(reason)
    if not ns.db or ns.db.warn == false then return end

    local context = Alert.Context()
    if not context then return end
    if not CanFix() then return end

    local wrong, read = ns.Gear.Wrong(context == "pvp", ns.db.mutedSlots)
    if #wrong == 0 then
        Alert.Hide()
        return
    end
    if not ns.Gear.LooksReliable(wrong, read) then return end

    local key = context .. ":" .. (#wrong > 0 and "gear" or "")
    if ns.db.muted and ns.db.muted[key] then return end
    if key == lastKey and ui and ui:IsShown() then return end
    lastKey = key

    -- O texto do jogo, no lugar do jogo: aviso amarelo abaixo do centro. É onde a Blizzard
    -- põe recado desta natureza, e o helper já cuida de cor e de repetição.
    if UIErrorsFrame and UIErrorsFrame.AddExternalWarningMessage then
        pcall(UIErrorsFrame.AddExternalWarningMessage, UIErrorsFrame,
            context == "pvp" and L["PvE gear in a PvP match."] or L["PvP gear in PvE content."])
    end

    Build()

    ui.headline:SetText(context == "pvp" and L["PvE gear in a PvP match."]
        or L["PvP gear in PvE content."])

    local lines = {}
    for i = 1, math.min(#wrong, 6) do
        lines[#lines + 1] = "• " .. ns.Gear.SlotName(wrong[i].slot) .. "   " .. wrong[i].link
    end
    if #wrong > 6 then
        lines[#lines + 1] = format(L["...and %d more."], #wrong - 6)
    end
    ui.body:SetText(table.concat(lines, "\n"))

    local preset = PresetFor(context)
    if preset then
        ui.fix:SetText(format(L["Load %s"], preset.name))
        ui.fix:SetScript("OnClick", function()
            ns.Data.Apply(preset, function(text) ns.Print(text) end)
            ui:Hide()
        end)
        ui.fix:Show()
    else
        ui.fix:Hide()
    end

    ui:SetHeight(120 + math.min(#wrong, 7) * 14)
    ui:Show()
end

--------------------------------------------------------------------------------
-- Ready check: o resumo antes de puxar
--------------------------------------------------------------------------------
---O que você está usando agora, em uma linha.
---
---Não é aviso e não julga nada: é a conferência que o líder pede quando manda o ready check.
---"Gélido · SBA ST · Frost" responde sozinho se você esqueceu de trocar depois da última luta.
function Alert.Summary()
    local parts = {}

    local specIndex = ns.Data.GetCurrentSpecIndex()
    local spec = ns.Data.GetSpecByIndex(specIndex)
    if spec then parts[#parts + 1] = spec.name end

    if spec then
        local configID = ns.Data.GetActiveLoadoutID(spec.id)
        local name = configID and ns.Data.LoadoutName(spec.id, configID)
        parts[#parts + 1] = name or L["(no talent loadout)"]
    end

    local setID = ns.Data.GetEquippedSetID()
    parts[#parts + 1] = setID and ns.Data.GearSetName(setID) or L["(no gear set)"]

    return table.concat(parts, "  ·  ")
end

function Alert.OnReadyCheck()
    if not ns.db or ns.db.readyCheck == false then return end

    ns.Print(L["ready check:"] .. " " .. Alert.Summary())

    -- Também no meio da tela, porque o ready check tem prazo e ninguém está lendo o chat.
    if RaidWarningUtil and RaidWarningUtil.AddMessage then
        pcall(RaidWarningUtil.AddMessage, Alert.Summary(), NORMAL_FONT_COLOR, 5)
    end

    -- E de quebra: se o equipamento estiver errado para o conteúdo, é a hora de saber.
    Alert.Check("readycheck")
end

--------------------------------------------------------------------------------
-- Gatilhos
--------------------------------------------------------------------------------
function Alert.Create()
    if frame then return frame end

    frame = CreateFrame("Frame", ADDON .. "AlertEvents")

    -- Entrar em instância: `PLAYER_ENTERING_WORLD` sozinho é cedo demais — o equipamento
    -- ainda não está carregado. Dois segundos é o que o TalentReminder usa, pelo mesmo motivo.
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    frame:RegisterEvent("UPDATE_BATTLEFIELD_STATUS")
    frame:RegisterEvent("READY_CHECK")
    -- Estes só CANCELAM: podem esconder um aviso, nunca criar um.
    frame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    frame:RegisterEvent("EQUIPMENT_SWAP_FINISHED")
    if C_EventUtils and C_EventUtils.IsEventValid
        and C_EventUtils.IsEventValid("ADDON_RESTRICTION_STATE_CHANGED") then
        frame:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED")
    end

    frame:SetScript("OnEvent", function(_, event, a, b)
        if event == "READY_CHECK" then
            Alert.OnReadyCheck()

        elseif event == "PLAYER_EQUIPMENT_CHANGED" or event == "EQUIPMENT_SWAP_FINISHED" then
            ns.Gear.ClearCache()
            lastKey = nil
            Alert.Hide()

        elseif event == "ADDON_RESTRICTION_STATE_CHANGED" then
            -- `b` é o estado. `Activating` é a última chamada: ainda dá para trocar.
            if Enum and Enum.AddOnRestrictionState and b == Enum.AddOnRestrictionState.Activating then
                Alert.Check("restriction")
            end

        else
            C_Timer.After(2, function() Alert.Check(event) end)
        end
    end)

    return frame
end
