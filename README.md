# Rocket Swap

Conjuntos que relacionam **especialização + talentos + itens + aparência**, trocados com um
clique. Para World of Warcraft: Midnight (12.x).

## Por que existe

Trocar de função no WoW não é uma ação, são quatro — e elas estão em quatro janelas diferentes.
Quem alterna entre tanque e dano faz isso várias vezes por sessão, na ordem certa, sem esquecer
nenhuma. O addon guarda o conjunto e faz as quatro.

## O que ele resolve, e que não é óbvio

**A troca é uma corrente, não um comando.** Cada passo depende do anterior e é confirmado por um
evento do jogo, não por uma leitura de estado logo depois da chamada — o servidor demora, e
conferir na hora acusa falha numa troca que está a caminho.

**O jogo recusa trocar de especialização por alguns segundos depois de uma troca.** A recusa é
transitória e não tem como ser prevista: o diário real mostrou a mesma troca sendo aceita ora em
4, ora em 14 segundos, com todos os preditores possíveis respondendo "pode trocar". Então o addon
não adivinha — ele espera e insiste, e o jogador clica uma vez só.

**A troca de aparência é API protegida.** `ChangeToOutfit` devolve sucesso e não faz nada quando
chamada de código de addon. Desde o patch 12.0.5 existe uma ação segura `outfit`, e é por isso
que a aparência só troca pelo botão **Carregar** — ela acontece dentro do clique, antes de todo o
resto. O passo final apenas confere se pegou.

## Como se usa

| Comando | O quê |
|---|---|
| `/rs` | abre a janela |
| `/rs log` | o diário das últimas trocas (é ele que responde "por que não trocou?") |
| `/rs warn` | liga/desliga o aviso de conjunto errado |
| `/rs ready` | liga/desliga o resumo no *ready check* |

O botão do minimapa abre a janela; o botão direito carrega o último conjunto.

## Arquitetura

| Arquivo | Responsabilidade |
|---|---|
| `Core.lua` | ciclo de vida, SavedVariables, eventos |
| `Log.lua` | o diário em SavedVariables — lido de fora do jogo quando algo dá errado |
| `Data.lua` | a corrente de passos e as APIs do jogo; trata Secret Values |
| `UI.lua` | a janela: lista, editor e o progresso da troca |
| `Gear.lua` | leitura do conjunto de itens e o aviso de equipamento errado |
| `Alert.lua` | o resumo do *ready check* |
| `Minimap.lua` | o botão do minimapa |

`tests/harness.lua` roda o addon fora do jogo com LuaJIT, e `tests/sabotar.py` quebra o código de
propósito para conferir que os testes pegam — contar linhas `ok` não é critério de aprovação.

```
luajit tests/harness.lua
python tests/sabotar.py
```

## Licença

MIT — ver `LICENSE`.
