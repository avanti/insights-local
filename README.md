# Avanti Insights local

Instalador para executar o Avanti Insights AI e o Backend Insights no computador,
com integrações reais e acesso pelo localhost. Suporta Windows, macOS e Linux.
Frontend, API, PostgreSQL, Redis, workers e scheduler ficam locais. As análises
usam Hub, OpenAI, Anthropic e os demais serviços configurados pela Avanti.

O repositório do instalador é público. Os aplicativos e as credenciais continuam
privados. Não existe modo de demonstração: o setup prepara o ambiente funcional.

## Começar pelo Codex

A pessoa precisa ter o Codex instalado, internet e contas autorizadas no GitHub e
na AWS da Avanti. Não precisa instalar Git, Docker, Python, Node ou AWS CLI antes.
O administrador precisa preparar as permissões AWS descritas abaixo. A pessoa
também deve conhecer o ID ou alias da conta AWS, caso a tela de login solicite.

Copie este pedido para uma conversa **local** no Codex:

> Instale e configure o Avanti Insights neste computador até a interface local
> estar pronta para uso com as integrações reais. Trabalhe com a maior autonomia
> possível: identifique Windows, macOS ou Linux, escolha e execute os passos
> apropriados e verifique o resultado. Peça minha interação somente quando uma
> etapa depender de mim, como autenticação, confirmação do sistema, permissão de
> administrador ou reinicialização. Para as demais etapas, execute o trabalho e
> informe o progresso em português, de forma breve. Instale Git, se estiver
> ausente, pelo gerenciador oficial do sistema e confirme que o comando funciona.
>
> No macOS, se o Git estiver ausente, execute /usr/bin/xcode-select --install
> pelas ferramentas locais do Codex. Não me peça para abrir o Terminal nem copiar
> comandos. Oriente-me apenas a confirmar a instalação das Xcode Command Line
> Tools e aceitar os termos na janela do macOS. Continue acompanhando a instalação
> até o comando git funcionar. O aplicativo Xcode completo não é necessário.
>
> Escolha uma pasta permanente e execute
> git clone https://github.com/avanti/insights-local.git. Entre nela e leia
> README.md e AGENTS.md. Se já existir uma instalação, use a mesma pasta e
> preserve o código, o banco e as senhas. Use sempre o clone completo do instalador.
>
> Execute .\scripts\local.ps1 setup no Windows ou bash scripts/local.sh setup
> no macOS/Linux. Os scripts devem instalar as dependências, clonar os dois
> aplicativos privados, buscar as credenciais no AWS Secrets Manager e iniciar
> o ambiente completo. Não use modo demo nem peça que eu preencha chaves de API
> individualmente. No macOS, use o fluxo Homebrew para as instalações; não abra
> páginas de download nem peça que eu monte DMGs ou arraste aplicativos.
>
> Conduza o login GitHub e o login AWS pelo navegador quando forem necessários.
> Use terminal interativo do Codex para iniciar esses comandos, se necessário.
> Na AWS, use aws login com o perfil avanti-insights-local: eu informo usuário,
> senha e MFA somente na página oficial da AWS. Nunca peça senhas, códigos MFA,
> tokens ou chaves de API no chat. Se faltar uma permissão AWS, identifique qual
> permissão precisa ser concedida pelo administrador; não tente contornar o bloqueio.
>
> Não interrompa o fluxo para pedir autorização ou confirmação de etapas que
> você consegue executar. Explique somente a ação que realmente depende de mim,
> aguarde essa etapa e retome o trabalho automaticamente. Acompanhe downloads e
> instalações; não encerre enquanto alguma etapa ainda estiver trabalhando. Se
> algo falhar, consulte o erro original e os diagnósticos locais antes de me
> orientar: .local/setup-progress.txt e, no macOS, .local/install-macos.log.
> Se a revisão automática bloquear uma ação, explique a ação e o motivo retornado
> e preserve a preparação.
>
> Execute doctor. Confirme a interface, login, sessão, os dois workers e a leitura
> autenticada do Hub. Abra .local/access.txt no editor para eu consultar meu acesso,
> sem mostrar a senha no chat. Abra o localhost no navegador e verifique o login
> com as ferramentas disponíveis. Não execute análises pagas apenas para concluir
> a instalação; mostre como eu posso testar um objetivo pela interface.
>
> Depois, execute .\scripts\local.ps1 codex no Windows ou
> bash scripts/local.sh codex no macOS/Linux para abrir frontend e backend no Codex.
> Confira se as duas pastas aparecem na barra lateral. Abrir o link não comprova
> cadastro permanente: se necessário, mostre os caminhos de
> .local/codex-projects.json e oriente-me a usar Criar projeto. Ao terminar,
> mostre o link do localhost e as integrações que ainda exigem configuração.

