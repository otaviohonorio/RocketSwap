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

-- Candidatos de ícone, do preferido para o último recurso. Quem escolhe é o CLIENTE, via
-- `ns.FirstIcon` → `GetFileIDFromPath`: caminho de textura que não existe falha em silêncio,
-- e nome de ícone é justamente o que não dá para conferir em disco (as texturas moram no
-- CASC, não na pasta de addons).
--
-- O último da lista é o do RocketMeter — o único nome que eu SEI existir neste cliente,
-- porque o usuário o vê na lista de addons hoje. Se todos os outros falharem, cai nele.
--
-- `/rs icon` imprime quais resolveram: se você preferir outro, é trocar uma linha.
local ICON_CANDIDATES = {
    "Interface\\Icons\\INV_Misc_EnggizmosCog",
    "Interface\\Icons\\INV_Misc_Gear_01",
    "Interface\\Icons\\Trade_Engineering",
    "Interface\\Icons\\INV_Misc_Bag_08",
    "Interface\\Icons\\INV_Misc_MissileLarge_Red",
}

ns.ICON_CANDIDATES = ICON_CANDIDATES

local function Reposition()
    local angle = math.rad(ns.db.minimap and ns.db.minimap.angle or 210)
    button:SetPoint("CENTER", Minimap, "CENTER",
        math.cos(angle) * RADIUS, math.sin(angle) * RADIUS)
end

---O menu do botao direito: os conjuntos, pelo titulo, para trocar sem abrir a janela.
---
---Sem conjunto nenhum, ou num cliente sem o menu novo, o direito faz o que o esquerdo faz --
---abre a janela. NUNCA uma troca: e a troca sem pedir que este menu existe para eliminar.
function Minimap_.Menu(owner)
    local presets = ns.db and ns.db.presets or {}
    if #presets == 0 or not _G.MenuUtil then
        ns.UI.Toggle()
        return false
    end

    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle(L["Switch to"])
        for _, preset in ipairs(presets) do
            root:CreateButton(preset.name or "?", function()
                ns.LoadPreset(preset)
            end)
        end
    end)
    return true
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

    -- (!) O BOTAO DIREITO LISTA OS CONJUNTOS. ELE NAO TROCA NADA SOZINHO.
    --
    -- Ele chamava `ns.LoadLast()`, e um usuario reportou em video que o clique direito "trocava
    -- a spec sozinha". Estava certo, e o codigo fazia exatamente isso.
    --
    -- Dois motivos para tirar:
    --
    --   * BOTAO DIREITO EM ICONE DE MINIMAPA ABRE MENU. E a convencao do jogo inteiro, e e o
    --     que os outros dois addons Rocket fazem (nos dois, o direito abre as opcoes). Este era
    --     o unico que divergia -- e o unico em que a acao divergente era destrutiva. Quem clica
    --     esperando um menu leva uma troca de spec, talentos e itens.
    --   * A DICA NAO SALVA NINGUEM. Ela dizia "Right click: load the last preset", mas dica
    --     exige passar o mouse e ler, e ninguem le dica antes de clicar com o direito.
    --
    -- POR QUE ISSO NAO APARECIA AQUI: todos os conjuntos deste desenvolvedor tem aparencia, e
    -- conjunto com aparencia cai no ramo do `LoadPreset` que ABRE A JANELA em vez de aplicar.
    -- O dado dele impedia o defeito de acontecer. Os conjuntos do usuario que reportou nao tem
    -- aparencia, entao caiam direto no `Data.Apply`. Confirmado nos dois SavedVariables.
    button:SetScript("OnClick", function(self, mouseButton)
        if mouseButton == "RightButton" then
            Minimap_.Menu(self)
        else
            ns.UI.Toggle()
        end
    end)

    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(ADDON, 1, 1, 1)
        GameTooltip:AddLine(L["Left click: open. Right click: pick a preset."],
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

---Ícone do botão: FIXO e genérico.
---
---A primeira versão mostrava o ícone do conjunto vestido, com a ideia de virar indicador. Na
---prática o botão passou a parecer ícone de classe — o usuário viu um Cavaleiro da Morte
---Sangue no minimapa, não o addon. Botão de addon precisa dizer QUAL addon ele é; qual
---conjunto está ativo já é dito na janela, pelo ✓.
function Minimap_.Refresh()
    if not button then return end
    button.icon:SetTexture(ns.FirstIcon(ICON_CANDIDATES))
end
