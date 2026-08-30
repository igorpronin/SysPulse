# SysPulse

[English](README.md) | [Русский](README.ru.md) | **Português**

Versão atual: **0.8.0** — ver [Releases](../../releases) e o [CHANGELOG](CHANGELOG.md).

<img src="docs/icon.png" width="96" align="right" alt="Ícone do SysPulse">

Um pequeno utilitário para macOS que mostra sempre **como está o seu Mac neste momento** — a carga do CPU por núcleo, a memória de todos os tipos e o espaço livre em disco, ao vivo numa pequena janela flutuante e na barra de menus.

Feito com um propósito simples: manter a máquina debaixo de olho sem abrir o Monitor de Atividade. Uma resposta permanente e imediata à pergunta «há alguma coisa a comer o meu CPU / RAM / disco?», sempre por cima daquilo em que está a trabalhar.

## O aspeto

| Normal | Compacto | Detalhe da memória | Contraste |
|:---:|:---:|:---:|:---:|
| <img src="docs/screenshot-normal.png" width="200" alt="Janela flutuante: barras por núcleo do CPU, barra de memória, discos"> | <img src="docs/screenshot-compact.png" width="158" alt="Janela compacta: as mesmas linhas, com letras e barras mais pequenas"> | <img src="docs/screenshot-details.png" width="200" alt="Detalhe da memória: aplicações, residente, comprimida, cache, livre, swap, pressão"> | <img src="docs/screenshot-contrast.png" width="200" alt="Modo de contraste: fundo branco, texto escuro"> |

A janela flutuante semitransparente sobre a secretária; os mesmos números vivem na barra de menus. As capturas de ecrã são geradas fora do ecrã com dados fictícios pelo `scripts/make-screenshots.sh` — nenhum estado real da máquina entra nelas.

## Funcionalidades

