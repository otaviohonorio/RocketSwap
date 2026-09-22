-- RocketSwap | Progress.lua
-- O painel flutuante da troca: aparece sozinho quando a troca começa, some sozinho quando
-- acaba, e **não depende de a janela do addon estar aberta**.
--
-- POR QUE ELE EXISTE, se a janela já mostra o progresso na coluna da direita. Porque o pedido
-- do usuário foi literal — *"ainda sinto falta de um aviso e alguma coisa que mostre o progresso
-- melhor da troca até terminar, que visualmente o usuário entenda que ainda está trocando"* — e
-- o painel de dentro da janela responde só para quem está com a janela aberta. Na prática o
-- jogador clica em Carregar e volta a olhar o jogo: é ali, e não na janela que ele acabou de
-- deixar para trás, que o sinal precisa aparecer.
--
-- ⚑ E ELE NÃO TEM DADO PRÓPRIO. Tudo vem de `Data.GetProgress()`, o mesmo que a janela lê, e a
-- arte de cada estado vem de `ns.ProgressVisuals`, a mesma tabela que a janela usa. Duas telas
-- com duas leituras do mesmo fato divergem na primeira mudança — e aí uma delas mente.
local ADDON, ns = ...
local L = ns.L

local Progress = {}
ns.Progress = Progress

local WIDTH = 240
local PAD = 10
local ROW = ns.PROGRESS_ROW or 22
local ICON = ns.PROGRESS_ICON or 16
local ICON_GAP = ns.PROGRESS_ICON_GAP or 5
local TITLE_INK = 16
local TITLE_GAP = 13
local BAR_H = 8
local BAR_GAP = 8

-- Quanto o resultado fica na tela depois de a troca acabar. **Três segundos, escolha do
-- usuário**: some sozinho, sem exigir clique, mas dá tempo de ler o que aconteceu.
--
-- Falha NÃO entra nessa conta: se algum passo falhou, o painel fica até o jogador fechar. O
-- que precisa ser lido não pode ter prazo, e aqui o prazo apagaria justamente o único caso em
-- que ele tem algo a dizer.
local HOLD = 3

-- O GRITO DE VITÓRIA. Pedido do usuário: nos três segundos que sobram depois de a troca
-- terminar, o painel deixa de ser relatório e vira comemoração.
--
-- E faz sentido além da piada: naquele ponto a lista de passos já cumpriu o papel dela — quem
-- estava acompanhando já viu cada um fechar. O que ainda falta comunicar é uma coisa só, e de
-- longe: **acabou, e deu certo**. Uma linha grande diz isso melhor que quatro linhas de detalhe.
--
-- E é **só a frase**. Uma versão anterior deixava "Trocando para <conjunto>" embaixo dela, e o
-- usuário apontou o óbvio: nessa altura já trocou, então a linha estava no tempo errado —
-- anunciava como presente o que tinha acabado de virar passado.
--
-- SÓ NO SUCESSO. Se algum passo falhou, o painel continua mostrando a lista e fica até o
-- jogador fechar: comemorar por cima de um passo que não deu seria o pior desfecho possível.
--
-- Não é chave de tradução de propósito: é nome próprio, e o mesmo em qualquer idioma.
local SHOUT = "Leroy Jeeeeeennkiiinnss!"

-- A cor da barra em cada momento. Dourado é "andando" — é a cor de progresso do jogo inteiro.
-- Verde só aparece quando **fechou tudo e deu certo**, e por isso ele não precisa de legenda:
-- ninguém confunde barra cheia e verde com troca pela metade.
local BAR_RUNNING = { 1, 0.82, 0, 0.85 }
local BAR_DONE    = { 0.25, 0.78, 0.35, 0.90 }

local frame

