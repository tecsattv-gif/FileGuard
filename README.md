# FileGuard

Gerenciador de arquivos para Android: navegar pelas pastas, copiar, mover, compactar em ZIP, ver fotos, vídeos, PDF e textos dentro do app e limpar o armazenamento.

## Baixar

O APK mais novo fica em [Releases](https://github.com/tecsattv-gif/FileGuard/releases/latest). Depois de instalado, o próprio app avisa quando há versão nova e instala com a sua autorização.

## Primeira vez

1. Abra o app. Na tela **Início** aparece o cartão *Falta liberar o acesso*.
2. Toque em **Permitir acesso** e ligue a chave do FileGuard em *Acesso a todos os arquivos*. Sem isso o Android não deixa o app ver as pastas.

## O que o app faz

- **Início**: armazenamento interno e cartão SD com o espaço usado e livre, atalhos (Downloads, Câmera, Imagens, Documentos, Música, Filmes, WhatsApp, Telegram, só os que existem no telefone), categorias, favoritos e Lixeira.
- **Arquivos**: navegar pelas pastas, com o caminho no topo (toque numa parte para voltar até ela). Ordenar por nome, data, tamanho ou tipo; lista ou grade; mostrar ou esconder os arquivos ocultos. Miniaturas das fotos.
- **Selecionar**: toque longo num item. Depois toque nos outros para juntar à seleção.
- **Copiar e Mover**: selecione, toque em *Copiar* ou *Mover*, abra a pasta de destino e toque em **Colar aqui**. Se já existir um item com o mesmo nome, o novo fica "nome (1)". Funciona entre o interno e o cartão SD.
- **Renomear, Nova pasta, Propriedades** (tamanho com as subpastas somadas, data e local), **Enviar** (compartilhar) e **Abrir com outro app**.
- **Buscar**: a lupa filtra a pasta aberta; o botão ao lado busca também em todas as subpastas.
- **Favoritos**: selecione uma pasta → *Mais* → *Adicionar aos favoritos*. Aparecem no Início.
- **ZIP**: selecione arquivos ou pastas → *Mais* → *Compactar em ZIP*. Toque num .zip para **extrair** numa pasta com o mesmo nome ou na pasta atual. Também extrai .tar, .tar.gz/.tgz, .tar.bz2 e .tar.xz. Arquivos .rar e .7z abrem com outro app.
- **Visualizar dentro do app**:
  - **Fotos** com zoom (dois dedos) e passar para o lado para ver as outras fotos da pasta.
  - **Vídeo e áudio** com play/pausa, barra de posição e ±10 s.
  - **PDF** página por página (deslize para cima), com zoom.
  - **Textos** (.txt, .log, .csv, .json, .xml, .srt, .m3u e outros, até 2 MB) para ler e **editar** (lápis → salvar). Ao sair sem salvar o app pergunta antes.
  - Word, Excel, APK e outros abrem no app do telefone (o APK abre o instalador).
- **Categorias**: todas as imagens, vídeos, áudios, PDFs, documentos, compactados, APKs ou textos do telefone, do mais novo para o mais antigo, com seleção para apagar ou enviar.
- **Lixeira**: o que se apaga vai para a Lixeira (com **DESFAZER** por 8 segundos logo depois). Na Lixeira dá para restaurar para o lugar de onde saiu ou apagar de vez. Depois de 30 dias é apagado sozinho. Nos Ajustes dá para desligar a Lixeira (aí apaga de vez).
- **Limpeza**: *Analisar armazenamento* mostra:
  - o **espaço por tipo** (imagens, vídeos, áudio…);
  - **arquivos grandes** (mais de 50 MB);
  - **duplicados** (arquivos iguais em mais de um lugar, comparando o conteúdo). *Selecionar cópias* marca todos menos o mais antigo de cada grupo, e o app não deixa apagar todas as cópias de um grupo;
  - **APKs** (instaladores que ficaram no telefone);
  - **pastas vazias**;
  - o tamanho da **Lixeira**.
  
  O que se apaga na Limpeza sai **de vez** (não passa pela Lixeira), porque o objetivo é liberar espaço. O app sempre pede confirmação antes.
- **Telefone e tablet, em pé ou deitado**: com o telefone deitado ou no tablet o menu fica na lateral, e a grade mostra mais colunas.
- **Backup**: salvar os ajustes e favoritos em *Download/FileGuard/fileguard-backup.json* (o novo substitui o anterior), compartilhar o backup e restaurar.
- **Atualização pelo app**: avisa quando há versão nova; *Ajustes → Procurar atualização* procura na hora.
- **Abertura** com o ícone, a versão instalada (muda sozinha a cada atualização) e os créditos.

## Pastas que o app não abre

No Android 11 ou mais novo, *Android/data* e *Android/obb* são bloqueadas pelo próprio Android para todos os gerenciadores de arquivos. A Lixeira fica na pasta oculta *.FileGuard* de cada armazenamento.

## Compilar

Cada envio para o `main` compila o APK no GitHub Actions, roda os testes e publica numa Release com a versão do `pubspec.yaml` (formato 1.2.0, subida à mão a cada mudança).

Para a Release sair assinada sempre com a mesma chave (e o Android aceitar atualizar por cima), o repositório precisa do segredo **FILEGUARD_KEYSTORE** em *Settings → Secrets and variables → Actions* (qualquer texto serve como senha). Sem ele o APK é compilado só para teste, sem Release. O repositório precisa ser **público** para a atualização pelo app funcionar.

## Versões

- **1.0.1**: Componentes com tema completo pelo **FlexColorScheme** (pacote `flex_color_scheme`, open source, MIT): botões, interruptores, chips, menus, caixas de seleção e campos dos diálogos seguem as cores do app, com cantos arredondados iguais e efeitos de toque. O visual das telas não muda. Código: `TG.theme()` em `lib/theme.dart`.
- **1.0.0**: primeira versão (pastas, copiar/mover, ZIP, visualizador, categorias, Lixeira, Limpeza, favoritos, backup e atualização pelo app).

Criado por Luiz Alberto Cardoso (tecsattv@gmail.com).
