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
- Antes de clonar os aplicativos, verifique se `git config --global user.name` e
  `git config --global user.email` estão definidos. Preserve os valores
  existentes. Se faltar algum, explique que nome e email identificam a autoria
  dos commits nesta máquina, não autenticam no GitHub e valem para todos os
  repositórios do usuário; pergunte apenas o que falta e execute o comando
  correspondente, substituindo o exemplo pelo valor informado:
  - `git config --global user.name "..."`
  - `git config --global user.email "..."`
  Nunca use placeholders literalmente. Se a pessoa preferir não configurar agora,
  prossiga com a instalação e avise que commits futuros podem exigir essa
  configuração.
- No macOS, execute /usr/bin/xcode-select --install pelas ferramentas locais do
  agente quando o Git estiver indisponível. Não delegue à pessoa a abertura do
  Terminal nem a cópia de comandos. Peça apenas as confirmações da janela do macOS,
  acompanhe a instalação e confirme /usr/bin/git --version antes de continuar.
  Use as Xcode Command Line Tools; o aplicativo Xcode completo não é necessário.
- Execute doctor e a verificação de login antes de declarar o ambiente pronto.
- Se as portas estiverem ocupadas, escolha portas livres com as ferramentas do
  sistema e repita setup com os parâmetros de porta. Não pare outros aplicativos.
  Ao concluir, abra o localhost e o acesso local no editor. Se o navegador estiver
  disponível, verifique o login sem mostrar a senha no chat.
- Os caminhos absolutos do frontend e do backend no computador ficam em
  .local/projects.json, gerado pelo setup. Quando a pessoa pedir para abrir os
  aplicativos no editor ou na ferramenta que estiver usando, informe esses
  caminhos. Não altere bancos ou arquivos internos de outras ferramentas para
  cadastrar projetos.
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
- Para pedidos de alteração nos aplicativos frontend/backend, siga o fluxo
  obrigatório em "Alterações nos aplicativos" abaixo antes de editar código.
- Rode python -m unittest discover -s tests -v, bash -n scripts/local.sh e os
  testes PowerShell antes de publicar alterações.
- Para alterações de macOS, valide scripts/macos.sh e macos-askpass.sh com
  ShellCheck e Bash 3.2. Os testes usam comandos simulados; não substituem uma
  instalação em Mac limpo com janelas e permissões reais.
- Atualizações de sources.lock exigem novo smoke test com os dois aplicativos.

## Alterações nos aplicativos

Estas regras se aplicam quando a solicitação envolve `avanti-insights-ai` ou
`backend-insights`, incluindo código, documentação, testes, dependências e
configuração. O instalador `insights-local` é um repositório separado. Localize
os caminhos reais dos dois aplicativos por `.local/projects.json` e
confirme cada raiz Git; não presuma que os clones estão dentro de `sources/`.

### Estado local, atualização e branches

- Antes de começar uma nova tarefa de alteração, confira a branch e
  `git status --short` dos dois aplicativos, mesmo se o pedido mencionar apenas
  um. Identifique mudanças staged, unstaged e arquivos não rastreados. Resuma os
  caminhos e o tipo de mudança ao usuário; não mostre valores de segredos.
- Se houver alterações locais que não pertençam ao trabalho ativo do agente,
  pare e pergunte ao usuário como tratá-las. Não as descarte, sobrescreva, misture,
  faça stash, commit ou troque de branch sem autorização explícita. Não trate as
  alterações produzidas pelo agente na tarefa ativa como trabalho pré-existente:
  mantenha-as na branch dessa tarefa quando o usuário pedir ajustes relacionados.
- No primeiro pedido de alteração de uma nova conversa, informe o nome sugerido
  para a branch, em quais repositórios ela será criada e que as duas `main` serão
  atualizadas; peça confirmação antes de criá-la e não edite os aplicativos antes
  de a branch existir. Uma confirmação explícita para criar a branch, dada no
  próprio pedido, já vale. Se a pessoa pedir para continuar uma tarefa/PR existente
  em outra conversa, confirme e reutilize aquela branch. Reutilize a mesma branch
  nos pedidos complementares da mesma tarefa/conversa; não crie uma branch para
  cada ajuste. Se a tarefa abranger os dois aplicativos, use o mesmo nome de
  branch nos dois. Se afetar apenas um, crie branch somente nele.
- Depois de resolver o estado local e obter a confirmação da branch, atualize a
  branch `main` local de ambos os aplicativos a partir de `origin/main` antes de
  criar a branch de trabalho. Faça fetch e avance `main` somente por fast-forward;
  não use reset forçado nem sobrescreva commits locais. Crie a branch de trabalho
  a partir da `main` atualizada do(s) repositório(s) que serão alterados. Use o
  prefixo `feature/` para funcionalidades e `fix/` para correções, seguido de um
  nome curto que descreva a tarefa.