A pasta deve ser permanente, fora de /tmp e de diretórios temporários. Se houver
reinicialização ou interrupção, diga **continuar** na mesma conversa. Repetir
setup busca as credenciais novamente, preserva o banco, o primeiro acesso e os
checkouts existentes, inclusive código modificado pelo Codex.

## O que a pessoa confirma

Os comandos são executados pelo Codex. A pessoa pode precisar confirmar:

- instalação das ferramentas Apple, autorização de administrador ou WSL;
- termos e primeira abertura do Docker Desktop;
- login GitHub, MFA e autorização da organização;
- login AWS, MFA e autorização para uso local;
- reinicialização do sistema, quando solicitada.

Não é preciso copiar chaves AWS para o terminal. AWS CLI 2.32.0 ou posterior
oferece login com as credenciais do Console pelo navegador. O instalador usa um
perfil próprio e reutiliza uma sessão válida. Se a Avanti usar IAM Identity
Center, pode-se selecionar um perfil SSO já configurado. Referência:
[login AWS para desenvolvimento local](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-sign-in.html).

## Preparação única pelo administrador da Avanti

Cada colaborador precisa de acesso aos repositórios privados indicados em
sources.lock e de uma identidade AWS com login no Console da conta correta.
Para o fluxo padrão de navegador, essa identidade precisa de:

1. política gerenciada **SignInLocalDevelopmentAccess**, para autorizar o login
   da CLI com credenciais temporárias;
2. **secretsmanager:GetSecretValue** no segredo **synapse/review-app/env**,
   localizado em **us-east-1**;
3. **kms:Decrypt** na chave correspondente, somente se o segredo usar uma chave
   KMS gerenciada pelo cliente.