--------------------------------------------------------------------------------
-- A barra
--------------------------------------------------------------------------------
-- ⚑ A BARRA ANDA POR PASSO, NÃO POR TEMPO — e essa distinção é o que a torna honesta.
--
-- A corrente não sabe quanto vai demorar: o passo de especialização espera o servidor, e o
-- diário real mostrou a mesma troca sendo aceita ora em 4, ora em 14 segundos. Barra que corre
-- sozinha contra um relógio inventa uma previsão que ninguém tem, e barra que trava no meio é
-- pior que barra nenhuma — foi por isso que a versão de dentro da janela recusou ter uma.
--
-- O que dá para afirmar é **quantos passos fecharam de quantos**. Isso é verdade a cada quadro,
-- é o que o jogador quer saber, e não depende de adivinhação.
--
-- E tem uma exceção legítima: quando o passo em curso é uma CONJURAÇÃO de verdade (a troca de
-- especialização conjura a magia 200749), o jogo informa início e fim, e aí a fatia daquele
-- passo pode andar com o tempo real da conjuração. Isso não é previsão: é medida.
local function BarFill(passos)
    if not passos or #passos == 0 then return 0 end

    local fechados, atual = 0, nil
    for i, p in ipairs(passos) do
        if p.state == "done" or p.state == "skipped" or p.state == "failed" then
            fechados = fechados + 1
        elseif p.state == "doing" and not atual then
            atual = i
        end
    end

    local fatia = 1 / #passos
    local fill = fechados * fatia

    -- A fatia do passo em curso só avança quando há conjuração medida.
    if atual and UnitCastingInfo then
        local _, _, _, startMS, endMS = UnitCastingInfo("player")
        if startMS and endMS and endMS > startMS then
            local agora = GetTime() * 1000
            local dentro = (agora - startMS) / (endMS - startMS)
            if dentro > 0 and dentro < 1 then
                fill = fill + fatia * dentro
            end
        end
    end

    return math.min(1, fill)
end