- Se autenticação, rede, conflito ou divergência impedir a atualização de
  qualquer `main`, pare antes de criar a branch ou alterar os aplicativos.
  Informe qual repositório falhou e o erro confirmado. Só prossiga sem atualizar
  se o usuário autorizar isso explicitamente. Antes de prosseguir, explique que a
  alteração partirá de uma revisão antiga e pode não conter correções ou mudanças
  de contrato recentes, causar conflitos ou não ser compatível com o outro
  aplicativo. Registre qual base desatualizada foi autorizada.

### Reuso, compatibilidade e agendamentos

- Antes de criar componente, função, método, endpoint ou fluxo novo, procure no
  aplicativo por uma implementação reutilizável e siga os padrões existentes.
  Prefira estender a implementação atual a duplicar comportamento. Antes de mudar
  componente, função, método ou contrato compartilhado, localize e revise seus
  usos e testes. Preserve compatibilidade ou atualize todos os consumidores
  afetados; valide os fluxos relacionados com testes de regressão. Não prometa
  que nada será quebrado sem evidência; informe riscos que não puder verificar.
- Para qualquer pedido relacionado a agendamentos — interface, API, criação,
  edição, pausa, execução ou histórico — use e estenda o fluxo de scheduler já
  existente. Na raiz do backend, leia `docs/scheduler_adapters.md` e confira
  `app/api/routes/scheduled_tasks.py`, `app/scheduler/service.py`, o registry e
  os adapters do objetivo. Na raiz do frontend, procure primeiro nas telas,
  ações, rotas e componentes existentes em `app/insights/schedules/` e
  `app/api/schedules/`. Não crie cron, Celery Beat ou outro mecanismo paralelo.
  Se o fluxo atual não comportar o pedido, demonstre a limitação no
  código/documentação e proponha como estendê-lo antes de escolher uma arquitetura
  diferente.

### GA4

- No backend, o servidor MCP oficial do GA4 (`analytics-mcp`, aberto por
  `app/integrations/ga4_mcp.py`) é usado somente pelo objetivo G.A.B.I., em que o
  modelo escolhe as consultas. Não use esse MCP em nenhum outro objetivo, painel,
  script ou endpoint.
- Qualquer outra consulta ao GA4 é feita pelo Avanti Hub: as rotas
  `/api/analytics/*` ou, para relatório sob medida, `POST /api/analytics/report`
  (no backend, `HubGa4Reporter` em `app/integrations/ga4_hub_reports.py`). O Hub
  aplica o limite de consultas simultâneas por cliente, o prazo, o cache e a cota
  do GA4 que todos dividem; uma consulta direta pelo MCP fura esses limites.
- Se o Hub não tiver o que a consulta precisa, não use o MCP como alternativa:
  siga a regra de limites de Labs abaixo e descreva a rota que falta para a equipe
  de Labs criar.

### Verificação de fatos e limites de Labs

- Não invente nem presuma endpoints, campos, permissões, variáveis, efeitos de
  scripts ou comportamento de produção. Antes de propor uma implementação ou dar
  instruções, verifique o código, os contratos OpenAPI/MCP, a documentação ou
  testes relevantes. Para comportamento externo, consulte uma fonte autorizada e
  atual. Separe fatos confirmados de hipóteses; se faltar evidência, diga o que
  não foi possível verificar e pergunte como prosseguir. Não implemente uma
  integração apoiada somente em uma suposição.
- `avanti-hub` e `avanti-mcp-server` são fontes somente para consulta. Nunca
  altere seus arquivos, branches, issues, PRs ou deploys. Se uma solicitação do
  frontend/backend depender de mudança neles, informe que a equipe de Labs deve
  fazê-la. Descreva para encaminhamento: repositório/componente, contrato ou
  comportamento necessário, motivo, evidência encontrada e critério de aceite.
  Não apresente detalhes ainda não confirmados como requisitos certos.

### Pull requests, produção e merge

- Se o usuário pedir um PR e não indicar a branch de destino, pergunte se deve
  ser `develop` ou `main` e explique: `develop` passa pelos testes da equipe e
  segue para o próximo dia de deploy; `main` não passa pelos testes da equipe e
  só recebe deploy depois da autorização da gestão. Não escolha o destino pelo
  usuário. A abertura de PR não autoriza merge.
- Nunca faça merge automaticamente ao abrir um PR. Informe que o PR ficará
  aberto para revisão; faça merge somente quando o usuário pedir explicitamente.
- Nunca faça deploy por iniciativa própria. Mesmo quando o usuário pedir
  deploy, prepare e revise a mudança, informe o ambiente, a branch/commit e a
  ação que será executada e solicite uma confirmação final antes de iniciar.
- Em todo PR, verifique e declare na descrição se há variável de ambiente a
  configurar antes do deploy ou script a executar depois dele. Inclua uma seção
  `Configuração e pós-deploy` e informe uma destas situações: ações necessárias,
  nenhuma ação necessária, ou verificação pendente. Para cada ação, indique o
  nome da variável sem valor secreto, onde configurá-la, o comando/script e a
  ordem/momento de execução. Avise também o usuário. Nunca inclua segredos no PR.
