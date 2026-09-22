-- RocketSwap | UI.lua
-- A janela: lista de conjuntos à esquerda, editor à direita, estado no rodapé.
--
-- ESTE ARQUIVO FOI REESCRITO depois do primeiro teste in-game. O print mostrou três defeitos,
-- e os três vinham da mesma raiz: **eu ancorei conteúdo sem contar com a arte do template.**
-- A geometria abaixo foi medida no código-fonte da UI da Blizzard do 12.1.0, não estimada.
--
--   1. O RETRATO POR CIMA DO TEXTO. `PortraitFrameTemplate` desenha um disco de Ø58 com
--      centro em (26, −22) do frame. O rótulo "Conjuntos" estava em (14, −34), a
--      sqrt(12² + 12²) = 17px do centro — ou seja, 12px DENTRO do disco.
--      REGRA: nada ancorado em `frame` com x < 58 e y > −55. Nada aqui viola isso.
--
--   2. RÓTULOS ÓRFÃOS. Com zero conjuntos, "Nome / Especialização / Talentos / Itens"
--      apareciam sem campo embaixo: eu escondia os controles e esquecia os rótulos.
--      A correção não é um `SetShown` a mais — é que **o estado "nada selecionado" deixou de
--      existir**: com ≥1 conjunto, a lista seleciona o primeiro sozinha. Precedente da
--      Blizzard: `ClickBindingFrameMixin:OnShow` foca o primeiro item.
--      E cada rótulo agora vive DENTRO do seu grupo — esconder o grupo esconde os dois.
--
--   3. JANELA VAZIA. 640×452 para 2 a 5 conjuntos. Agora 520×320, derivado do conteúdo, e o
--      estado vazio é um bloco centralizado com uma frase e um botão.
--
-- O TEMPLATE MUDOU para `ButtonFrameTemplate`: é o `PortraitFrameTemplate` mais um `Inset` já
-- posicionado nos offsets oficiais (`PANEL_INSET_*` em `SharedUIPanelTemplates.lua:4-9`).
-- Ancorar na área rebaixada em vez de no frame cru torna o bug 1 impossível de repetir.
local ADDON, ns = ...
local L = ns.L

local UI = {}
ns.UI = UI

-- Todos os números têm origem. Onde há citação, ela é de arquivo do cliente 12.1.0.
-- A altura subiu de 420 para 452 quando a sub-opção de modo guerra entrou na faixa de Avisos
-- (12/09). A conta é fechada, não estética: a faixa começa em −304, três caixas terminam em −112
-- dentro dela (142 de altura), e o rodapé que o `ButtonFrameTemplate` reserva come 26 px do fundo
-- ⇒ 304 + 142 + 26 = 472, mais os mesmos 4 px de folga que a janela de 420 já tinha.
-- (Era 118/452 com três caixas; a do convite de fila, 18/09, trouxe a quarta.)
-- ⛑ A LARGURA SUBIU DE 520 PARA 620, e os 100 px vão INTEIROS para a lista. A coluna da
-- direita fica pixel a pixel como estava: `FIELD_W` e `NAME_W` são medidas absolutas alinhadas
-- com a borda (a arte terminava em 500 com janela de 520, e termina em 600 com janela de 620).
-- Dividir o ganho entre as duas colunas obrigaria a recalcular as duas, e a da direita não
-- estava apertada — quem estava era a lista, que agora mostra um card e não uma linha.
-- A altura é CALCULADA mais abaixo, quando `LIST_BOTTOM` existe: janela e lista deixaram de ser
-- dois números escolhidos à parte, e passou a ser a lista que manda no tamanho da janela.
local WIDTH = 620
local HEIGHT
local LIST_W = 360            -- largura externa do inset da lista: x 4..364
local GUTTER = 20             -- calha entre colunas (MountJournal)
local COL_X = 384             -- borda esquerda da ARTE da coluna direita
local ROW_SPACING = 2

-- ⛑ A LINHA VIROU CARD, e por isso a altura dela deixou de ser constante.
--
-- Pedido do usuário: *"Spec: Tal (quebra linha) Talento: tal (quebra linha) Equipamento: tal"*.
-- Antes tudo isso era UMA linha com pontos separando — `Sangue · Blood M+ · Blood · Dark` — e
-- nela o jogador tinha que saber de cor qual valor era o quê. Com rótulo por linha, não tem o
-- que saber: está escrito.
--
-- A altura acompanha o que o conjunto define. Reservar quatro linhas sempre deixaria três vazias
-- num conjunto só de itens, e espaço guardado para conteúdo que não existe é o que mais faz uma
-- janela parecer quebrada — a mesma regra que a `Data.GetProgress` já segue ao filtrar passos.
local CARD_PAD = 8            -- respiro acima do nome e abaixo da última linha
local CARD_NAME_INK = 16      -- `GameFontNormal` a 13pt, arredondado pela caixa da fonte
local CARD_LINE = 15          -- passo entre linhas de detalhe (11pt de tinta + 4 de respiro)
local CARD_WARN = 24          -- a placa do aviso: altura de botão (22) mais 2 de folga
-- O DESENHO DO CARD, escolhido pelo usuario depois de duas tentativas minhas erradas:
--
--   Tank                        [ Carregar ]     <- titulo sozinho, na margem
--   (icone)  Especializacao: Sangue              <- icone a esquerda do BLOCO de campos
--            Talentos: Blood M+
--            Equipamento: Blood
--
-- A 0.34.1 tinha posto o icone no alto como distintivo e o titulo abaixo dele. Reprovado na
-- hora: *"ficou ruim o titulo, eu gostei do icone ao lado no comeco"*. O icone volta para o
-- lado -- so que ao lado dos CAMPOS, nao do titulo, que e o que libera a linha do titulo.
local CARD_ICON = 32          -- o icone, a esquerda do bloco de campos
local CARD_LEFT = 44          -- onde os campos comecam: depois do icone, com a margem dele
local CARD_NAME_GAP = 4       -- entre o titulo e a primeira linha de campo

-- TETO DE LARGURA DO TEXTO. A outra reclamacao da 0.34.1 foi *"ficou muito comprido as linhas"*:
-- numa janela de 620 elas atravessavam de borda a borda.
--
-- O numero e DERIVADO, e nao escolhido: e o que sobra da largura da lista depois do recuo dos
-- campos e da barra de rolagem. Um teto fixo maior que isso nao encurtaria nada -- ele so
-- deixaria o texto transbordar a linha, que e pior que a linha comprida.
local CARD_TEXT_W = LIST_W - CARD_LEFT - 30

-- ⛑ QUANTOS CARDS INTEIROS TÊM QUE CABER SEM ROLAR. Pedido do usuário: três.
--
-- O inset da lista tinha altura FIXA (de -60 a -300, 240 px) e não acompanhava a janela — por
-- isso aumentar `HEIGHT` na rodada anterior não deu um pixel a mais de lista. A altura agora é
-- DERIVADA do card mais alto, que é o de quatro campos, e o resto da janela desce junto.
local CARDS_VISIVEIS = 3
-- O card de QUATRO CAMPOS, sem a faixa de aviso — e a escolha é deliberada. Com a faixa ele mede
-- 116, e dimensionar a janela por ele a deixaria 72 px mais alta **para todo mundo, o tempo
-- todo**, por causa de um estado que é erro e é para durar pouco. Com peca perdida em todos os
-- três conjuntos, a lista rola um pouco; e o certo é o jogador consertar, não a janela crescer.
-- A altura do bloco de campos e o MAIOR entre as linhas e o icone: com um campo so, as linhas
-- medem 15 e o icone 32, e sem este maximo ele vazaria o card.
local function FieldsHeight(n)
    return math.max(CARD_LINE * n, CARD_ICON)
end
local CARD_TOP = CARD_PAD + CARD_NAME_INK + CARD_NAME_GAP   -- onde o bloco de campos comeca
local CARD_MAX = CARD_TOP + FieldsHeight(4) + CARD_PAD
local LIST_TOP = -60
local LIST_H = CARD_MAX * CARDS_VISIVEIS + ROW_SPACING * (CARDS_VISIVEIS - 1) + 6  -- 6 = 3+3 do inset
local LIST_BOTTOM = LIST_TOP - LIST_H
-- A faixa de Avisos começa logo abaixo do inset, com a mesma folga de 4 que ela sempre teve.
local WARN_STRIP_Y = LIST_BOTTOM - 4

-- A conta fechada da janela, herdada da versão anterior e agora ancorada na lista:
-- faixa de Avisos (142 de conteúdo) + o rodapé de 26 que o `ButtonFrameTemplate` reserva,
-- mais os 4 de folga que a janela sempre teve.
local WARN_STRIP_H = 130
local TEMPLATE_FOOTER = 26
HEIGHT = -WARN_STRIP_Y + WARN_STRIP_H + TEMPLATE_FOOTER + 4
local FIELD_W = 200           -- combos (o dropdown de loadout de talentos usa 200)
local NAME_W = 211            -- EditBox: a arte termina em 500, alinhada com a dos combos
local GROUP_STEP = 50         -- rótulo (15) + combo (25) + respiro (10)
local ATTIC_Y = -30           -- faixa entre o título e o inset
local CHILD_INDENT = 15       -- recuo de opção filha (`Blizzard_SettingControls.lua:1`)

local frame, editor, selection