- **Janela flutuante** — um pequeno painel semitransparente. Arraste-o para onde quiser; a posição fica memorizada. Se desligar o monitor onde ele está, o painel muda-se para aquele em que está a trabalhar, em vez de ficar fora de vista.
- **Um menu, duas formas de lá chegar** — clique com o botão direito na janela (ou toque com dois dedos) e o mesmo menu do ícone da barra de menus abre-se logo por baixo. Nada está acessível só a partir de um deles, e tudo continua ao alcance mesmo quando uma barra de menus cheia esconde o ícone. O botão esquerdo fica livre para arrastar.
- **CPU, núcleo a núcleo** — uma barra por cada núcleo lógico mais a percentagem global, com os núcleos de desempenho e os de eficiência separados por um intervalo e identificados ao passar o ponteiro. Numa máquina com muitos núcleos a faixa alarga-se para as barras continuarem legíveis em vez de afinarem até ao fio, e todas têm exatamente a mesma largura.
- **Carga do GPU** — lida diretamente do sistema, sem permissões e sem `powermetrics`. O Apple Silicon reporta um único valor para todo o GPU, por isso não há detalhe por núcleo para mostrar.
- **Memória de todos os tipos** — uma barra segmentada com usada / total ao lado: azul para a memória das aplicações, laranja para a residente, violeta para a comprimida, cinzento neutro para a cache de ficheiros — e a cauda vazia é aquilo que está livre. Aqui a cor diz *que tipo é*, não *quanto é*, e os tons estão validados quanto à separação para daltónicos e ao contraste, tanto no modo claro como no escuro. Ative o detalhe e cada tipo aparece em números, juntamente com a swap e o nível de pressão de memória segundo o próprio sistema; passar o ponteiro pela etiqueta RAM mostra esse nível a qualquer momento.
- **Passe o ponteiro e perceba** — sobre um segmento da barra de memória, ele diz o nome e o tamanho; sobre uma linha do detalhe, explica o que é aquele tipo de memória e para que serve, até ao significado das pressões Normal, Alerta e Crítica. Dá jeito se alguma vez se questionou porque é que um Mac saudável quase não tem memória livre.
- **Espaço livre em disco** — uma linha por cada volume local montado, com a fração ocupada em barra e o espaço livre em números; passe o ponteiro pela barra para ver quanto está ocupado e o nome completo do volume. Em APFS e HFS+ o valor é exatamente o que o Finder mostra, incluindo o espaço recuperável dos snapshots; em exFAT e FAT — o formato com que a maioria dos discos externos chega — recorre à contagem simples de espaço livre, a única que esses sistemas de ficheiros mantêm. Clicar na barra de um volume abre-o no Finder. Os volumes que não lhe interessam escondem-se nas definições.
- **Tamanhos de pastas** — acompanhe as pastas que quiser: adicione-as em «Pastas», escrevendo o caminho ou escolhendo-a no Finder, dê a cada uma a sua periodicidade de análise (não atualizar, ou de uma vez por minuto até uma vez por dia), e os tamanhos juntam-se ao painel num bloco próprio, sob um título «Pastas» que traz o total de todas elas. Um botão no título volta a analisar todas de uma vez, e cada pasta tem o seu. Defina um apelido e o painel mostra-o em vez do nome da pasta. Passar o ponteiro por uma pasta indica o caminho, a periodicidade, quando foi medida pela última vez e os dez maiores elementos lá dentro — subpastas e ficheiros soltos ordenados em conjunto, as pastas marcadas com uma barra final —, o suficiente para ver o que está realmente a ocupar o espaço. Clicar no nome de uma pasta abre-a no Finder. Os resultados ficam em cache, por isso o tamanho está no ecrã assim que a aplicação arranca, sem esperar por uma nova análise.
- **Cores conforme a carga** — as barras vão do verde ao amarelo e ao vermelho à medida que se enchem, por isso um núcleo ocupado ou um disco cheio saltam à vista sem ler um único número.
- **Linha na barra de menus** — por predefinição a carga do CPU, com a memória e o disco também disponíveis; os valores usam dígitos de largura fixa, para que os ícones vizinhos da barra de menus nunca dancem, e a dica do ícone traz sempre o resumo completo. Desligue os três e um pequeno ícone toma o lugar dos valores, para que o menu nunca fique inacessível com o painel escondido.
- **Frequência de atualização** — 0,5, 1, 2 ou 5 segundos. O espaço em disco é consultado à parte e raramente, porque muda devagar e custa mais a ler.
- **Escolha as métricas** — cada secção (CPU, barras por núcleo, memória, detalhe, discos) é um interruptor; a janela encolhe até exatamente aquilo que deixou ligado.
- **Modo compacto** — uma janela ainda mais pequena: letras mais pequenas, barras mais finas, linhas mais juntas.
- **Cursor de opacidade** — um cursor nas definições de interface leva a janela do totalmente transparente ao preto sólido; a cor do texto acompanha, para se manter sempre legível.
- **Modo de contraste** — um interruptor nas definições de interface inverte o esquema de cores: o fundo vai do transparente para o branco em vez do preto, e o texto adapta-se em sentido contrário.
- **Alinhamento à esquerda ou à direita** — o alinhamento à direita espelha cada linha (valor, barra, etiqueta) e mantém a margem direita da janela fixa, crescendo para a esquerda. Prático quando a janela fica junto ao limite direito do ecrã.
- **Sempre visível** decide duas coisas ao mesmo tempo, porque andam juntas. Ligado: o painel paira acima de tudo e aparece em todas as áreas de trabalho do seu monitor, incluindo aplicações em ecrã completo. Desligado: comporta-se como uma janela normal, pode ficar tapado, e vive numa só área de trabalho — aquela onde o deixou. Uma janela que se esconde debaixo das outras não tem por que o seguir por todas as áreas de trabalho.
- **Tudo fica memorizado** — métricas escolhidas, volumes escondidos, posição da janela, modo compacto, alinhamento, opacidade e visibilidade sobrevivem a reinícios da aplicação.
- **Abrir ao iniciar sessão** — um interruptor no menu (usa o `SMAppService` do sistema).
- **Verificação de atualizações** — uma vez por dia o SysPulse pergunta ao GitHub se saiu uma versão mais recente. Se saiu, a linha de topo do menu di-lo e abre a página da versão; nunca descarrega nem substitui nada por sua conta. Pode verificar à mão quando quiser, ou desligar de vez a verificação automática.
- **10 idiomas** — English (predefinição), Русский, Español, Deutsch, Français, Italiano, Português, 中文, 日本語, 한국어. Trocam-se a partir do menu.

## Planos

- **Ejetar discos externos** — um botão de ejetar na linha de cada volume amovível, para desmontar um disco com um clique ali mesmo onde já está a olhar, em vez de ir ao Finder para isso.
- **Formato do volume na dica do disco** — passar o ponteiro por um volume passaria a dizer também em que está formatado: APFS, HFS+, exFAT, FAT32. Essa única palavra explica ali mesmo porque é que um disco externo conta o espaço livre de outra maneira que o volume de arranque, em vez de deixar a resposta enterrada neste README.
- **Totais de pastas com noção de aninhamento** — quando uma pasta acompanhada está dentro de outra, os seus bytes são hoje contados duas vezes: o título «Pastas» limita-se a somar todas as pastas. O plano é apurar que pasta contém qual e contar o espaço partilhado uma só vez, para que o total seja o espaço realmente ocupado e não a soma das linhas.
- **Ir até à pasta acabada de adicionar** — «Adicionar pasta» acrescenta uma linha vazia ao fundo da lista e, assim que a lista fica mais alta do que a janela, essa linha cai fora da vista: parece que o botão não fez rigorosamente nada. Adicionar uma pasta deve deslocar a lista até lá.
- **Histórico e gráfico** — o espaço livre em disco e os tamanhos das pastas são medidos de poucos em poucos minutos e cada leitura é logo deitada fora. Guardados num pequeno registo local, os mesmos números passam a ser uma linha que se lê num relance: se um disco enche de forma regular ou se perdeu 40 GB de um dia para o outro, e qual das pastas acompanhadas foi a que cresceu. O registo ficaria na máquina, como tudo o resto que a aplicação regista.
- **Português europeu na aplicação** — a interface fala hoje o português do Brasil, ao passo que este README já está escrito na variante europeia. O plano é uma tradução pt-PT à parte, oferecida a par da pt-BR no menu de idiomas, para que as duas coincidam.

