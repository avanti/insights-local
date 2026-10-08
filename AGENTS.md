# Avanti Insights local

Este repositorio publico prepara dois aplicativos privados da organizacao Avanti.

- Leia README.md antes de iniciar. Use scripts/local.ps1 no Windows e
  scripts/local.sh no macOS/Linux. O primeiro comando e setup.
- Comece em modo demo, a menos que a pessoa solicite explicitamente connected.
- Verifique acesso aos repositorios de sources.lock. Login GitHub, senha sudo,
  termos do Docker e reinicializacao devem ser concluidos pela pessoa quando exigidos.
- Se o Git estiver ausente, instale-o pelo mecanismo oficial do sistema e confirme
  que git funciona antes de clonar este repositorio, conforme o prompt no README.
- No macOS, execute /usr/bin/xcode-select --install pelas ferramentas locais do
  Codex quando o Git estiver indisponivel. Nao delegue a pessoa a abertura do
  Terminal nem a copia de comandos. Peça apenas as confirmacoes da janela do macOS,
  acompanhe a instalacao e confirme /usr/bin/git --version antes de continuar.
  Use as Xcode Command Line Tools; o aplicativo Xcode completo nao e necessario.
- Execute doctor e a verificacao de login antes de declarar o ambiente pronto.
- Quando a pessoa solicitar abrir ou adicionar os aplicativos ao Codex, use
  scripts/local.ps1 codex ou bash scripts/local.sh codex depois de setup.
  Os links e caminhos absolutos estao em .local/codex-projects.json; a pagina
  .local/codex-projects.html e os atalhos nativos oferecem a mesma abertura.
  Verifique, com list_projects quando disponivel, se as duas pastas ja estao
  cadastradas como projetos. Abrir uma conversa por link nao confirma o cadastro.
  Se nao houver ferramenta para cadastrar uma pasta, informe os caminhos completos
  e oriente a pessoa a usar Criar projeto. Nao altere bancos ou arquivos internos
  do aplicativo Codex para forcar o cadastro.
- Nunca imprima .local/*.env, secrets.json, access.txt, tokens ou senhas no chat.
  Abra access.txt no editor local para a pessoa consultar o primeiro acesso.
- sources/ e .local/ sao privados e ignorados pelo Git. Publique apenas arquivos
  explicitamente revisados do instalador; nunca copie codigo dos apps para este repo.
- setup pode parar os containers deste instalador, mas deve preservar os volumes,
  senhas existentes e alteracoes nos checkouts. Nao execute down -v nem git reset.
- O banco e preparado pelo bootstrap local atual, sem reproduzir a historia
  legada do Alembic. Nunca aponte este instalador para bancos compartilhados.
- O modo demo bloqueia escritas fora da autenticacao e nao tem egress de rede.
  Nao remova essas protecoes para ocultar falhas de integracoes.
- Rode python -m unittest discover -s tests -v, bash -n scripts/local.sh e
  os testes PowerShell antes de publicar alteracoes.
- Atualizacoes de sources.lock exigem novo smoke test com os dois aplicativos.
