# Avanti Insights local

Este repositorio público prepara dois aplicativos privados da organização Avanti.

- Leia README.md antes de iniciar. Use scripts/local.ps1 no Windows e
  scripts/local.sh no macOS/Linux. O primeiro comando é setup.
- Conduza a pessoa até a interface local. Use português e mensagens curtas sobre
  a etapa atual. Execute os comandos e downloads; a pessoa só deve concluir as
  confirmações necessárias. Não delegue a instalação inteira por uma falha genérica.
- No macOS, siga scripts/macos.sh: Homebrew é preparado se ausente; GitHub CLI e
  Docker são instalados por Brew. Não abra navegador para baixar instaladores nem
  peça que a pessoa monte DMGs ou arraste aplicativos. Leia o script antes de usar.
  Senha de administrador somente na janela local, nunca no chat. O helper
  macos-askpass.sh é exclusivo de sudo; não execute nem registre sua saída.
- Consulte .local/setup-progress.txt e, no macOS, .local/install-macos.log ao
  retomar ou diagnosticar uma falha. Preserve o erro original; não invente sua
  causa. Se uma confirmação estiver pendente, explique uma ação concreta de cada
  vez, a janela correta e como retomar. Acompanhe processos com esperas curtas e
  informe progresso enquanto downloads e instalações ainda estiverem trabalhando.
- Para gh auth login, use terminal interativo quando necessário; a pessoa conclui
  login, 2FA e autorização da organização no navegador. Se a revisão automática
  rejeitar uma ação, identifique essa ação e o motivo retornado, conclua trabalho
  independente e aguarde a resolução. Não use outro meio para contornar a rejeição.
- O setup sempre prepara integrações reais. Não existe modo demo nem opção de modo.
- Depois de clonar os dois aplicativos, confira se sources/backend/.env existe.
  Se estiver ausente, instrua a pessoa a copiar sources/backend/.env.example para
  sources/backend/.env e preencher os valores privados localmente, antes de
  continuar. Não peça valores no chat. Aguarde a confirmação, execute setup de
  novo e não inicie os serviços de backend enquanto o arquivo estiver ausente ou
  incompleto. Diagnósticos podem mostrar nomes de variáveis faltantes, nunca valores.
- Não instale AWS CLI, não solicite login AWS e não acesse Secrets Manager. As
  configurações AWS necessárias ao backend em runtime continuam pertencendo a
  sources/backend/.env. Google Sheets é opcional para este setup.
- O arquivo sources/backend/.env deve continuar local e protegido. Nunca o leia
  em voz alta, imprima, copie para o repositório público ou mostre seus valores.
  No Windows, restrinja suas ACLs ao usuário atual, SYSTEM e Administradores; no
  macOS/Linux, mantenha permissão 600. O launcher prepara essa proteção.
- Verifique acesso aos repositórios privados indicados em sources.lock. Login
  GitHub, senha sudo, termos do Docker e reinicialização devem ser concluídos pela
  pessoa quando exigidos.
- Se o Git estiver ausente, instale-o pelo mecanismo oficial do sistema e confirme
  que git funciona antes de clonar este repositório, conforme o prompt no README.
- No macOS, execute /usr/bin/xcode-select --install pelas ferramentas locais do
  Codex quando o Git estiver indisponível. Não delegue à pessoa a abertura do
  Terminal nem a cópia de comandos. Peça apenas as confirmações da janela do macOS,
  acompanhe a instalação e confirme /usr/bin/git --version antes de continuar.
  Use as Xcode Command Line Tools; o aplicativo Xcode completo não é necessário.
- Execute doctor e a verificação de login antes de declarar o ambiente pronto.
- Se as portas estiverem ocupadas, escolha portas livres com as ferramentas do
  sistema e repita setup com os parâmetros de porta. Não pare outros aplicativos.
  Ao concluir, abra o localhost e o acesso local no editor. Se o navegador estiver
  disponível, verifique o login sem mostrar a senha no chat. A interface deve ficar
  acessível mesmo que o cadastro dos projetos na barra lateral do Codex dependa de
  uma etapa manual posterior.
- Quando a pessoa solicitar abrir ou adicionar os aplicativos ao Codex, use
  scripts/local.ps1 codex ou bash scripts/local.sh codex depois de setup. Os links
  e caminhos absolutos estão em .local/codex-projects.json; a página
  .local/codex-projects.html e os atalhos nativos oferecem a mesma abertura.
  Verifique, com list_projects quando disponível, se as duas pastas já estão
  cadastradas como projetos. Abrir uma conversa por link não confirma o cadastro.
  Se não houver ferramenta para cadastrar uma pasta, informe os caminhos completos
  e oriente a pessoa a usar Criar projeto. Não altere bancos ou arquivos internos
  do Codex para forçar o cadastro.
- O frontend roda em modo de desenvolvimento com sources/frontend montada no
  container e atualização automática de arquivos. Depois de alterar componentes
  ou estilos, aguarde a recarga do Next.js ou atualize a página; não reinicie os
  containers por mudanças comuns de interface. O backend usa Uvicorn com reload e
  arquivos montados; tarefas Celery já carregadas exigem reinício dos workers.
  Dependências e Dockerfiles exigem novo build.
- Nunca imprima .local/*.env, secrets.json, access.txt, tokens ou senhas no chat.
  Abra access.txt no editor local para a pessoa consultar o primeiro acesso.
- sources/ e .local/ são privados e ignorados pelo Git. Publique apenas arquivos
  explicitamente revisados do instalador; nunca copie código dos aplicativos para
  este repositório.
- setup pode parar os containers deste instalador, mas deve preservar volumes,
  senhas existentes e alterações nos checkouts. Não execute down -v nem git reset.
- O banco é preparado pelo bootstrap local atual, sem reproduzir a história
  legada do Alembic. Nunca aponte este instalador para bancos compartilhados.
- No primeiro preparo de um banco novo, o backend fixado por sources.lock executa
  scripts/seed_review_app.py uma vez. O dataset é sintético, não faz chamadas
  externas e compartilha a senha local do admin. As tarefas Review — de exemplo
  ficam inativas para não acionarem integrações reais. Checkouts existentes sem
  esse seeder devem ser preservados e informados, não atualizados em silêncio.
- O banco e Redis são locais, mas Hub, IA, S3, email, Slack, robôs e MCPs usam os
  serviços reais configurados no ambiente. Não declare todos os objetivos
  validados apenas pelo login. O doctor consulta Hub por GET /api/customers e
  verifica a sessão local, sem disparar análises ou mostrar dados dos clientes.
- Use HTTPS com verificação TLS para o Hub. O endpoint padrão é
  https://100.55.149.93.nip.io.
- Rode python -m unittest discover -s tests -v, bash -n scripts/local.sh e os
  testes PowerShell antes de publicar alterações.
- Para alterações de macOS, valide scripts/macos.sh e macos-askpass.sh com
  ShellCheck e Bash 3.2. Os testes usam comandos simulados; não substituem uma
  instalação em Mac limpo com janelas e permissões reais.
- Atualizações de sources.lock exigem novo smoke test com os dois aplicativos.