-- O conjunto em edição, guardado AQUI e não perguntado ao ScrollBox.
--
-- Dois motivos, os dois descobertos no primeiro teste in-game:
--
--   1. `SelectionBehaviorMixin:GetSelectedElementData()` devolve uma **LISTA**, não um
--      elemento (`ScrollUtil.lua:434`). Uma lista vazia é VERDADEIRA em Lua, então o editor
--      achava que havia um conjunto selecionado — um conjunto sem spec, sem talentos e sem
--      itens. Era isso o "combo de talentos não traz nada": sem spec, `GetLoadouts(nil)`
--      devolve lista vazia. E era isso o "a deleção não funcionou": `UI.Delete` procurava
--      uma tabela vazia na lista e não achava.
--   2. `SetDataProvider` **apaga a seleção** (`OnScrollBoxDataProviderReassigned`,
--      `ScrollUtil.lua:413`). Sem guardar por fora, qualquer troca de equipamento no jogo
--      redesenharia a lista e jogaria a seleção de volta para o primeiro conjunto.
local current

--------------------------------------------------------------------------------
local function Presets()
    return ns.db and ns.db.presets or {}
end

---Texto de apoio da linha: "Gélido · SBA ST · Frost". Só entra o que o conjunto define — um
---conjunto que não mexe em talentos não deve dar a entender que mexe.
---As linhas do card, cada uma com rótulo próprio, na ordem em que a troca acontece.
---
---Só entra o que o conjunto define — mesma regra do painel de progresso. Um conjunto só de
---itens mostra uma linha, e não quatro, das quais três diriam "(nenhum)".
local function CardLines(preset)
    local linhas = {}

    local spec = ns.Data.GetSpecByIndex(preset.spec)
    if spec then
        linhas[#linhas + 1] = { L["Specialization"], spec.name }
    end
    if preset.talent then
        linhas[#linhas + 1] = { L["Talents"],
            ns.Data.LoadoutName(spec and spec.id, preset.talent) or ("#" .. preset.talent) }
    end
    if preset.gear then
        linhas[#linhas + 1] = { L["Gear"],
            ns.Data.GearSetName(preset.gear) or ("#" .. preset.gear) }
    end
    if preset.transmog then
        linhas[#linhas + 1] = { L["Appearance"],
            ns.Data.OutfitName(preset.transmog) or ("#" .. preset.transmog) }
    end

    return linhas
end

---Quanto este card mede. A lista pergunta isto por elemento, e não uma altura fixa para todos.
local function CardHeight(preset)
    local n = #CardLines(preset)
    local altura = CARD_TOP + FieldsHeight(n) + CARD_PAD
    if preset.gear and ns.Data.GearSetProblem(preset.gear) then
        altura = altura + CARD_WARN
    end
    return altura
end

local function Subtitle(preset)
    local parts = {}

    local spec = ns.Data.GetSpecByIndex(preset.spec)
    if spec then parts[#parts + 1] = spec.name end

    if preset.talent then
        parts[#parts + 1] = ns.Data.LoadoutName(spec and spec.id, preset.talent)
            or ("#" .. preset.talent)
    end
    if preset.gear then
        parts[#parts + 1] = ns.Data.GearSetName(preset.gear) or ("#" .. preset.gear)
    end
    if preset.transmog then
        parts[#parts + 1] = ns.Data.OutfitName(preset.transmog) or ("#" .. preset.transmog)
    end

    return table.concat(parts, "  ·  ")
end

--------------------------------------------------------------------------------
-- A linha da lista
--------------------------------------------------------------------------------
---Monta a linha uma vez. O ScrollBox reaproveita o mesmo frame para dados diferentes, então
---tudo que depende do conjunto vai em `Fill`, não aqui.
local function BuildRow(row)
    if row.built then return end
    row.built = true

    -- A altura real vem de `CardHeight`, por elemento; esta é só a de partida.
    row:SetHeight(CARD_PAD * 2 + CARD_NAME_INK + CARD_LINE)

    -- Sem fundo próprio: quem dá o fundo é o mármore do inset. A linha só se pinta quando
    -- está sob o mouse ou selecionada — o padrão do painel de Opções do jogo.
    --
    -- Os alfas antigos (0.12 na seleção, 0.07 no hover) eram 3 a 6× mais fracos que o nativo
    -- e sem `ADD`: era por isso que a seleção não aparecia. Estas duas texturas e estes
    -- números são copiados do `GearSetButtonTemplate`, que é a lista de conjuntos de itens
    -- da própria Blizzard. `TexCoord 0.2..0.8` corta as pontas para esticar sem deformar.
    row.selected = row:CreateTexture(nil, "OVERLAY")
    row.selected:SetAllPoints()
    row.selected:SetTexture("Interface\\FriendsFrame\\UI-FriendsFrame-HighlightBar")
    row.selected:SetTexCoord(0.2, 0.8, 0, 1)
    row.selected:SetBlendMode("ADD")
    row.selected:SetAlpha(0.4)
    row.selected:Hide()

    row:SetHighlightTexture("Interface\\FriendsFrame\\UI-FriendsFrame-HighlightBar-Blue")
    local highlight = row:GetHighlightTexture()
    if highlight then
        highlight:SetTexCoord(0.2, 0.8, 0, 1)
        highlight:SetBlendMode("ADD")
        highlight:SetAlpha(0.4)
    end

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(CARD_ICON, CARD_ICON)
    row.icon:SetPoint("TOPLEFT", 6, -CARD_TOP)   -- reancorado em `FillRow`, com o n de campos
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.name:SetPoint("TOPLEFT", 8, -CARD_PAD)
    -- O titulo para antes do botao, e por isso ele nao usa `CARD_TEXT_W`: aqui o limite nao e
    -- de leitura, e de colisao.
    row.name:SetPoint("RIGHT", row, "RIGHT", -86, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    -- UMA LINHA POR CAMPO, cada uma com rótulo. Quatro vagas fixas porque são quatro campos
    -- possíveis; as que sobram ficam escondidas, e a ALTURA do card é que acompanha (`CardHeight`).
    row.lines = {}
    for i = 1, 4 do
        local fs = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        fs:SetPoint("TOPLEFT", CARD_LEFT, -(CARD_TOP + CARD_LINE * (i - 1)))
        fs:SetWidth(CARD_TEXT_W)
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(false)
        row.lines[i] = fs
    end

    -- A FAIXA DO AVISO. Vermelho sozinho, num texto de 11pt no meio de outros textos de 11pt,
    -- é sinal fraco demais — e a skill deste projeto é explícita: destaque se faz somando sinais
    -- fracos. Aqui são três: placa vermelha atrás, o "!" e a cor do texto.
    row.warn = CreateFrame("Frame", nil, row)
    row.warn:SetHeight(CARD_WARN - 2)
    row.warn:SetPoint("LEFT", CARD_LEFT, 0)
    row.warn:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    row.warn.bg = row.warn:CreateTexture(nil, "BACKGROUND")
    row.warn.bg:SetAllPoints()
    row.warn.bg:SetColorTexture(0.75, 0.15, 0.15, 0.20)

    row.warn.text = row.warn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.warn.text:SetPoint("LEFT", 6, 0)
    row.warn.text:SetJustifyH("LEFT")
    row.warn.text:SetWordWrap(false)
    row.warn.text:SetTextColor(1, 0.45, 0.42)

    -- O CONSERTO TEM BOTÃO PRÓPRIO, e não toma o lugar do Carregar. O usuário foi explícito
    -- (*"se tiver com erro de equipamentos, o botão de carregar fica indisponível para trocar"*),
    -- e é a mesma regra que ele já tinha dado para a restrição de especialização: botão que
    -- aceita clique e depois responde "não deu" é pior que botão apagado.
    row.fix = CreateFrame("Button", nil, row.warn, "UIPanelButtonTemplate")
    row.fix:SetSize(112, 20)
    row.fix:SetPoint("RIGHT", -2, 0)
    row.fix:SetScript("OnClick", function(self)
        local preset = row.preset
        if self.action == "save" then
            local problema = preset and preset.gear and ns.Data.GearSetProblem(preset.gear)
            if problema and problema.consertavel and ns.Data.SaveGearSet(preset.gear) then
                ns.Print(format(L["%s updated with what you are wearing."], problema.nome or "?"))
            end
            UI.Refresh()
        else
            ns.Data.OpenEquipmentManager()
        end
    end)
    row.warn:Hide()

    -- O botão e o ✓ dividem o mesmo slot: a linha não reflui quando o conjunto passa a
    -- estar aplicado, porque o texto reserva os 86px dos dois jeitos.
    -- BOTÃO SEGURO, e não por capricho: **trocar de conjunto de aparência é protegido**. As duas
    -- funções que fazem isso (`ChangeToOutfit` e `ChangeDisplayedOutfit`) não respondem a código
    -- de addon — devolvem sucesso e não fazem nada, que foi o "não troca e não gera nenhum erro"
    -- relatado três vezes. O patch 12.0.5 adicionou uma ação segura `"outfit"` justamente por
    -- isso, e é o que o único addon instalado que troca aparência usa
    -- (`EnhanceQoLQuickActions/Runtime.lua:4544,4593-4595`).
    --
    -- Então quem troca a aparência é o CLIQUE DO JOGADOR neste botão, e não o nosso código. Os
    -- outros três passos (spec, talentos, itens) continuam nossos e rodam no `PostClick`.
    --
    -- `PostClick`, e não `OnClick`: num botão seguro o `OnClick` roda dentro do caminho protegido
    -- e o que fizermos ali contamina o resto. O `PostClick` roda depois, fora dele.
    row.load = CreateFrame("Button", nil, row,
        "UIPanelButtonTemplate, SecureActionButtonTemplate")
    row.load:SetSize(74, 22)
    -- NA LINHA DO ICONE: e a unica faixa do card sem texto, e assim o botao para de disputar
    -- altura com o titulo. De quebra, ele fica no canto onde o olho ja procura acao.
    row.load:SetPoint("RIGHT", -6, 0)
    row.load:SetText(L["Load"])
    row.load:RegisterForClicks("AnyUp")
    row.load:SetAttribute("useOnKeyDown", false)
    row.load:SetScript("PostClick", function(self)
        UI.Load(self:GetParent().preset)
    end)

    -- BOTÃO APAGADO TEM QUE DIZER POR QUÊ, senão ele é só um botão quebrado. O motivo vem do
    -- jogo, já traduzido (`CanPlayerUseTalentSpecUI` devolve `canUse, failureReason`).
    row.load:SetScript("OnEnter", function(self)
        if not self.blockedReason then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["Load"], 1, 1, 1)
        GameTooltip:AddLine(self.blockedReason, 1, 0.5, 0.4, true)
        GameTooltip:Show()
    end)
    row.load:SetScript("OnLeave", GameTooltip_Hide)

    row.check = row:CreateTexture(nil, "OVERLAY")
    row.check:SetSize(16, 16)
    row.check:SetPoint("RIGHT", -8, 0)
    row.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    row.check:Hide()

    -- O CLIQUE DA LINHA. Ele não existia: eu troquei o `OnClick` manual pelo
    -- `AddSelectionBehavior` achando que o comportamento também capturava o clique. Ele só
    -- gerencia o ESTADO da seleção — quem seleciona é quem clica. Era o "não consigo clicar
    -- em outros conjuntos".
    row:RegisterForClicks("LeftButtonUp")
    row:SetScript("OnClick", function(self)
        if selection and self.GetElementData then
            selection:Select(self)
        end
    end)

    row:SetScript("OnEnter", function(self)
        if not self.preset then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.preset.name ~= "" and self.preset.name or L["Unnamed"], 1, 1, 1)
        GameTooltip:AddLine(Subtitle(self.preset), 0.7, 0.7, 0.7, true)

        -- O PORQUÊ DO VERMELHO. Sem esta linha a pessoa vê "falta 1 item" e conclui a coisa
        -- errada — que a troca vai ficar incompleta. O estrago real é outro: o espaço fica com
        -- a peça que já estava, que pode ser a do papel anterior.
        local problema = self.preset.gear and ns.Data.GearSetProblem(self.preset.gear)
        if problema then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(format(L["%s is missing %d item(s): the slot keeps what you are wearing, which may be wrong. Save the set first."],
                problema.nome or "?", problema.perdidas), 1, 0.35, 0.35, true)
            if problema.slots then
                GameTooltip:AddLine(table.concat(problema.slots, ", "), 0.8, 0.6, 0.6, true)
            end
            GameTooltip:AddLine(problema.consertavel
                and L["You are already wearing the rest of it — use /rs fix to update the set."]
                or L["Open the equipment manager, fix the set and save it, then switch."],
                0.7, 0.7, 0.7, true)
        end

        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", GameTooltip_Hide)
end

---Arma (ou desarma) a ação segura de aparência num botão.
---
---`action = "change"` e não `"toggle"`: em `SECURE_ACTIONS.outfit` o `"toggle"` vira
---`allowRemoveOutfit = true`, e aí pedir a aparência que já está posta é tratado como **limpar**
---(`SlashCommands.lua:1714`) — carregar duas vezes o mesmo conjunto TIRARIA a roupa na segunda.
---
---EM COMBATE NÃO SE MEXE em atributo de frame seguro. Sair sem fazer nada é o certo: o atributo
---que já estava lá continua valendo, e `Data.Apply` já recusa aplicar em combate de todo jeito.
local function ArmOutfit(button, preset)
    if InCombatLockdown() then return end

    -- (!) CONJUNTO QUEBRADO NÃO ARMA A AÇÃO SEGURA. A ação `outfit` roda DENTRO do clique, antes
    -- de qualquer Lua nosso — então recusar a troca no `Data.Apply` chegaria tarde para ela, e o
    -- jogador ficaria com a roupa trocada e nada mais. Desarmar aqui é o único ponto em que dá
    -- para impedir a aparência de ir sozinha.
    local quebrado = preset and preset.gear and ns.Data.GearSetProblem(preset.gear)

    local index = not quebrado and preset and preset.transmog
        and ns.Data.OutfitIndex(preset.transmog)
    if index then
        button:SetAttribute("type", "outfit")
        button:SetAttribute("outfit-index", index)
        button:SetAttribute("action", "change")
    else
        -- Sem aparência no conjunto (ou a aparência foi apagada do jogo): o botão volta a ser um
        -- botão comum. Deixar `type` armado com índice nulo faria o clique cair no ramo de
        -- `SECURE_ACTIONS.outfit` e não fazer nada, silenciosamente.
        button:SetAttribute("type", nil)
        button:SetAttribute("outfit-index", nil)
        button:SetAttribute("action", nil)
    end
end

---Preenche a linha com um conjunto.
local function FillRow(row, preset)
    BuildRow(row)
    row.preset = preset
    ArmOutfit(row.load, preset)

    row.name:SetText(preset.name ~= "" and preset.name or L["Unnamed"])

    local linhas = CardLines(preset)
    for i, fs in ipairs(row.lines) do
        local linha = linhas[i]
        fs:SetShown(linha ~= nil)
        if linha then
            -- RÓTULO e VALOR na mesma linha, com o rótulo apagado: o olho varre os valores na
            -- vertical e só lê o rótulo quando precisa. Dois brilhos, nenhuma cor nova.
            fs:SetText("|cff9a9a9e" .. linha[1] .. ":|r  " .. (linha[2] or "?"))
        end
    end
    -- O ICONE CENTRALIZADO NO BLOCO DE CAMPOS: com um campo so ele ficaria pendurado no topo.
    local blocoH = FieldsHeight(#linhas)
    row.icon:ClearAllPoints()
    row.icon:SetPoint("TOPLEFT", 6, -(CARD_TOP + math.floor((blocoH - CARD_ICON) / 2)))

    row:SetHeight(CardHeight(preset))

    local _, icon = ns.Data.GearSetName(preset.gear)
    row.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")

    -- UM canal por fato: a barra dourada diz "selecionado", o slot do botão diz "aplicado".
    -- A versão anterior também tingia o nome, e dourado-contra-quase-branco é distinção que
    -- ninguém lê — dois sinais para o mesmo fato brigando com a barra de seleção.
    -- O conjunto quebrado se anuncia NA LINHA, antes de qualquer clique: é o mesmo sinal que o
    -- gerenciador de equipamento do jogo dá (nome em vermelho), e é o aviso que o usuário pediu
    -- — *"a gente consegue antes de trocar, avisar isso"*.
    -- A FAIXA DO AVISO, ancorada abaixo da última linha que apareceu.
    local problema = preset.gear and ns.Data.GearSetProblem(preset.gear)
    row.warn:SetShown(problema ~= nil)
    if problema then
        row.warn:ClearAllPoints()
        row.warn:SetPoint("LEFT", CARD_LEFT, 0)
        row.warn:SetPoint("RIGHT", row, "RIGHT", -6, 0)
        row.warn:SetPoint("TOP", row, "TOP", 0, -(CARD_TOP + FieldsHeight(#linhas) + 2))
        row.warn.text:SetText("|cffff5a52!|r  " .. format(L["%s: %d item(s) missing"],
            problema.nome or "?", problema.perdidas))
        row.fix.action = ns.Data.GearFixAction(preset)
        row.fix:SetText(row.fix.action == "save" and L["Save set"] or L["Equipment Manager"])
    end

    local loaded = ns.Data.IsLoaded(preset)
    row.check:SetShown(loaded)
    row.load:SetShown(not loaded)

    -- BOTÃO DESABILITADO QUANDO O JOGO NÃO DEIXA, e a ideia é do usuário: *"se houver isso, tem
    -- que desabilitar os botões de carregar preset até que possa ser feito"*. Ele está certo —
    -- botão que aceita clique e depois responde "não deu" é pior que botão apagado.
    --
    -- SÓ VALE PARA CONJUNTO QUE TROCA DE SPEC. Um conjunto que só mexe em itens não tem por que
    -- ficar bloqueado por uma restrição de especialização, e desabilitar todos seria punir o
    -- inocente — a regra é a MESMA que o passo aplica, e por isso as duas não podem divergir.
    -- COM PEÇA PERDIDA, CARREGAR FICA APAGADO. A corrente recusa de qualquer jeito, e a regra
    -- é a mesma que já vale para a restrição de especialização: botão que aceita clique e depois
    -- responde "não deu" é pior que botão apagado. Quem age é o botão da faixa vermelha.
    -- Os dois motivos de apagar o botão saem da MESMA função (`Data.LoadBlockedReason`), que
    -- é onde o harness alcança. Aqui sobra o desenho: apagar e guardar a frase da dica.
    local motivo = ns.Data.LoadBlockedReason(preset)
    row.load:SetEnabled(motivo == nil)
    row.load.blockedReason = motivo

    row.selected:SetShown(selection ~= nil and selection:IsElementDataSelected(preset))
end

--------------------------------------------------------------------------------
-- Os campos do editor
--------------------------------------------------------------------------------
---Rótulo + combo num CONTÊINER. Esconder o grupo esconde os dois — é o que impede o rótulo
---órfão de voltar no próximo campo que alguém acrescentar.
---
---O rótulo assenta pelo rodapé no topo do combo, +3: assim ele não depende do corpo da fonte.
local function Group(parent, labelText, yTop, items, get, set)
    local group = CreateFrame("Frame", nil, parent)
    group:SetSize(216, 40)
    group:SetPoint("TOPLEFT", parent, "TOPLEFT", COL_X, yTop)

    -- +8 compensa o transbordo da arte do combo, para ela cair exatamente na coluna.
    local dd = CreateFrame("DropdownButton", nil, group, "WowStyle1DropdownTemplate")
    dd:SetSize(FIELD_W, 25)
    dd:SetPoint("BOTTOMLEFT", group, "BOTTOMLEFT", 8, 0)

    local label = group:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    label:SetPoint("BOTTOMLEFT", dd, "TOPLEFT", 3, 3)
    label:SetJustifyH("LEFT")
    label:SetText(labelText)

    ---Regenera o menu a partir do estado atual.
    ---
    ---`SetDefaultText` é só para "nada selecionado" — a marca do item escolhido sai de graça
    ---do `IsSelected` do `CreateRadio`. A versão anterior usava o default como "texto do
    ---selecionado", que é o que o comentário da própria Blizzard desaconselha.
    function group.Sync()
        local list = items()

        dd:SetupMenu(function(_, root)
            root:CreateButton(L["(none)"], function() set(nil); UI.AfterEdit() end)
            if #list > 0 then root:CreateDivider() end

            for _, item in ipairs(list) do
                local entry = root:CreateRadio(item.text,
                    function() return get() == item.value end,
                    function() set(item.value); UI.AfterEdit() end,
                    item.value)

                -- O conjunto de itens já tem ícone; mostrá-lo no menu custa cinco linhas e
                -- é o que faz escolher "Frost" sem ler.
                if item.icon and entry.AddInitializer then
                    entry:AddInitializer(function(button)
                        local tex = button:AttachTexture()
                        tex:SetSize(19, 19)
                        tex:SetPoint("LEFT")
                        tex:SetTexture(item.icon)
                        if button.fontString then
                            button.fontString:SetPoint("LEFT", tex, "RIGHT", 3, 0)
                        end
                    end)
                end
            end

            -- Sem nada para escolher, o combo fica apagado em vez de abrir um menu de um
            -- item só — o caso real de uma spec sem loadout salvo.
            if root.HasElements then dd:SetEnabled(root:HasElements()) end
        end)

        local current, text = get(), nil
        for _, item in ipairs(list) do
            if item.value == current then text = item.text end
        end
        dd:SetDefaultText(text or L["(none)"])
    end

    group.dropdown = dd
    return group
end

local function BuildEditor()
    editor = {}

    -- O nome NÃO tem rótulo separado: a instrução mora dentro da caixa. Era metade do
    -- "texto colado", resolvida pela raiz em vez de por um `SetShown`.
    editor.name = CreateFrame("EditBox", nil, frame, "InputBoxInstructionsTemplate")
    editor.name:SetSize(NAME_W, 22)
    editor.name:SetPoint("TOPLEFT", frame, "TOPLEFT", COL_X + 5, -60)
    editor.name:SetAutoFocus(false)
    editor.name:SetMaxLetters(31)
    if editor.name.Instructions then
        -- Sem isto o texto de instrução nasce 16px à direita do texto digitado.
        editor.name.Instructions:SetAllPoints()
        editor.name.Instructions:SetText(L["Preset name"])
    end
    editor.name:SetScript("OnEscapePressed", editor.name.ClearFocus)
    editor.name:SetScript("OnEnterPressed", editor.name.ClearFocus)
    -- Sair da caixa salva. O botão "Salvar" foi embora: os combos já escrevem direto no
    -- conjunto, então ele só confirmava o nome — e sua existência levantava a dúvida "a
    -- escolha do combo salvou?".
    editor.name:SetScript("OnEditFocusLost", function() UI.SaveName() end)

    editor.divider = frame:CreateTexture(nil, "ARTWORK")
    editor.divider:SetSize(216, 1)
    editor.divider:SetPoint("TOPLEFT", frame, "TOPLEFT", COL_X, -98)
    if not ns.SetAtlasSafe or not ns.SetAtlasSafe(editor.divider, "Options_HorizontalDivider") then
        editor.divider:SetColorTexture(1, 1, 1, 0.12)
    end

    local function Current() return UI.Selected() end

    editor.spec = Group(frame, L["Specialization"], -108,
        function()
            local out = {}
            for _, s in ipairs(ns.Data.GetSpecs()) do
                out[#out + 1] = { value = s.index, text = s.name, icon = s.icon }
            end
            return out
        end,
        function() local p = Current(); return p and p.spec end,
        -- Trocar a spec zera o loadout: um loadout de Gélido não existe em Profano, e
        -- oferecê-lo seria oferecer o impossível.
        function(v) local p = Current(); if p then p.spec = v; p.talent = nil end end)

    editor.talent = Group(frame, L["Talents"], -108 - GROUP_STEP,
        function()
            local p = Current()
            local spec = p and ns.Data.GetSpecByIndex(p.spec)
            local out = {}
            for _, l in ipairs(ns.Data.GetLoadouts(spec and spec.id)) do
                out[#out + 1] = { value = l.configID, text = l.name }
            end
            return out
        end,
        function() local p = Current(); return p and p.talent end,
        function(v) local p = Current(); if p then p.talent = v end end)

    editor.gear = Group(frame, L["Gear"], -108 - GROUP_STEP * 2,
        function()
            local out = {}
            for _, s in ipairs(ns.Data.GetGearSets()) do
                out[#out + 1] = { value = s.setID, text = s.name, icon = s.icon }
            end
            return out
        end,
        function() local p = Current(); return p and p.gear end,
        function(v) local p = Current(); if p then p.gear = v end end)

    -- Aparência é OPCIONAL de propósito: deixar em "(nenhum)" faz o conjunto não mexer na
    -- roupa. Quem não usa transmog nem percebe que o campo existe.
    editor.transmog = Group(frame, L["Appearance"], -108 - GROUP_STEP * 3,
        function()
            local out = {}
            for _, o in ipairs(ns.Data.GetOutfits()) do
                out[#out + 1] = { value = o.outfitID, text = o.name, icon = o.icon }
            end
            return out
        end,
        function() local p = Current(); return p and p.transmog end,
        function(v) local p = Current(); if p then p.transmog = v end end)
end

--------------------------------------------------------------------------------
-- O progresso da troca
--------------------------------------------------------------------------------
-- POR QUE ISTO EXISTE. O relato foi: *"quando clica para carregar, ele demora para iniciar o
-- 'cast', o usuário vai pensar que nada aconteceu"* — e o pedido junto, *"algo animado e bem
-- didático que o usuário entenda"* que a troca *"é um processo de troca por etapas"*.
--
-- **E não é uma barra de progresso.** A corrente não sabe quanto vai demorar: o passo da
-- especialização espera o servidor e reinsiste de 4 em 4 segundos, e o diário real mostrou a
-- mesma troca sendo aceita ora em 4, ora em 14 segundos. Barra que anda sozinha inventa uma
-- previsão que ninguém tem, e barra que trava no meio é pior que barra nenhuma. O que dá para
-- mostrar com honestidade — e é o que a pessoa quer saber — são quatro coisas verdadeiras a cada
-- quadro: **quais são as etapas**, **em qual delas estamos**, **quais já fecharam** e **há
-- quanto tempo**. As três primeiras vêm de `Data.GetProgress()`; a quarta é um relógio.
--
-- ONDE: na coluna da direita, no lugar do editor. Durante a troca o editor não é usável — mexer
-- no conjunto que está sendo aplicado é mudar o chão no meio do passo —, então o espaço está
-- livre. E é onde os campos do conjunto já moram: os rótulos aqui são **os mesmos** do editor
-- (`Especialização`, `Talentos`, `Itens`, `Aparência`) e **na mesma ordem**. Quem acabou de ler
-- aqueles nomes ao lado dos combos reconhece a lista sem precisar de legenda — é isso que torna
-- a tela didática, e não um texto explicando o que ela é.
--
-- E entram **só as etapas que o conjunto pede** (`Data.GetProgress` filtra): um conjunto só de
-- itens mostra uma linha, não quatro, das quais três diriam "nada a mudar".

local PROGRESS_ROW = 22       -- ritmo de LISTA (`Blizzard_CategoryList.xml:51` + `.lua:214`)
local PROGRESS_ICON = 16      -- o tamanho do ✓ nativo (`Blizzard_UIWidgetTemplateBase.xml:185`)
local PROGRESS_ICON_GAP = 5   -- ícone → rótulo pequeno (`Blizzard_AutoCompletePopupList.xml:32`,
                              -- que é ícone + `GameFontHighlightSmall`, o mesmo par daqui)
local PROGRESS_TITLE_GAP = 13 -- abaixo do título, como no cabeçalho de seção: bloco 45, título a
                              -- y=-16 e 16 de tinta ⇒ 45 − 16 − 16 (`Blizzard_SettingControls.xml:14,19`)
local PROGRESS_TITLE_INK = 16 -- `GameFontNormal` a 14pt, arredondado pela caixa da fonte
local PROGRESS_CLOCK_W = 70

-- QUANTO TEMPO O RESULTADO FICA NA TELA depois de a troca acabar. Sem esta pausa o painel some
-- no instante em que ele finalmente tem algo a dizer — qual passo foi pulado, qual não deu — e o
-- jogador ficaria só com a linha de status lá embaixo, que é justamente o aviso que *"mostra e
-- some, o usuário pode nem ver"*.
local PROGRESS_HOLD = 5

-- Um sinal por estado, e nenhum deles inventado: os três atlas foram conferidos na fonte do
-- 12.1.0 (`common-icon-checkmark` em 7 arquivos, `common-icon-redx` em 3, `common-icon-forwardarrow`
-- em 3). A skill do workspace é explícita quanto ao resto: cor de classe é vocabulário reservado,
-- então o destaque se faz somando **sinais fracos** — aqui, arte + brilho + a pulsação.
--
-- `skipped` NÃO É FALHA e não pode parecer uma: nada de ✗, nada de vermelho. Ele ganha o mesmo
-- ponto neutro de quem ainda não começou, mais a razão escrita no próprio rótulo.
-- Exportado em `ns.ProgressVisuals` logo abaixo: o painel flutuante (`Progress.lua`) desenha
-- os MESMOS estados, e duas tabelas de arte divergiriam na primeira mudança.
local PROGRESS_STATE = {
    pending = {                                     alpha = 0.40 },
    doing   = { atlas = "common-icon-forwardarrow", alpha = 1.00 },
    done    = { atlas = "common-icon-checkmark",    alpha = 0.85 },
    skipped = {                                     alpha = 0.45 },
    failed  = { atlas = "common-icon-redx",         alpha = 0.90 },
}

-- O painel flutuante (`Progress.lua`) desenha os MESMOS estados. Duas tabelas de arte
-- divergiriam na primeira mudança, então existe uma só e ela mora aqui.
ns.ProgressVisuals = PROGRESS_STATE
ns.PROGRESS_ROW = PROGRESS_ROW
ns.PROGRESS_ICON = PROGRESS_ICON
ns.PROGRESS_ICON_GAP = PROGRESS_ICON_GAP

---Fecha o painel e devolve a coluna ao editor.
local function ConcludeProgress(panel)
    if not panel:IsShown() then return end
    panel:Hide()
    for _, row in ipairs(panel.rows) do
        if row.__pulsing then
            row.pulse:Stop()
            row:SetAlpha(1)
            row.__pulsing = false
        end
    end
    UI.RefreshEditor()
end

---Monta o painel uma vez; quem escreve nele é `UI.RefreshProgress`.
local function BuildProgress()
    local panel = CreateFrame("Frame", nil, frame)
    panel:SetPoint("TOPLEFT", frame, "TOPLEFT", COL_X, -60)
    panel:SetPoint("RIGHT", frame, "RIGHT", -20, 0)
    panel:Hide()

    -- O relógio à direita do título. É o que responde *"aconteceu alguma coisa?"* antes de
    -- qualquer passo fechar: um número que anda de segundo em segundo prova que o addon está
    -- vivo, mesmo nos 4 segundos em que ele está de propósito esperando o jogo liberar.
    panel.clock = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    panel.clock:SetPoint("TOPRIGHT", 0, 0)
    panel.clock:SetWidth(PROGRESS_CLOCK_W)
    panel.clock:SetJustifyH("RIGHT")
    panel.clock:SetWordWrap(false)

    panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    panel.title:SetPoint("TOPLEFT", 0, 0)
    panel.title:SetPoint("RIGHT", panel.clock, "LEFT", -PROGRESS_ICON_GAP, 0)
    panel.title:SetJustifyH("LEFT")
    panel.title:SetWordWrap(false)

    panel.rows = {}
    for i = 1, 4 do
        local row = CreateFrame("Frame", nil, panel)
        row:SetHeight(PROGRESS_ROW)
        if i == 1 then
            row:SetPoint("TOPLEFT", panel.title, "BOTTOMLEFT", 0, -PROGRESS_TITLE_GAP)
        else
            row:SetPoint("TOPLEFT", panel.rows[i - 1], "BOTTOMLEFT", 0, 0)
        end
        row:SetPoint("RIGHT", panel, "RIGHT", 0, 0)

        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(PROGRESS_ICON, PROGRESS_ICON)
        row.icon:SetPoint("LEFT", 0, 0)

        -- O PONTO DE ESPERA. Nos estados sem arte (ainda não chegou a vez, e o pulado) a coluna
        -- do ícone não pode ficar vazia: buraco no meio de uma lista faz ela parecer quebrada, e
        -- o rótulo perde a margem que os outros três têm. Um ponto neutro segura a coluna, e ele
        -- some por baixo do ✓ ou do ✗ quando eles entram.
        row.dot = row:CreateTexture(nil, "ARTWORK")
        row.dot:SetSize(4, 4)
        row.dot:SetPoint("CENTER", row.icon, "CENTER", 0, 0)
        row.dot:SetColorTexture(1, 1, 1, 1)

        -- Largura por ancoragem nos dois lados, e não por `SetWidth` chutado: o rótulo tem que
        -- caber em alemão e russo, onde ele cresce sozinho.
        row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.label:SetPoint("LEFT", row.icon, "RIGHT", PROGRESS_ICON_GAP, 0)
        row.label:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        row.label:SetJustifyH("LEFT")
        row.label:SetWordWrap(false)

        -- A PULSAÇÃO, e ela é a única animação da tela. Serve para o caso "indeterminado": não
        -- se sabe quanto falta, então o que se anima é a presença do passo, não um avanço.
        -- Alfa e não rotação — pulsar não disputa atenção com nada, e não exige arte nova.
        row.pulse = row:CreateAnimationGroup()
        row.pulse:SetLooping("BOUNCE")
        local fade = row.pulse:CreateAnimation("Alpha")
        fade:SetFromAlpha(1)
        fade:SetToAlpha(0.4)
        fade:SetDuration(0.7)

        panel.rows[i] = row
    end

    panel:SetHeight(PROGRESS_ROW * 4 + PROGRESS_TITLE_GAP + PROGRESS_TITLE_INK)
    frame.progress = panel
end

---Redesenha o progresso. Roda no `OnUpdate` da janela, represado — o relógio é em segundos
---inteiros, então dez quadros por segundo já é folga.
function UI.RefreshProgress()
    if not frame or not frame.progress then return end
    local panel = frame.progress

    local passos, info = ns.Data.GetProgress()
    if not passos then
        ConcludeProgress(panel)     -- nunca houve troca nesta sessão
        return
    end

    -- AS DUAS TRANSIÇÕES. `info.live` diz se a troca está acontecendo AGORA; `panel.live` é o que
    -- a janela viu da última vez. A diferença entre os dois é o que marca começo e fim — e é o
    -- fim que precisa da pausa, para o resultado ser lido antes de o editor voltar.
    if info.live and not panel.live then
        panel.live, panel.holdUntil = true, nil
    elseif not info.live and panel.live then
        panel.live, panel.holdUntil = false, GetTime() + PROGRESS_HOLD
    end

    -- Retrato de uma troca que já terminou e já foi mostrada (ou que aconteceu com a janela
    -- fechada): ele não abre o painel. Progresso é sobre agora.
    if not info.live and (not panel.holdUntil or GetTime() >= panel.holdUntil) then
        panel.holdUntil = nil
        ConcludeProgress(panel)
        return
    end

    if not panel:IsShown() then
        panel:Show()
        UI.RefreshEditor()          -- a coluna passa a ser do progresso
    end

    -- A ALTURA ACOMPANHA QUANTAS ETAPAS O CONJUNTO PEDE. Reservar as quatro vagas sempre deixa
    -- um vazio embaixo do painel de um conjunto so de itens -- e espaco guardado para conteudo
    -- que nao existe e o que mais faz uma janela parecer quebrada.
    panel:SetHeight(PROGRESS_ROW * #passos + PROGRESS_TITLE_GAP + PROGRESS_TITLE_INK)

    panel.title:SetText(format(L["Switching to %s"],
        info.preset and info.preset.name or "?"))

    -- SÓ OS SEGUNDOS, e nada sobre tentativas.
    --
    -- Uma versão anterior trocava o relógio por "tentativa 2 de 8" enquanto o jogo recusava a
    -- troca de spec. O usuário pediu para tirar, e ele tem razão: o número de tentativas é
    -- mecânica interna do addon — o jogador não decide nada com ele, não pode acelerar nem
    -- interromper, e ver um contador subindo sugere um problema onde há só espera normal. O que
    -- ele precisa saber é que **algo está acontecendo**, e disso o relógio já dá conta sozinho.
    --
    -- A insistência continua registrada onde ela serve: no diário (`/rs log`).
    --
    -- E ele PARA quando a troca para — deixá-lo correndo durante a pausa faria o número contar o
    -- tempo de leitura como se fosse tempo de troca.
    if info.live then
        local secs = math.max(0, math.floor(GetTime() - (info.startedAt or 0)))
        panel.clock:SetText(secs .. "s")
    end

    for i, row in ipairs(panel.rows) do
        local passo = passos[i]
        row:SetShown(passo ~= nil)
        if passo then
            local visual = PROGRESS_STATE[passo.state] or PROGRESS_STATE.pending
            local temArte = visual.atlas and ns.SetAtlasSafe(row.icon, visual.atlas) or false

            row.icon:SetShown(temArte)
            row.icon:SetAlpha(visual.alpha)
            row.dot:SetShown(not temArte)
            row.dot:SetVertexColor(1, 1, 1, visual.alpha)

            -- O PULADO DIZ POR QUE FOI PULADO, no próprio rótulo. Sem isso ele fica igual a um
            -- passo que ainda não começou, e o jogador termina a troca sem saber se a aparência
            -- foi aplicada ou esquecida.
            row.label:SetText(passo.state == "skipped"
                and format(L["%s — nothing to change"], passo.label)
                or passo.label)
            row.label:SetAlpha(visual.alpha)

            -- A pulsação segue o passo em andamento, e só enquanto a troca está viva: ela é
            -- reancorada em vez de recriada, porque animação começada de novo a cada quadro não
            -- anima nada — pisca.
            local deve = passo.state == "doing" and info.live
            if deve and not row.__pulsing then
                row.pulse:Play()
                row.__pulsing = true
            elseif not deve and row.__pulsing then
                row.pulse:Stop()
                row:SetAlpha(1)
                row.__pulsing = false
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Estado vazio
--------------------------------------------------------------------------------
---Bloco centralizado. A Blizzard não tem tela de vazio com arte: em ~20 sistemas o padrão é
---uma FontString centralizada mais, quando há o que fazer, um botão.
---
---O texto responde à pergunta que o botão levanta ("vou ter que preencher tudo?"), em vez de
---descrever o produto. E a resposta é verdade no código: `UI.New` já nasce preenchido.
local function BuildEmptyState()
    local empty = CreateFrame("Frame", nil, frame)
    empty:SetAllPoints()

    empty.title = empty:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    empty.title:SetPoint("CENTER", frame, "CENTER", 0, 55)
    empty.title:SetText(L["No presets yet"])

    empty.body = empty:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    empty.body:SetPoint("TOP", empty.title, "BOTTOM", 0, -10)
    empty.body:SetWidth(320)
    empty.body:SetJustifyH("CENTER")
    empty.body:SetText(L["The first one starts with the spec, talents and gear you have right now."])

    empty.button = CreateFrame("Button", nil, empty, "UIPanelButtonTemplate")
    empty.button:SetSize(180, 22)
    empty.button:SetPoint("TOP", empty.body, "BOTTOM", 0, -20)
    empty.button:SetText(L["Create the first preset"])
    empty.button:SetScript("OnClick", function() UI.New() end)

    frame.emptyState = empty
end

--------------------------------------------------------------------------------
---A seção "Avisos", no rodapé e em largura total.
---
---Ela fica visível SEMPRE — inclusive com zero conjuntos, que é o caso que a motivou. Os dois
---avisos são o que o addon faz por quem nunca vai criar um conjunto; deixá-los só em
---`/rs warn` e `/rs ready` é o mesmo que não tê-los, porque ninguém descobre comando.
---
---Ligados por padrão, e por isso o rótulo é afirmativo: a caixa marcada descreve o que já
---está acontecendo, não uma promessa.
local function BuildToggles()
    local strip = CreateFrame("Frame", nil, frame)
    strip:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, WARN_STRIP_Y)
    strip:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -14, WARN_STRIP_Y)
    -- 142 = a última caixa termina em −136, mais 6 de respiro. Era 86 com duas caixas, 118 com
    -- a sub-opção de modo guerra (12/09) e 142 com a do convite de fila (18/09). Altura fixa que
    -- não acompanha o conteúdo é o defeito que a faixa transbordando teria produzido em silêncio.
    -- A faixa encolheu de 142 para 106 quando as quatro caixas viraram duas colunas de duas:
    -- titulo (-10, 16 de tinta) + titulo de coluna (-34, 14) + duas caixas de 24 a partir de
    -- -52 => a ultima termina em -100, mais 6 de respiro. O numero vive em `WARN_STRIP_H`,
    -- porque a altura da janela sai dele.
    strip:SetHeight(WARN_STRIP_H)

    strip.divider = strip:CreateTexture(nil, "ARTWORK")
    strip.divider:SetPoint("TOPLEFT", 0, 0)
    strip.divider:SetPoint("TOPRIGHT", 0, 0)
    strip.divider:SetHeight(1)
    if not ns.SetAtlasSafe or not ns.SetAtlasSafe(strip.divider, "Options_HorizontalDivider") then
        strip.divider:SetColorTexture(1, 1, 1, 0.12)
    end

    strip.title = strip:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    strip.title:SetPoint("TOPLEFT", 0, -10)
    strip.title:SetText(L["Warnings"])
    strip.title:SetTextColor(1, 0.82, 0)

    -- O "?" ao lado do título, e não em cada caixa: o que precisa ser explicado é o RECURSO
    -- (que os avisos funcionam sem conjunto, e quando eles calam), não cada linha isolada.
    --
    -- `Interface\common\help-i` é a arte que a Blizzard usa no HelpPlate
    -- (`Blizzard_HelpPlate.xml:382`). Caminho de textura falha em SILÊNCIO, então ele passa
    -- por `ns.FirstIcon`, que consulta `GetFileIDFromPath` — e o último recurso é desenhar um
    -- "?" de texto, que não tem como não aparecer.
    local help = CreateFrame("Button", nil, strip)
    help:SetSize(18, 18)
    help:SetPoint("LEFT", strip.title, "RIGHT", 6, 0)

    local art, verified = ns.FirstIcon({ "Interface\\common\\help-i" })
    if verified then
        help.icon = help:CreateTexture(nil, "ARTWORK")
        help.icon:SetAllPoints()
        help.icon:SetTexture(art)
    else
        help.label = help:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        help.label:SetAllPoints()
        help.label:SetText("?")
        help.label:SetTextColor(1, 0.82, 0)
    end
    help:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight")

    help:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["Warnings"], 1, 1, 1)
        GameTooltip:AddLine(L["These two work without any preset — they are what the addon does on the day you install it."],
            0.8, 0.8, 0.8, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["Wrong gear:"], 1, 0.82, 0)
        GameTooltip:AddLine(L["In an arena or battleground it flags every slot WITHOUT the PvP item level line; in a dungeon or raid, every slot WITH it. It names the slots, and offers to load a preset if you have one that fits."],
            0.8, 0.8, 0.8, true)
        GameTooltip:AddLine(L["In the open world with War Mode on it stays quiet unless you tick the second box: out there most of the time is questing, not fighting players."],
            0.8, 0.8, 0.8, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["Ready check:"], 1, 0.82, 0)
        GameTooltip:AddLine(L["When the leader starts one, it prints your specialization, talent loadout and gear set — so you can confirm before the pull."],
            0.8, 0.8, 0.8, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["PvP queue pop:"], 1, 0.82, 0)
        GameTooltip:AddLine(L["When the arena or battleground invite shows up, it prints the same summary — the last moment when you can still fix the build."],
            0.8, 0.8, 0.8, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["It stays quiet in combat, once the gates are open, and whenever the reading is not reliable. Type /rs gear to see what it reads on each slot."],
            0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end)
    help:SetScript("OnLeave", GameTooltip_Hide)

    ---Uma caixa com rótulo próprio. `UICheckButtonTemplate` tem um `.text` embutido, mas ele
    ---depende de o frame ter nome — e frame nomeado vira global. FontString própria evita as
    ---duas coisas.
    local function Toggle(y, label, key, indent)
        local box = CreateFrame("CheckButton", nil, strip, "UICheckButtonTemplate")
        box:SetSize(24, 24)
        box:SetPoint("TOPLEFT", indent or 0, y)

        local text = strip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        text:SetPoint("LEFT", box, "RIGHT", 2, 0)
        text:SetText(label)

        box:SetScript("OnClick", function(self)
            ns.db[key] = self:GetChecked() and true or false
            if UI.RefreshToggles then UI.RefreshToggles() end
        end)

        -- A DICA DIZ POR QUE ESTA APAGADA. Sem isso a caixa cinza e so uma caixa quebrada.
        box:SetScript("OnEnter", function(self)
            if self:IsEnabled() then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(label, 1, 1, 1)
            GameTooltip:AddLine(L["Turn on the wrong gear warning first."], 1, 0.5, 0.4, true)
            GameTooltip:Show()
        end)
        box:SetScript("OnLeave", GameTooltip_Hide)

        box.key = key
        box.label = text
        return box
    end

    -- (!) DUAS COLUNAS, E OS TITULOS DIZEM A VERDADE SOBRE O QUE CADA UMA E (22/09).
    --
    -- O pedido foi *"de um lado avisos de PVE e do outro lado avisos de PVP"*. Ao conferir no
    -- `Alert.lua` o que cada caixa faz, a divisao PvE/PvP nao existe:
    --
    --   `warn`        dispara nos DOIS contextos (equipamento de PvP em masmorra, e o inverso)
    --   `readyCheck`  vale em qualquer grupo
    --   `warnWarMode` estende o de cima ao mundo aberto com Modo Guerra -- PvP
    --   `queuePop`    so campo de batalha e arena -- PvP
    --
    -- Ou seja: dois sao universais, dois sao de PvP, e **nenhum e so de PvE**. Uma coluna "PvE"
    -- nasceria vazia ou mentindo, e rotulo que mente e pior que coluna nenhuma. Entao os titulos
    -- sao os que o codigo sustenta, e a intencao do pedido -- ver de relance o que e especifico
    -- de PvP -- fica atendida do mesmo jeito.
    local COL2 = math.floor((WIDTH - 28) / 2)

    local function ColumnTitle(x, texto)
        local fs = strip:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("TOPLEFT", x, -34)
        fs:SetText(texto)
        fs:SetTextColor(0.75, 0.75, 0.78)
        return fs
    end

    strip.colPvE = ColumnTitle(0, L["PvE"])
    strip.colPvP = ColumnTitle(COL2, L["PvP"])

    -- AS DUAS COLUNAS SAO REAIS DESDE 0.35.0. Antes o aviso de equipamento era uma chave so para
    -- os dois conteudos, entao os titulos tinham que ser "Em qualquer conteudo" e "So em PvP" --
    -- honestos, mas nao era o que o usuario queria. Com a chave separada por contexto, PvE e PvP
    -- passam a ser colunas de verdade, cada uma com o seu aviso de equipamento.
    strip.warnPvE = Toggle(-52, L["Warn about wrong gear"], "warnPvE")
    strip.ready = Toggle(-76, L["Show my setup on Ready Check"], "readyCheck")

    strip.warnPvP = Toggle(-52, L["Warn about wrong gear"], "warnPvP", COL2)
    -- (!) A SUB-OPCAO VOLTOU A SER FILHA, e agora com a mae na MESMA coluna: o Modo Guerra e
    -- mundo aberto com PvP ligado, entao ele pertence a esta coluna e a este aviso. O recuo de
    -- 15 px volta a dizer a dependencia, e o estado apagado continua dizendo tambem -- os dois
    -- sinais somados, que e o que a skill deste projeto manda fazer.
    strip.warMode = Toggle(-76, L["Warn with War Mode on too"], "warnWarMode", COL2 + CHILD_INDENT)
    strip.queue = Toggle(-100, L["Show my setup when a PvP queue pops"], "queuePop", COL2)

    frame.toggles = strip
end

---Acerta o estado das caixas: marcada/desmarcada e, no caso da filha, apagada ou nao.
---
---(!) A DEPENDENCIA DEIXOU DE SER DESENHO E VIROU COMPORTAMENTO. Enquanto as duas moravam na
---mesma pilha, o recuo de 15 px dizia "esta depende da de cima". Em colunas diferentes o recuo
---nao diz mais nada, entao quem diz e o estado: com o aviso de equipamento desligado, a de Modo
---Guerra fica apagada, e a dica explica.
function UI.RefreshToggles()
    local strip = frame and frame.toggles
    if not strip then return end

    strip.warnPvE:SetChecked(ns.db.warnPvE ~= false)
    strip.warnPvP:SetChecked(ns.db.warnPvP ~= false)
    strip.ready:SetChecked(ns.db.readyCheck ~= false)
    strip.queue:SetChecked(ns.db.queuePop ~= false)

    -- `== true`, e nao `~= false`: esta nasce DESMARCADA, entao a ausencia de valor e "nao".
    -- Copiar o `~= false` das vizinhas a deixaria marcada em quem nunca a viu -- o oposto do
    -- que foi pedido em 12/09.
    strip.warMode:SetChecked(ns.db.warnWarMode == true)

    -- A filha depende do aviso de PvP, que e a mae dela agora (Modo Guerra e mundo com PvP).
    local ligado = ns.db.warnPvP ~= false
    if strip.warMode then
        strip.warMode:SetEnabled(ligado)
        if strip.warMode.label then
            strip.warMode.label:SetTextColor(ligado and 1 or 0.5, ligado and 1 or 0.5,
                ligado and 1 or 0.5)
        end
    end
end

local function Create()
    if frame then return frame end

    -- Herança de template só na criação.
    frame = CreateFrame("Frame", ADDON .. "Frame", UIParent, "ButtonFrameTemplate")
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("HIGH")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        ns.db.pos = { point = point, relPoint = relPoint, x = x, y = y }
    end)
    frame:Hide()

    if frame.SetTitle then frame:SetTitle(ADDON) end
    if frame.SetPortraitToAsset then
        frame:SetPortraitToAsset(ns.FirstIcon(ns.ICON_CANDIDATES))
    end
    tinsert(UISpecialFrames, frame:GetName())

    -- O inset do template cobre a largura toda; aqui ele passa a cobrir só a coluna da lista.
    -- A coluna direita fica sobre o fundo da janela de propósito: o mármore do inset é fundo
    -- de LISTA, e sob um formulário ele compete com a arte dos combos.
    if frame.Inset then
        frame.Inset:ClearAllPoints()
        frame.Inset:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, LIST_TOP)
        frame.Inset:SetPoint("BOTTOMRIGHT", frame, "TOPLEFT", 4 + LIST_W, LIST_BOTTOM)
    end
    local host = frame.Inset or frame

    -- Sem rótulo "Conjuntos": o inset já delimita a lista, e era justamente esse rótulo que
    -- estava embaixo do retrato.
    frame.list = CreateFrame("Frame", nil, host, "WowScrollBoxList")
    frame.listBar = CreateFrame("EventFrame", nil, host, "MinimalScrollBar")
    frame.listBar:SetPoint("TOPRIGHT", host, "TOPRIGHT", -3, -3)
    frame.listBar:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -3, 3)

    local view = CreateScrollBoxListLinearView(0, 0, 0, 0, ROW_SPACING)
    view:SetVirtualized(false)          -- 2 a 5 itens: cria todos, não recicla
    -- ALTURA POR ELEMENTO, e não uma para todos: cada card mede o que os campos dele pedem.
    view:SetElementExtentCalculator(function(_, preset)
        return CardHeight(preset)
    end)
    view:SetElementInitializer("Button", FillRow)
    ScrollUtil.InitScrollBoxListWithScrollBar(frame.list, frame.listBar, view)

    ScrollUtil.AddManagedScrollBarVisibilityBehavior(frame.list, frame.listBar,
        { CreateAnchor("TOPLEFT", host, "TOPLEFT", 3, -3),
          CreateAnchor("BOTTOMRIGHT", host, "BOTTOMRIGHT", -17, 3) },
        { CreateAnchor("TOPLEFT", host, "TOPLEFT", 3, -3),
          CreateAnchor("BOTTOMRIGHT", host, "BOTTOMRIGHT", -3, 3) })

    -- A seleção guarda a TABELA do conjunto, não o índice. Com índice, `table.remove` no
    -- Apagar deslocava tudo e a seleção passava a apontar para outro conjunto.
    selection = ScrollUtil.AddSelectionBehavior(frame.list)
    selection:RegisterCallback(SelectionBehaviorMixin.Event.OnSelectionChanged,
        function(_, elementData, isSelected)
            local row = frame.list:FindFrame(elementData)
            if row and row.selected then row.selected:SetShown(isSelected) end
            if isSelected then
                current = elementData
                UI.RefreshEditor()
            elseif current == elementData then
                current = nil
            end
        end, UI)

    -- Sótão: a faixa entre o título e o inset, à direita do retrato (x ≥ 58).
    frame.new = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.new:SetSize(140, 22)
    frame.new:SetPoint("TOPLEFT", frame, "TOPLEFT", 60, ATTIC_Y)
    frame.new:SetText("+ " .. L["New preset"])
    frame.new:SetScript("OnClick", function() UI.New() end)

    -- Rodapé: a banda que o template já reserva (y 4..26).
    frame.delete = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.delete:SetSize(100, 22)
    frame.delete:SetPoint("BOTTOMRIGHT", -6, 4)
    frame.delete:SetText(L["Delete"])
    frame.delete:SetScript("OnClick", function() UI.Delete() end)

    frame.status = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.status:SetPoint("BOTTOMLEFT", 10, 8)
    frame.status:SetPoint("RIGHT", frame.delete, "LEFT", -8, 0)
    frame.status:SetJustifyH("LEFT")
    frame.status:SetWordWrap(false)

    -- O RELÓGIO DA JANELA. É o único `OnUpdate` do addon, e ele só corre com a janela aberta —
    -- represado em 0,1 s porque o que ele desenha muda de segundo em segundo.
    --
    -- Ele fica na janela, e não no painel, de propósito: `OnUpdate` de frame escondido não roda,
    -- e o painel começa escondido. Preso nele, o progresso nunca apareceria sozinho.
    frame.__tick = 0
    frame:SetScript("OnUpdate", function(self, elapsed)
        self.__tick = self.__tick + (elapsed or 0)
        if self.__tick < 0.1 then return end
        self.__tick = 0
        UI.RefreshProgress()
    end)

    BuildEditor()
    BuildProgress()
    BuildEmptyState()
    BuildToggles()
    return frame
end

--------------------------------------------------------------------------------
---O conjunto em edição. É a TABELA do conjunto, não um índice — `table.remove` no Apagar
---desloca os índices, e um índice guardado passaria a apontar para outro conjunto.
---Acesso à lista, só para o harness poder disparar o clique de uma linha. Sem isto o teste
---que trava o bug "não consigo clicar em outros conjuntos" não teria como existir.
function UI.DebugList()
    return frame and frame.list
end

---Acesso à faixa de avisos, para o harness poder clicar nas caixas.
---O painel de progresso, para o teste poder olhar o que a janela mostra. Sem esta porta o
---harness so conseguiria afirmar que "nao deu erro" -- que e o que ele ja dizia enquanto o
---passo pulado aparecia igual ao passo que nao comecou.
function UI.DebugProgress()
    return frame and frame.progress, editor
end

---As medidas do painel. O que se trava aqui e a RAZAO entre os vaos, nao o numero cru: os
---numeros mudam quando a tela mudar; a razao e o que nao pode voltar a quebrar.
function UI.DebugMetrics()
    return {
        row = PROGRESS_ROW,
        icon = PROGRESS_ICON,
        iconGap = PROGRESS_ICON_GAP,
        titleGap = PROGRESS_TITLE_GAP,
        hold = PROGRESS_HOLD,
        states = PROGRESS_STATE,
    }
end

---Quanto mede o card de um conjunto. Geometria é aritmética e se confere em disco — duas
---rodadas de teste in-game já foram gastas neste projeto com posição e largura, e as duas eram
---conferveis daqui.
function UI.DebugCardHeight(preset)
    return CardHeight(preset)
end

function UI.DebugCardMetrics()
    return {
        pad = CARD_PAD, name = CARD_NAME_INK, line = CARD_LINE, warn = CARD_WARN,
        icon = CARD_ICON, nameGap = CARD_NAME_GAP, left = CARD_LEFT,
        top = CARD_TOP, textW = CARD_TEXT_W, listW = LIST_W,
        cardMax = CARD_MAX, visiveis = CARDS_VISIVEIS, spacing = ROW_SPACING,
        listH = LIST_H, listTop = LIST_TOP, listBottom = LIST_BOTTOM,
        stripY = WARN_STRIP_Y, stripH = WARN_STRIP_H, footer = TEMPLATE_FOOTER,
        height = HEIGHT, width = WIDTH,
    }
end

function UI.DebugToggles()
    return frame and frame.toggles
end

function UI.Selected()
    return current
end

---Seleciona um conjunto pela janela, como se o jogador tivesse clicado na linha dele.
---
---Existe para o atalho do minimapa: conjunto com aparência não pode ser aplicado por lá (a troca
---de aparência exige o clique no botão seguro), então o atalho abre a janela **com ele já
---selecionado** — um clique a mais, e o clique certo.
---
---`Refresh` reancora a seleção a partir de `current`, então basta apontá-lo e redesenhar.
function UI.Select(preset)
    if not preset then return end
    current = preset
    UI.Refresh()
    UI.RefreshEditor()
end

---A janela está aberta?
---
---Existe porque `Toggle` alterna, e alternar obriga quem chama a saber o estado anterior. No
---harness isso vira dependência de ORDEM entre blocos de teste: um bloco que abre sem fechar
---inverte o comportamento de todos os seguintes, e o defeito aparece longe de onde nasceu --
---foi exatamente o que aconteceu ao escrever os testes da 0.10.0.
function UI.IsShown()
    return frame ~= nil and frame:IsShown() and true or false
end

function UI.SetStatus(text, isError)
    if not frame then return end
    frame.status:SetText(text or "")
    if isError then
        frame.status:SetTextColor(1, 0.5, 0.4)
    else
        frame.status:SetTextColor(0.75, 0.78, 0.82)
    end
end

---Só o editor. Chamado quando a seleção muda ou quando um combo escreve.
function UI.RefreshEditor()
    if not frame or not editor then return end

    local preset = UI.Selected()

    -- O EDITOR CEDE A COLUNA ENQUANTO O PROGRESSO ESTÁ NELA. Não é só para não sobrepor: mexer
    -- nos combos de um conjunto que está sendo aplicado muda o alvo no meio do caminho, e a
    -- corrente já leu o que ia ler. Sumir com os campos é a forma mais direta de dizer "agora
    -- não" — mais do que desabilitar cada um deles.
    local has = preset ~= nil and not (frame.progress and frame.progress:IsShown())

    editor.name:SetShown(has)
    for _, group in ipairs({ editor.spec, editor.talent, editor.gear, editor.transmog }) do
        -- `SetupMenu` só gera o menu com o frame visível: mostrar ANTES de sincronizar.
        group:SetShown(has)
        if has then group.Sync() end
    end
    editor.divider:SetShown(has)

    if has and not editor.name:HasFocus() then
        editor.name:SetText(preset.name or "")
        if editor.name.Instructions and InputBoxInstructions_OnTextChanged then
            InputBoxInstructions_OnTextChanged(editor.name)
        end
    end
end

function UI.Refresh()
    if not frame or not frame:IsShown() then return end

    local presets = Presets()
    local total = #presets
    local empty = total == 0

    -- As caixas ficam fora do jogo de esconder/mostrar de propósito: elas valem nos dois
    -- estados, e o estado vazio é justamente onde elas mais importam.
    -- UM LUGAR SÓ acerta o estado das caixas (`UI.RefreshToggles`). Este bloco repetia a mesma
    -- regra que a função dela já tinha, e a sabotagem denunciou: desligar o `SetEnabled` de lá
    -- não reprovava nada, porque a cópia daqui continuava acertando o estado. Duas partes do
    -- addon sabendo a mesma coisa é a divergencia da próxima mudança com data marcada.
    UI.RefreshToggles()

    frame.emptyState:SetShown(empty)
    if frame.Inset then frame.Inset:SetShown(not empty) end
    frame.list:SetShown(not empty)
    frame.new:SetShown(not empty)
    frame.delete:SetShown(not empty)

    if empty then
        -- SEM LISTA NÃO HÁ CORRENTE. Sem esta linha, `current` continuava apontando para o último
        -- conjunto selecionado mesmo depois de ele sair da lista — e `UI.Selected()` devolvia um
        -- conjunto que não existe mais, que é o que `UI.Load` e `UI.Delete` consomem.
        --
        -- O editor some de qualquer jeito logo abaixo, então nada disso aparecia na tela; o teste
        -- que cobria isto passava por acidente de ordem, porque quem rodava antes dele deixava
        -- `current` nulo. Um bloco de teste novo mudou a ordem e o defeito apareceu.
        current = nil

        editor.name:Hide()
        editor.divider:Hide()
        for _, group in ipairs({ editor.spec, editor.talent, editor.gear, editor.transmog }) do
            group:Hide()
        end
        return
    end

    -- `SetDataProvider` apaga a seleção do comportamento; por isso o conjunto corrente é
    -- guardado por fora e reancorado logo abaixo.
    local wanted = current
    frame.list:SetDataProvider(CreateDataProvider(presets), true)

    local stillThere = false
    for i = 1, total do
        if presets[i] == wanted then stillThere = true end
    end

    -- Seleção automática: é isto que faz o estado "nada selecionado" não existir, e com ele
    -- os rótulos órfãos e o texto colado. Não é um remendo — é a remoção do estado.
    selection:SelectElementData(stillThere and wanted or presets[1])

    UI.RefreshEditor()
end

---Depois de mexer num combo: o texto da linha mudou, a quantidade não. Reinicializar é mais
---barato que trocar o data provider, e não perde a rolagem.
function UI.AfterEdit()
    if frame and frame.list and frame.list.ReinitializeFrames then
        frame.list:ReinitializeFrames()
    end
    UI.RefreshEditor()
end

--------------------------------------------------------------------------------
function UI.New()
    local presets = Presets()

    -- O conjunto novo já nasce com o que está valendo AGORA. É o caso de uso real: você
    -- acabou de arrumar spec, talentos e equipamento para uma masmorra — agora só quer dar
    -- um nome a isso. Começar vazio obrigaria a redigitar o óbvio.
    local specIndex = ns.Data.GetCurrentSpecIndex()
    local spec = ns.Data.GetSpecByIndex(specIndex)

    local preset = {
        name = "",
        spec = specIndex,
        talent = spec and ns.Data.GetActiveLoadoutID(spec.id) or nil,
        gear = ns.Data.GetEquippedSetID(),
    }
    presets[#presets + 1] = preset

    current = preset
    UI.Refresh()
    editor.name:SetFocus()
end

function UI.SaveName()
    local preset = UI.Selected()
    if not preset then return end

    local name = editor.name:GetText() or ""
    name = name:match("^%s*(.-)%s*$")
    if name == preset.name then return end

    preset.name = name
    UI.AfterEdit()
end

function UI.Delete()
    local preset = UI.Selected()
    if not preset then return end

    local presets = Presets()
    for i = 1, #presets do
        if presets[i] == preset then
            table.remove(presets, i)
            break
        end
    end

    current = nil
    if selection and selection.ClearSelections then selection:ClearSelections() end
    UI.SetStatus(L["preset deleted."], false)
    UI.Refresh()
end

---Chamada do `PostClick` do botão seguro, e por isso o terceiro argumento é `true`: a ação de
---aparência JÁ foi disparada pelo clique, e o passo de aparência tem que ESPERAR a resposta do
---servidor em vez de conferir na hora e acusar falha numa troca que está a caminho.
function UI.Load(preset)
    if not preset then return end
    ns.db.last = preset.name
    ns.Data.Apply(preset, UI.SetStatus, true)
    -- NO MESMO QUADRO DO CLIQUE. O `OnUpdate` traria o painel em até 0,1 s, mas o defeito que
    -- este painel conserta é justamente a sensação de que o clique não fez nada — então ele não
    -- pode ser a primeira coisa a chegar atrasada.
    UI.RefreshProgress()
end

--------------------------------------------------------------------------------
function UI.Toggle()
    Create()
    if frame:IsShown() then
        frame:Hide()
        return
    end

    if ns.db.pos then
        frame:ClearAllPoints()
        frame:SetPoint(ns.db.pos.point, UIParent, ns.db.pos.relPoint, ns.db.pos.x, ns.db.pos.y)
    end

    frame:Show()
    UI.SetStatus("", false)
    UI.Refresh()
end

function UI.Show()
    Create()
    if not frame:IsShown() then UI.Toggle() end
end