[Política de login AWS](https://docs.aws.amazon.com/aws-managed-policy/latest/reference/SignInLocalDevelopmentAccess.html)
e [permissões para ler segredos](https://docs.aws.amazon.com/secretsmanager/latest/userguide/retrieving-secrets_cli.html).
O modelo templates/aws-secret-read-policy.json tem ACCOUNT_ID como marcador:
o administrador deve substituí-lo ou usar o ARN exato do segredo. O instalador
não cria usuários IAM nem altera permissões da conta.

O segredo é um objeto JSON com nomes de variáveis e valores de texto, como no
Review App. Deve conter as chaves de OpenAI, Anthropic, AWS/S3, Slack e Hub, mais
as configurações GA4 de envelope: GA4_CREDENTIALS_PRIVATE_KEY_B64,
GA4_CREDENTIALS_KEY_ID e GA4_CREDENTIALS_SERVICE_TOKEN. Quando GitHub MCP estiver
habilitado, também precisa das três variáveis GITHUB_CREDENTIALS equivalentes.
MCPs habilitados precisam de endpoint e autenticação compatíveis. O setup
informa somente os nomes das variáveis faltantes e interrompe a preparação se
as credenciais obrigatórias estiverem incompletas.

## Credenciais e serviços reais

O setup recebe o segredo pela entrada padrão de um container de configuração,
valida o JSON e salva .local/integrations.env. Não imprime valores nem salva a
resposta JSON bruta. Gera .local/backend.env e .local/frontend.env com as
credenciais necessárias a cada aplicativo. Chaves de Hub, AWS e descriptografia
ficam apenas no backend. Chaves OpenAI/Anthropic usadas por rotas do Next.js
ficam no servidor do frontend, sem prefixo NEXT_PUBLIC_.

Os endereços de banco, Redis, backend, frontend e CORS são sempre gerados para
esta instalação. Senhas de banco, sessão, token interno e usuário inicial são
locais e preservadas. O segredo do Review App não troca o banco local por um
banco compartilhado nem direciona o frontend para uma API de produção.

Hub usa https://100.55.149.93.nip.io com verificação TLS. No ambiente validado,
o acesso funcionou com conexão à internet e a chave de API, sem VPN ou ajuste
manual de rede. O setup obtém essa chave do segredo AWS e faz uma leitura
autenticada GET /api/customers, descartando a resposta. Uma rede corporativa com
bloqueios específicos ainda pode impedir a conexão, mas não é esperada uma
configuração adicional para o uso normal.

Análises, uploads, notificações e serviços remotos usam as contas reais do
segredo, incluindo consumo de IA e armazenamento no S3. O histórico e os
agendamentos são locais. Agendamentos salvos nesse banco podem executar quando
o scheduler voltar a iniciar. Os colaboradores autorizados a baixar o segredo
terão acesso às credenciais dessas integrações; o administrador deve conceder
essa permissão apenas a quem estiver autorizado a utilizá-las.

Para ajustes individuais, copie .env.example para
.local/integrations.override.env e descomente somente as variáveis necessárias.
Os overrides são aplicados depois do segredo; não conseguem substituir os
endereços do banco, Redis ou os tokens locais. setup atualiza o segredo e
preserva os overrides. Não adicione valores vazios para chaves obrigatórias.
Google Sheets é opcional e, por decisão da Avanti, não faz parte dos requisitos
deste setup. Recursos dependentes de planilhas só funcionarão se forem
configurados posteriormente. Recursos de Jira e outras integrações adicionais
precisam das contas e credenciais correspondentes. O instalador não cria
conexões de clientes no Hub ou provisiona esses serviços externos.

## Sistemas e dependências

- **Windows:** versão compatível com Docker Desktop, virtualização habilitada,
  App Installer/winget e PowerShell 5.1 ou posterior. O script instala Git,
  GitHub CLI, AWS CLI e Docker Desktop e prepara WSL quando necessário.
- **macOS:** Intel ou Apple Silicon em versão suportada pelo Docker Desktop e
  Homebrew. O Codex inicia as Command Line Tools quando necessárias. O script
  prepara Homebrew, instala GitHub CLI, AWS CLI e Docker Desktop por Brew e
  acompanha a primeira abertura do Docker. O suporte Intel do Brew pode exigir
  validação adicional. Não precisa instalar Xcode completo.
- **Linux:** instalação automática em Ubuntu, Debian e Fedora. Docker Engine,
  Compose e utilitários são instalados pelo gerenciador do sistema. AWS CLI v2
  usa o pacote oficial x86_64/ARM64 com assinatura PGP verificada antes da
  instalação. A chave pública em scripts/aws-cli-public-key.asc foi obtida na
  [documentação oficial da AWS](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html);
  fingerprint FB5DB77FD5C118B80511ADA8A6310ACC4672475C.
  A CLI é instalada em ~/.local/share/avanti-aws-cli e ~/.local/bin.
  Outras distribuições precisam preparar as dependências manualmente.

O primeiro build baixa bibliotecas e navegadores e pode levar vários minutos.
O script instala apenas dependências ausentes ou AWS CLI antiga. Usa o contexto
Docker disponível e não troca globalmente o contexto da pessoa. Os arquivos
privados usam permissão 600 no macOS/Linux. No Windows, o script restringe as
ACLs de .local ao usuário atual, SYSTEM e Administradores.

No macOS, a senha de administrador é informada na janela local. O helper
macos-askpass.sh é exclusivo do sudo e não deve ser executado separadamente ou
ter sua saída capturada. Cancelar uma janela preserva a preparação. Homebrew
utiliza o instalador oficial do Docker internamente; uma falha real de montagem
precisa de diagnóstico, mesmo usando Brew.

Referências: [Docker Compose](https://docs.docker.com/compose/install/),
[Docker Windows](https://docs.docker.com/desktop/setup/install/windows-install/),
[Docker macOS](https://docs.docker.com/desktop/setup/install/mac-install/),
[Docker Linux](https://docs.docker.com/engine/install/),
[Homebrew](https://docs.brew.sh/Installation).

## Comandos e manutenção

macOS/Linux:

```bash
bash scripts/local.sh setup
bash scripts/local.sh doctor
bash scripts/local.sh start
bash scripts/local.sh stop
bash scripts/local.sh status
bash scripts/local.sh codex
```

Windows:

```powershell
.\scripts\local.ps1 setup
.\scripts\local.ps1 doctor
.\scripts\local.ps1 start
.\scripts\local.ps1 stop
.\scripts\local.ps1 status
.\scripts\local.ps1 codex
```

- setup instala, clona, autentica, busca as credenciais, configura e inicia.
- start reutiliza a configuração privada existente, sem precisar baixar o
  segredo novamente ou refazer login AWS.
- stop para somente esta stack e preserva volumes e arquivos.
- status mostra os serviços e o endereço local.
- doctor verifica Compose, sessão local e acesso ao Hub; não dispara análises.
- codex abre as pastas dos aplicativos usando os atalhos do host. O cadastro
  permanente na barra lateral deve ser confirmado no aplicativo Codex.

No Bash, use --root, --port, --api-port, --no-browser, --non-interactive e
--project frontend|backend|all. No Windows, os equivalentes são -Root, -Port,
-ApiPort, -NoBrowser, -NonInteractive e -Project. Portas mudam por setup.
Não há --mode ou -Mode. Instalações antigas em demo devem executar setup uma
vez para migrar; o banco, as senhas e o código permanecem preservados.

Configurações avançadas, definidas como variáveis de ambiente antes do setup:

- INSIGHTS_AWS_PROFILE: perfil da pessoa; padrão avanti-insights-local.
- INSIGHTS_AWS_REGION: região do segredo; padrão us-east-1.
- INSIGHTS_SECRET_ID: nome ou ARN autorizado; padrão synapse/review-app/env.
- INSIGHTS_AWS_LOGIN_METHOD: console (padrão, aws login) ou sso para um perfil
  IAM Identity Center já configurado.
- INSIGHTS_DOCKER_CONTEXT: seleciona um contexto Docker só para os comandos.
- INSIGHTS_PROJECT_NAME: nome desta stack; use o mesmo nome para iniciar/parar.

A sessão AWS de navegador é temporária. Se setup pedir login novamente, conclua
a janela e retome. Um erro AccessDenied ao ler o segredo precisa ser resolvido
pelo administrador; novo login não concede permissões inexistentes. Se quiser
atualizar as chaves após uma rotação, repita setup. Não imprima arquivos .env,
secrets.json ou access.txt no chat, nem use debug da AWS para capturar credenciais.

## Acesso e alterações no código

A interface padrão fica em http://localhost:3000 e a API em
http://localhost:8000. O administrador local é admin@example.com; a senha
aleatória está em .local/access.txt. Esse usuário possui permissões locais para
utilizar os objetivos. Clientes e conexões reais devem ser selecionados pelo
fluxo do Hub disponível na interface. O banco não copia dados de produção.

No primeiro preparo do banco, o instalador também executa o seeder do Review
App incluído no backend fixado em `sources.lock`. Ele preenche o banco local com
clientes, históricos e resumos sintéticos, sem chamar serviços externos. A senha
das contas sintéticas é a mesma do administrador local; o arquivo
`.local/access.txt` indica onde consultar a lista de usuários. O seeder roda uma
vez por banco. Suas tarefas agendadas de exemplo ficam inativas para não disparar
análises reais depois da instalação. Se forem ativadas manualmente, passam a usar
as integrações reais configuradas no ambiente.

O frontend roda Next.js em desenvolvimento com sources/frontend montado e
observação por polling. Mudanças em componentes e estilos recarregam a página
sem reiniciar containers. O backend monta sources/backend/app e usa Uvicorn
com reload/polling. No Docker Desktop a sincronização pode levar alguns segundos.

Código de tarefas Celery já carregadas exige reiniciar worker e
playwright_worker; dependências e Dockerfiles exigem reconstrução. O Codex deve
identificar o serviço afetado e preservar o banco. Não execute down -v.

sources.lock fixa versões aprovadas para novos clones. setup não faz pull,
reset ou checkout em um repositório já instalado. Checkouts alterados ou em
outra branch são reutilizados, preservando o trabalho da pessoa. Atualizar
sources.lock exige validar novamente a combinação dos aplicativos.

sources/ e .local/ são privados e ignorados pelo Git. Arquivos de acesso,
credenciais, logs e atalhos ficam em .local. Os arquivos
.local/codex-projects.html e .local/codex-projects.json mostram os caminhos
absolutos das duas pastas. Se os atalhos não cadastrarem os projetos, use
Criar projeto no Codex e selecione cada pasta indicada.
