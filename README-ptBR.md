# Rocket Swap

Conjuntos que relacionam **especialização + talentos + itens + aparência**, trocados com um
clique. Para World of Warcraft: Midnight (12.x).

> 🇺🇸 [Read in English](README.md) — o inglês é a versão de referência deste documento.

## Por que existe

Trocar de função no WoW não é uma ação, são quatro — e elas estão em quatro janelas diferentes.
Quem alterna entre tanque e dano faz isso várias vezes por sessão, na ordem certa, sem esquecer
nenhuma. O addon guarda o conjunto e faz as quatro.

## O que ele resolve, e que não é óbvio

**A troca é uma corrente, não um comando.** Cada passo depende do anterior e é confirmado por um
evento do jogo, não por uma leitura de estado logo depois da chamada — o servidor demora, e
conferir na hora acusa falha numa troca que está a caminho.

**A troca de aparência é API protegida.** `ChangeToOutfit` devolve sucesso e não faz nada quando
chamada de código de addon. Desde o patch 12.0.5 existe uma ação segura `outfit`, e é por isso
que a aparência só troca pelo botão **Carregar** — ela acontece dentro do clique, antes de todo o
resto. O passo final apenas confere se pegou.

**E era esse clique seguro que provocava um segundo cast.** A troca de aparência *conjura*, e o
jogo não deixa começar uma troca de especialização com outra conjuração em voo. Resultado: a
primeira `SetSpecialization` era recusada em toda troca que mexesse nas duas coisas. O addon lia
isso como "o jogo está ocupado" e insistia quatro segundos depois — então o jogador via duas
barras de conjuração com um vão morto entre elas. Agora o passo de especialização espera a
conjuração sair do caminho antes de pedir. Diagnosticado pelo diário do próprio addon, não por
suposição.

**Conjunto de itens com peça faltando não troca.** Quando um conjunto salvo pede uma peça que
você não tem mais, o jogo não deixa o espaço vazio — ele **mantém o que você está vestindo**.
A troca "dá certo" e você sai com o berloque do papel anterior num conjunto feito para outro,
sem nada na tela dizendo isso. Somando a isso, conjunto com peça perdida nunca consegue se
declarar em uso, então o passo nunca fecha. O Rocket Swap recusa a troca, marca o conjunto em
vermelho antes do clique, nomeia as peças que sumiram O botão Carregar fica apagado — botão que aceita
o clique e depois responde "não deu" é pior que botão apagado — e a faixa vermelha carrega a
ação que resolve: **Salvar conjunto** quando você já está vestindo o conjunto inteiro menos o
que sumiu (o único caso em que salvar por cima conserta em vez de destruir), ou **Gerenciador**,
que abre o gerenciador do próprio jogo na aba certa. Pelo chat, `/rs fix`.

## Como se usa

| Comando | O quê |
|---|---|
| `/rs` | abre a janela |
| `/rs load <nome>` | carrega um conjunto pelo nome |
| `/rs list` | lista os conjuntos |
| `/rs gear` | mostra o que cada espaço está lendo |
| `/rs progress` | liga/desliga o painel flutuante de progresso |
| `/rs log` | o diário das últimas trocas (é ele que responde "por que não trocou?") |
| `/rs warn` | liga/desliga o aviso de conjunto errado |
| `/rs ready` | liga/desliga o resumo no *ready check* |
| `/rs queue` | liga/desliga o resumo no convite da fila de PvP |

O botão do minimapa abre a janela; o botão direito carrega o último conjunto.

Durante a troca, um painel flutuante mostra quais etapas o conjunto pede, em qual delas estamos e
quais já fecharam. A barra anda **por etapa fechada**, nunca contra um relógio: a corrente não
tem como saber quanto o servidor vai demorar, e barra que corre atrás de uma previsão inventada
trava no meio e mente. Terminando bem, o painel fica verde e diz isso por três segundos; se
alguma etapa falhar, ele mantém a lista na tela até você fechar.

## Arquitetura

| Arquivo | Responsabilidade |
|---|---|
| `Core.lua` | ciclo de vida, SavedVariables, eventos |
| `Log.lua` | o diário em SavedVariables — lido de fora do jogo quando algo dá errado |
| `Data.lua` | a corrente de passos e as APIs do jogo; trata Secret Values |
| `UI.lua` | a janela: lista, editor e o progresso dentro dela |
| `Progress.lua` | o painel flutuante de progresso |
| `Gear.lua` | leitura do conjunto de itens e o aviso de equipamento errado |
| `Alert.lua` | os resumos do *ready check* e do convite de fila |
| `Minimap.lua` | o botão do minimapa |

`tests/harness.lua` roda o addon fora do jogo com LuaJIT, e `tests/sabotar.py` quebra o código de
propósito para conferir que os testes pegam — contar linhas `ok` não é critério de aprovação.

```
luajit tests/harness.lua
python tests/sabotar.py
```

## Apoio

Estes addons são gratuitos e vão continuar sendo. Se eles te poupam tempo toda sessão, dá para
apoiar o trabalho em [github.com/sponsors/otaviohonorio](https://github.com/sponsors/otaviohonorio)
— é o que paga as horas de manter tudo em dia a cada patch.

Não apoiar não te custa nada aqui. Um bom relato de defeito vale o mesmo.

## Licença

MIT — ver `LICENSE`.
