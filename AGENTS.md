# Avanti Insights local

Este repositorio publico prepara dois aplicativos privados da organizacao Avanti.

- Leia README.md antes de iniciar. Use scripts/local.ps1 no Windows e
  scripts/local.sh no macOS/Linux. O primeiro comando e setup.
- Conduza a pessoa ate a interface local. Use portugues e mensagens curtas sobre
  a etapa atual. Execute os comandos e downloads; a pessoa so deve concluir as
  confirmacoes necessarias. Nao delegue instalacao inteira por uma falha generica.
- No macOS, siga scripts/macos.sh: Homebrew e preparado se ausente; GitHub CLI e
  Docker sao instalados por Brew. Nao abra navegador para baixar instaladores nem
  peca que a pessoa monte DMGs ou arraste aplicativos. Leia o script antes de usar.
  Senha de administrador somente na janela local, nunca no chat. O helper
  macos-sudo-askpass.sh e exclusivo de sudo; nao execute nem registre sua saida.
- Consulte .local/setup-progress.txt e, no macOS, .local/install-macos.log ao
  retomar ou diagnosticar uma falha. Preserve o erro original; nao invente sua
  causa. Se uma confirmacao estiver pendente, explique uma acao concreta de cada
  vez, a janela correta e como retomar. Acompanhe processos com esperas curtas e
  informe progresso enquanto downloads e instalacoes ainda estiverem trabalhando.
- Para gh auth login, use terminal interativo quando necessario; a pessoa conclui
  login, 2FA e autorizacao da organizacao no navegador. Se a revisao automatica
  rejeitar uma acao, identifique essa acao e o motivo retornado, conclua trabalho
  independente e aguarde a resolucao. Nao use outro meio para contornar a rejeicao.
- O setup sempre prepara integracoes reais. Nao existe modo demo nem opcao de modo.
- Instale AWS CLI >= 2.32.0 e use aws login para abrir o navegador com o perfil
  avanti-insights-local. A pessoa informa usuario, senha e MFA somente na AWS.
  Reutilize sessoes autorizadas; nao crie IAM users nem altere permissoes AWS.
  SignInLocalDevelopmentAccess e GetSecretValue no segredo exigem preparo do
  administrador da Avanti. Perfis SSO existentes tambem sao suportados.
- O segredo synapse/review-app/env em us-east-1 deve passar pela entrada padrao
  do comando import-secret; nunca capture valores em logs ou argumentos.
  Leia .local/integrations.override.env para ajustes individuais, sem versiona-lo.
  Google Sheets nao e requisito para setup, conforme decisao do usuario.
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
- Se as portas estiverem ocupadas, escolha portas livres com as ferramentas do
  sistema e repita setup com os parametros de porta. Nao pare outros aplicativos.
  Ao concluir, abra o localhost e o acesso local no editor. Se o navegador estiver
  disponivel, verifique o login local sem mostrar a senha no chat. A interface
  deve ficar acessivel mesmo que o cadastro dos projetos na barra lateral do
  Codex dependa de uma etapa manual posterior.
- Quando a pessoa solicitar abrir ou adicionar os aplicativos ao Codex, use
  scripts/local.ps1 codex ou bash scripts/local.sh codex depois de setup.
  Os links e caminhos absolutos estao em .local/codex-projects.json; a pagina
  .local/codex-projects.html e os atalhos nativos oferecem a mesma abertura.
  Verifique, com list_projects quando disponivel, se as duas pastas ja estao
  cadastradas como projetos. Abrir uma conversa por link nao confirma o cadastro.
  Se nao houver ferramenta para cadastrar uma pasta, informe os caminhos completos
  e oriente a pessoa a usar Criar projeto. Nao altere bancos ou arquivos internos
  do aplicativo Codex para forcar o cadastro.
- O frontend e executado em modo de desenvolvimento com a pasta
  sources/frontend montada no container e atualizacao automatica de arquivos.
  Depois de alterar componentes ou estilos, aguarde a recarga do Next.js ou
  atualize a pagina; nao reinicie os containers por mudancas comuns de interface.
  O backend usa Uvicorn com reload e arquivos montados; tarefas Celery ja carregadas
  exigem reinicio dos workers. Dependencias e Dockerfiles exigem novo build.
- Nunca imprima .local/*.env, secrets.json, access.txt, tokens ou senhas no chat.
  Abra access.txt no editor local para a pessoa consultar o primeiro acesso.
- sources/ e .local/ sao privados e ignorados pelo Git. Publique apenas arquivos
  explicitamente revisados do instalador; nunca copie codigo dos apps para este repo.
- setup pode parar os containers deste instalador, mas deve preservar os volumes,
  senhas existentes e alteracoes nos checkouts. Nao execute down -v nem git reset.
- O banco e preparado pelo bootstrap local atual, sem reproduzir a historia
  legada do Alembic. Nunca aponte este instalador para bancos compartilhados.
- No primeiro preparo de um banco novo, o backend fixado por sources.lock
  executa scripts/seed_review_app.py uma vez. Esse dataset e sintetico, nao faz
  chamadas externas e compartilha a senha local do admin. Desative as tarefas
  Review — de exemplo para que nao acionem integracoes reais. Checkouts existentes
  sem esse seeder devem ser preservados e informados, nao atualizados em silencio.
- O banco e Redis sao locais, mas Hub, IA, S3, email, Slack, robos e MCPs usam
  os servicos reais configurados no segredo. Nao declare todos os objetivos
  validados apenas pelo login. O doctor consulta Hub por GET /api/customers e
  verifica sessao local, sem disparar analises ou mostrar dados dos clientes.
- Use HTTPS com verificacao TLS para o Hub. O IP 100.55.149.93 e acessivel
  por HTTPS deste ambiente; nao pertence ao bloco 100.64.0.0/10.
- Rode python -m unittest discover -s tests -v, bash -n scripts/local.sh e
  os testes PowerShell antes de publicar alteracoes.
- Para alteracoes de macOS, valide scripts/macos.sh e macos-askpass.sh com
  ShellCheck e Bash 3.2. Os testes usam comandos simulados; nao substituem uma
  instalacao em Mac limpo com janelas e permissoes reais.
- Atualizacoes de sources.lock exigem novo smoke test com os dois aplicativos.