--------------------------------------------------------------------------------
-- Montagem
--------------------------------------------------------------------------------
local function Build()
    frame = CreateFrame("Frame", ADDON .. "Progress", UIParent, "BackdropTemplate")
    frame:SetWidth(WIDTH)
    frame:SetHeight(80)
    frame:SetFrameStrata("HIGH")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetClampedToScreen(true)

    if frame.SetBackdrop then
        frame:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        frame:SetBackdropColor(0.04, 0.04, 0.05, 0.92)
        frame:SetBackdropBorderColor(0, 0, 0, 1)
    end

    local pos = ns.db and ns.db.progressPos
    if pos then
        frame:SetPoint(pos.point or "CENTER", UIParent, pos.point or "CENTER", pos.x or 0, pos.y or 0)
    else
        -- Acima da barra de ação e abaixo do centro: fora da mira, mas no caminho do olho.
        frame:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 220)
    end

    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint()
        if ns.db then ns.db.progressPos = { point = point, x = x, y = y } end
    end)

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.title:SetPoint("TOPLEFT", PAD, -PAD)
    frame.title:SetWidth(WIDTH - PAD * 2 - 40)
    frame.title:SetJustifyH("LEFT")
    frame.title:SetWordWrap(false)

    frame.clock = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.clock:SetPoint("TOPRIGHT", -PAD, -PAD - 2)
    frame.clock:SetWidth(36)
    frame.clock:SetJustifyH("RIGHT")

    -- A barra.
    local trilho = CreateFrame("Frame", nil, frame)
    trilho:SetPoint("TOPLEFT", PAD, -(PAD + TITLE_INK + BAR_GAP))
    trilho:SetSize(WIDTH - PAD * 2, BAR_H)
    trilho.bg = trilho:CreateTexture(nil, "BACKGROUND")
    trilho.bg:SetAllPoints()
    trilho.bg:SetColorTexture(1, 1, 1, 0.08)

    trilho.fill = trilho:CreateTexture(nil, "ARTWORK")
    trilho.fill:SetPoint("TOPLEFT")
    trilho.fill:SetPoint("BOTTOMLEFT")
    trilho.fill:SetWidth(1)
    trilho.fill:SetColorTexture(1, 0.82, 0, 0.85)

    -- Os cortes entre as fatias: sem eles a barra vira um bloco e o jogador perde a noção de
    -- quantas etapas existem, que é a informação que esta barra carrega.
    -- Visível desde o começo e até o fim: ela é a única parte da tela de progresso que continua
    -- dizendo algo depois que a troca acaba.
    trilho:Show()
    trilho.ticks = {}
    trilho:SetScript("OnShow", function() end)
    frame.trilho = trilho

    -- As linhas de passo, com a mesma arte e os mesmos estados da janela.
    frame.rows = {}
    for i = 1, 4 do
        local row = CreateFrame("Frame", nil, frame)
        row:SetSize(WIDTH - PAD * 2, ROW)
        row:SetPoint("TOPLEFT", PAD, -(PAD + TITLE_INK + BAR_GAP + BAR_H + TITLE_GAP + (i - 1) * ROW))

        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(ICON, ICON)
        row.icon:SetPoint("LEFT")

        row.dot = row:CreateTexture(nil, "ARTWORK")
        row.dot:SetSize(4, 4)
        row.dot:SetPoint("CENTER", row.icon, "CENTER")
        row.dot:SetColorTexture(1, 1, 1, 0.5)

        row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.label:SetPoint("LEFT", row.icon, "RIGHT", ICON_GAP, 0)
        row.label:SetWidth(WIDTH - PAD * 2 - ICON - ICON_GAP)
        row.label:SetJustifyH("LEFT")
        row.label:SetWordWrap(false)

        frame.rows[i] = row
    end

    -- O grito ocupa o painel inteiro quando aparece, entáo nasce centralizado e escondido.
    -- O grito ocupa o espaço das linhas de passo, ABAIXO da barra — que não sai da tela. Duas
    -- linhas são permitidas: numa janela de 240 a frase não cabe inteira, e encolher a fonte
    -- para forçar uma linha só tiraria dela justamente o tamanho, que é o recado.
    frame.shout = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.shout:SetPoint("TOPLEFT", frame.trilho, "BOTTOMLEFT", 0, -6)
    frame.shout:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD, PAD)
    frame.shout:SetJustifyH("CENTER")
    frame.shout:SetJustifyV("MIDDLE")
    frame.shout:SetWordWrap(true)
    frame.shout:SetTextColor(0.35, 0.90, 0.45)
    frame.shout:Hide()

    frame.close = CreateFrame("Button", nil, frame)
    frame.close:SetSize(14, 14)
    frame.close:SetPoint("TOPRIGHT", -4, -4)
    frame.close.tex = frame.close:CreateTexture(nil, "ARTWORK")
    frame.close.tex:SetAllPoints()
    if not (ns.SetAtlasSafe and ns.SetAtlasSafe(frame.close.tex, "common-icon-redx")) then
        frame.close.tex:SetTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
    end
    frame.close.tex:SetAlpha(0.5)
    frame.close:SetScript("OnClick", function() frame:Hide() end)
    frame.close:SetScript("OnEnter", function() frame.close.tex:SetAlpha(1) end)
    frame.close:SetScript("OnLeave", function() frame.close.tex:SetAlpha(0.5) end)
    frame.close:Hide()

    frame:SetScript("OnUpdate", function(self, elapsed)
        self.__acc = (self.__acc or 0) + elapsed
        if self.__acc < 0.1 then return end
        self.__acc = 0
        Progress.Refresh()
    end)

    frame:Hide()
    return frame
end

--------------------------------------------------------------------------------
-- Desenho
--------------------------------------------------------------------------------
local function LayoutTicks(trilho, n)
    for _, t in ipairs(trilho.ticks) do t:Hide() end
    if n < 2 then return end
    local largura = trilho:GetWidth()
    for i = 1, n - 1 do
        local t = trilho.ticks[i]
        if not t then
            t = trilho:CreateTexture(nil, "OVERLAY")
            t:SetColorTexture(0, 0, 0, 0.8)
            t:SetWidth(1)
            trilho.ticks[i] = t
        end
        t:ClearAllPoints()
        t:SetPoint("TOP", trilho, "TOPLEFT", largura * (i / n), 0)
        t:SetPoint("BOTTOM", trilho, "BOTTOMLEFT", largura * (i / n), 0)
        t:Show()
    end
end