## Privacidade

O SysPulse faz exatamente um tipo de pedido de rede: uma vez por dia pergunta ao GitHub se existe uma versão mais recente. Nada sobre si é enviado — o GitHub vê um endereço IP e o nome e a versão da aplicação, tal como qualquer navegador que abra a página das versões — e pode desligar a verificação em **Atualizações → Verificar automaticamente**.

Tudo o resto é local: a aplicação lê os contadores da sua própria máquina através de APIs públicas do macOS e guarda as suas definições nas preferências dela. Sem contas, sem estatísticas, sem telemetria, e nada sobre os seus ficheiros ou a sua máquina sai dela.

## Instalação (versão pré-compilada)

1. Descarregue o `SysPulse.zip` da página [Releases](../../releases) e descompacte-o.
2. Mova o `SysPulse.app` para `/Applications`.
3. Primeira abertura: a aplicação não está notarizada, por isso o macOS bloqueia o duplo clique normal. No **macOS 15 Sequoia**, tente abri-la uma vez e depois vá a **Definições do Sistema → Privacidade e Segurança** e prima **Abrir Mesmo Assim** — a Apple retirou no Sequoia o antigo atalho do clique com Control. No **macOS 13 e 14**, clicar na aplicação com o botão direito → **Abrir** → **Abrir** ainda funciona. Em qualquer versão, remover o sinalizador de quarentena no Terminal resolve:

   ```sh
   xattr -dr com.apple.quarantine /Applications/SysPulse.app
   ```

4. Procure os valores na barra de menus (se não os vir, a sua barra de menus pode estar cheia — arraste outros ícones com Cmd para abrir espaço). De qualquer forma a janela flutuante aparece na primeira abertura, e clicar nela com o botão direito abre o mesmo menu.

Requer macOS 13 Ventura ou posterior. Não são precisas permissões especiais.

## Compilar a partir do código-fonte

Requisitos: macOS 13+, Xcode Command Line Tools (`xcode-select --install`). Não é preciso um projeto Xcode — isto é um Swift Package normal.

```sh
git clone https://github.com/igorpronin/SysPulse.git
cd SysPulse
./build-app.sh
ditto build/SysPulse.app /Applications/SysPulse.app
```

O `build-app.sh` compila um binário de release com o SwiftPM, envolve-o num pacote `.app` com o ícone (regenerado pelo `scripts/make-icon.sh` se faltar) e assina-o em modo ad-hoc. A versão vem do `Sources/SysPulse/Version.swift` e aparece na janela «Sobre».

Variante de desenvolvimento com informação extra na janela «Sobre»: `./build-app.sh -dev`.

## Licença

MIT — ver [LICENSE](LICENSE).

## Como funciona

- **CPU** — o `host_processor_info(PROCESSOR_CPU_LOAD_INFO)` dá contadores cumulativos de ticks por núcleo lógico; a carga é a diferença entre duas amostras (user + system + nice contra o total), por isso a primeira amostra depois do arranque só define o ponto de partida.
- **Memória** — o `host_statistics64(HOST_VM_INFO64)` nos termos do Monitor de Atividade: a memória das aplicações são as páginas anónimas menos as purgeable, mais as páginas residentes (wired) e comprimidas; usada = aplicações + residente + comprimida. A cache de ficheiros e a memória livre são reportadas à parte, a swap vem de `vm.swapusage` e o nível de pressão de `kern.memorystatus_vm_pressure_level`.
- **Discos** — `volumeAvailableCapacityForImportantUsage` para cada volume local visível montado, que é exatamente o que o Finder mostra.
- **Pastas** — um percurso da árvore de ficheiros por análise, somando o espaço que cada ficheiro ocupa de facto em disco (o valor que o `du` reporta) e atribuindo-o à subpasta de primeiro nível onde ele está. Os percursos correm um de cada vez em segundo plano, fora do fio principal; adicionar uma pasta dentro da Secretária, dos Documentos ou das Transferências faz o macOS pedir permissão à primeira vez, e uma pasta que não se consiga ler é indicada como tal em vez de aparecer a zero. A memória é contada em gigabytes binários e os discos em decimais, tal como o próprio macOS reporta cada um.
- A janela é um `NSPanel` sem moldura e não-ativante, ao nível flutuante, com uma vista SwiftUI lá dentro — clicar nela nunca rouba o foco à aplicação em que está.
