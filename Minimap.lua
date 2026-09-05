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

local function Reposition()
    local angle = math.rad(ns.db.minimap and ns.db.minimap.angle or 210)
    button:SetPoint("CENTER", Minimap, "CENTER",
        math.cos(angle) * RADIUS, math.sin(angle) * RADIUS)
end

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
    button.icon = button:CreateTexture(nil, "BACKGROUND")
    button.icon:SetSize(20, 20)
    button.icon:SetPoint("CENTER", -1, 1)
    button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    button:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "RightButton" then
            ns.LoadLast()
        else
            ns.UI.Toggle()
        end
    end)

    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(ADDON, 1, 1, 1)
        GameTooltip:AddLine(L["Left click: open. Right click: load the last preset."],
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

---Atualiza o ícone para o conjunto vestido. Chamado quando o equipamento muda.
function Minimap_.Refresh()
    if not button then return end

    local _, icon = ns.Data.GearSetName(ns.Data.GetEquippedSetID())
    -- Sem conjunto vestido (ou peça trocada à mão), cai para o ícone do addon — o mesmo do
    -- RocketMeter, que é o único nome que eu sei existir neste cliente.
    button.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_MissileLarge_Red")
end