---As duas caras do painel: o relatório (enquanto troca, e quando falha) e o grito (quando
---termina bem). Uma esconde a outra inteira — sobrepor as duas deixaria o grito ilegiível por
---cima das linhas de passo.
local function ShowShout(frame_, mostrar)
    frame_.shout:SetShown(mostrar)
    -- A BARRA NÃO SAI. Ela é a única coisa da tela de progresso que ainda diz algo depois do
    -- fim — cheia e verde, é o "tudo fechado" em forma, e some junto com o painel.
    frame_.clock:SetShown(not mostrar)
    frame_.title:SetShown(not mostrar)
    for _, row in ipairs(frame_.rows) do
        if mostrar then row:Hide() end
    end

    local cor = mostrar and BAR_DONE or BAR_RUNNING
    frame_.trilho.fill:SetColorTexture(cor[1], cor[2], cor[3], cor[4])
    if mostrar then
        frame_.shout:SetText(SHOUT)
        frame_.trilho.fill:SetWidth(frame_.trilho:GetWidth())
    end
end

function Progress.Refresh()
    if not frame then return end

    local passos, info = ns.Data.GetProgress()
    if not passos or not info then
        frame:Hide()
        return
    end

    -- As duas transições, do mesmo jeito que a janela as trata: `info.live` é o agora,
    -- `frame.live` é o que este painel viu por último.
    if info.live and not frame.live then
        frame.live, frame.holdUntil = true, nil
    elseif not info.live and frame.live then
        frame.live = false
        local falhou = false
        for _, p in ipairs(passos) do
            if p.state == "failed" then falhou = true end
        end
        -- Falha não tem prazo: fica até o jogador fechar.
        frame.holdUntil = falhou and math.huge or (GetTime() + HOLD)
        frame.close:SetShown(falhou)
        frame.shouting = not falhou
    end

    if not info.live and frame.holdUntil and GetTime() >= frame.holdUntil then
        frame.holdUntil = nil
        frame:Hide()
        return
    end

    -- A ALTURA É A MESMA DO COMEÇO AO FIM. Encolher no desfecho faz o painel pular na tela
    -- bem no instante em que o olho volta para ele, e um salto de layout se lê como defeito.
    frame:SetHeight(PAD * 2 + TITLE_INK + BAR_GAP + BAR_H + TITLE_GAP + ROW * #passos)

    -- TERMINOU E DEU CERTO: o painel troca de conteúdo pelos três segundos que lhe restam.
    if frame.shouting then
        ShowShout(frame, true)
        if not frame:IsShown() then frame:Show() end
        return
    end

    ShowShout(frame, false)
    frame.title:SetText(format(L["Switching to %s"], info.preset and info.preset.name or "?"))

    if info.live then
        local secs = math.max(0, math.floor(GetTime() - (info.startedAt or 0)))
        frame.clock:SetText(secs .. "s")
    end

    local trilho = frame.trilho
    LayoutTicks(trilho, #passos)
    local fill = BarFill(passos)
    -- `SetWidth(0)` some com a textura e o jogo reclama; 1px é o mínimo visível.
    trilho.fill:SetWidth(math.max(1, trilho:GetWidth() * fill))

    for i, row in ipairs(frame.rows) do
        local passo = passos[i]
        row:SetShown(passo ~= nil)
        if passo then
            local visual = ns.ProgressVisuals[passo.state] or ns.ProgressVisuals.pending
            local temArte = visual.atlas and ns.SetAtlasSafe
                and ns.SetAtlasSafe(row.icon, visual.atlas) or false
            row.icon:SetShown(temArte)
            row.icon:SetAlpha(visual.alpha)
            row.dot:SetShown(not temArte)
            row.dot:SetVertexColor(1, 1, 1, visual.alpha)
            row.label:SetText(passo.label)
            row.label:SetAlpha(visual.alpha)
        end
    end

    if not frame:IsShown() then frame:Show() end
end

---Chamado pela corrente quando uma troca começa.
function Progress.Start()
    if ns.db and ns.db.hideProgress then return end
    if not frame then Build() end
    frame.live, frame.holdUntil, frame.shouting = nil, nil, nil
    frame.close:Hide()
    ShowShout(frame, false)
    Progress.Refresh()
end

function Progress.Frame()
    return frame
end

---A conta da barra, exposta para o harness.
---
---A arte da barra só se vê no jogo, mas a CONTA é aritmética e se confere em disco — e é ela
---que carrega a promessa: a barra afirma quantos passos fecharam, e nada sobre tempo.
function Progress.DebugShout()
    return SHOUT
end

function Progress.DebugBarFill(passos)
    return BarFill(passos)
end
