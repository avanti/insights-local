# Avanti Insights local

Instalador para executar o Avanti Insights AI e o Backend Insights no computador,
com integrações reais e acesso pelo localhost. Suporta Windows, macOS e Linux.
Frontend, API, PostgreSQL, Redis, workers e scheduler ficam locais. As chamadas de
IA, Hub, S3, Slack e outros serviços usam as configurações privadas do backend.

O repositório do instalador é público; os aplicativos e as credenciais continuam
privados. Não existe modo de demonstração. O setup instala as dependências locais,
clona os dois projetos e só inicia os serviços depois de validar o arquivo privado
`sources/backend/.env`.

## Começar com um agente de IA

O computador precisa ter um agente de IA para programação com acesso ao terminal
e aos arquivos locais, acesso à internet, permissão para usar
os repositórios privados Avanti indicados em `sources.lock` e acesso seguro às
configurações de integração do backend. Git, Docker, Docker Compose, Python e Node
não precisam estar instalados previamente. A instalação pode solicitar confirmação
do sistema, autorização de administrador, login GitHub ou reinicialização.

Copie este pedido para uma conversa **local** do agente, com acesso ao terminal
deste computador:

> Instale e configure o Avanti Insights neste computador até a interface local
> estar pronta para uso com as integrações reais. Trabalhe com a maior autonomia
> possível: identifique Windows, macOS ou Linux, escolha e execute os passos
> apropriados e verifique o resultado. Peça minha interação somente quando uma
> etapa depender de mim, como autenticação, confirmação do sistema, permissão de
> administrador, configuração privada ou reinicialização. Para as demais etapas,
> execute o trabalho e informe o progresso em português, de forma breve. Instale
> Git, se estiver ausente, pelo gerenciador oficial do sistema e confirme que o
> comando funciona.
>
> Antes de clonar os aplicativos, confira se `git config --global user.name` e
> `git config --global user.email` já estão definidos. Preserve qualquer valor
> existente. Se algum estiver ausente, explique que esses dados identificam a
> autoria dos commits feitos neste computador e não servem para autenticar no
> GitHub; pergunte somente o valor que falta e execute o comando correspondente,
> substituindo o texto entre aspas pelo valor que eu informar:
>
> - `git config --global user.name "Nome informado pelo usuário"`
> - `git config --global user.email "email informado pelo usuário"`
>
> Nunca configure esses exemplos literalmente. Se eu preferir não configurar
> agora, continue a instalação e avise que commits futuros podem exigir essa
> configuração.
>
> No macOS, se o Git estiver ausente, execute `/usr/bin/xcode-select --install`
> pelas ferramentas locais do agente. Não me peça para abrir o Terminal nem copiar
> comandos. Oriente-me apenas a confirmar a instalação das Xcode Command Line
> Tools na janela do macOS. Continue acompanhando até `git` funcionar. O aplicativo
> Xcode completo não é necessário.
>
> Escolha uma pasta permanente e execute
> `git clone https://github.com/avanti/insights-local.git`. Entre nela e leia
> `README.md` e `AGENTS.md`. Se já existir uma instalação, use a mesma pasta e
> preserve código, banco, senhas e alterações locais. Use o clone completo do
> instalador.
>
> Execute `.\scripts\local.ps1 setup` no Windows ou
> `bash scripts/local.sh setup` no macOS/Linux. Os scripts devem instalar as
> dependências e clonar os aplicativos privados. Quando o setup informar que
> falta `sources/backend/.env`, pare antes de iniciar qualquer serviço de backend.
> Oriente-me a copiar `sources/backend/.env.example` para `sources/backend/.env`
> e preencher os valores privados localmente, usando o canal seguro da Avanti.
> Não peça que eu envie, cole ou dite chaves, senhas ou o conteúdo desse arquivo
> no chat. Não leia nem imprima os valores. Depois que eu confirmar que o arquivo
> foi preenchido, execute setup novamente. Se faltarem configurações, mostre apenas
> os nomes das variáveis necessárias.
>
> Não instale AWS CLI, não abra login da AWS e não consulte AWS Secrets Manager.
> As credenciais AWS usadas pelo backend durante a execução ficam no arquivo
> privado `sources/backend/.env`; não são credenciais do instalador. No macOS,
> use o fluxo Homebrew para as instalações. Não abra páginas para baixar Docker
> nem peça que eu monte DMGs ou arraste aplicativos.
>
> Conduza o login GitHub pelo navegador quando necessário. Use um terminal
> interativo para iniciar o login. Nunca peça senha, código MFA, token ou
> chave de API no chat. Se algo falhar, consulte o erro original e os diagnósticos
> locais antes de me orientar: `.local/setup-progress.txt` e, no macOS,
> `.local/install-macos.log`. Não contorne uma rejeição da revisão automática.
>
> Após a instalação, execute `doctor`. Confirme a interface, o login, a sessão,
> os dois workers e a conexão autenticada ao Hub. Abra `.local/access.txt` no
> editor para eu consultar meu acesso, sem mostrar a senha no chat. Abra o
> localhost no navegador e verifique o login com as ferramentas disponíveis.
> Não execute análises pagas apenas para concluir a instalação.
>
> Ao terminar, mostre o link do localhost, os caminhos do frontend e do backend
> registrados em `.local/projects.json` e as integrações que ainda exigem
> configuração.

A pasta da instalação deve ser permanente, fora de `/tmp` e de diretórios
temporários. Se houver reinicialização ou interrupção, diga **continuar** na mesma
conversa. Depois de criar o `.env`, execute setup novamente na mesma pasta. Os
scripts preservam o banco, o primeiro acesso e os checkouts existentes, inclusive
código modificado localmente.

## Arquivo privado do backend

O setup clona o backend antes de solicitar as configurações privadas. Se
`sources/backend/.env` não existir, a execução para nesse ponto e não inicia os
serviços. Copie o exemplo que vem no repositório privado do backend:

- macOS/Linux: `cp sources/backend/.env.example sources/backend/.env`
- Windows PowerShell: `Copy-Item sources/backend/.env.example sources/backend/.env`

Preencha o `.env` localmente com os valores fornecidos pela Avanti por um canal
seguro. Não use chats de assistentes de IA para transportar segredos. A proteção do arquivo
é aplicada pelo launcher: permissão `600` em macOS/Linux e ACLs restritas no
Windows. O próprio repositório também ignora arquivos `.env`.

O setup valida estas variáveis antes de gerar a configuração e iniciar os
serviços:

- `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`;
- `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_S3_BUCKET`;
- `SLACK_BOT_TOKEN`, `MARKETING_HUB_API_KEY`;
- `GA4_CREDENTIALS_PRIVATE_KEY_B64`, `GA4_CREDENTIALS_KEY_ID` e
  `GA4_CREDENTIALS_SERVICE_TOKEN`.

Se Merchant MCP ou Jobber MCP estiver habilitado, informe o endpoint e, quando
exigida, a autenticação correspondente. GitHub MCP habilitado também exige as
três variáveis `GITHUB_CREDENTIALS_*`. O setup informa apenas nomes de variáveis
ausentes ou incompletas. Google Sheets é opcional e não é requisito para esta
instalação.

As credenciais AWS listadas são usadas pela aplicação em runtime para integração
com S3 e outros recursos configurados. A pessoa não precisa ter AWS CLI, fazer
login AWS, ter permissão de Secrets Manager nem fornecer credenciais AWS ao
instalador.

O script gera `.local/backend.env` e `.local/frontend.env`, distribuindo as
configurações necessárias a cada aplicativo. Hub, AWS e credenciais de
descriptografia ficam somente no backend. Chaves usadas por rotas do Next.js
ficam no servidor do frontend, sem prefixo `NEXT_PUBLIC_`. Os endereços de banco,
Redis, backend, frontend e CORS são sempre locais. Senhas de banco, sessão, token
interno e usuário inicial são gerados localmente e preservados em setups futuros.

O Hub usa `https://100.55.149.93.nip.io` com verificação TLS. É possível alterar
o endpoint para esta instalação em `.local/integrations.override.env`, usando
`.env.example` como referência. O setup verifica uma chamada autenticada somente
depois que os serviços estão prontos: `GET /api/customers`. A resposta é
descartada e não são iniciadas análises.

O uso das integrações reais pode consumir créditos de IA e armazenamento S3.
Histórico e agendamentos ficam no banco local. Tarefas agendadas podem executar
quando o scheduler voltar a iniciar; desative tarefas Review de exemplo para que
não acionem integrações reais. O instalador não cria conexões de clientes no Hub
nem provisiona serviços externos.

## Sistemas e dependências

- **Windows:** PowerShell 5.1 ou posterior, virtualização habilitada e App
  Installer/`winget`. O script instala Git, GitHub CLI e Docker Desktop e prepara
  WSL quando necessário. Os termos do Docker e a reinicialização precisam ser
  confirmados localmente quando solicitados.
- **macOS:** versão compatível com Docker Desktop e Homebrew. As Command Line
  Tools da Apple são instaladas quando necessárias; elas fornecem o Git. O script
  prepara Homebrew, instala GitHub CLI e Docker Desktop por Brew e acompanha a
  primeira abertura do Docker. Não é necessário instalar o Xcode completo.
- **Linux:** instalação automática em Ubuntu, Debian e Fedora. Docker Engine,
  Compose e utilitários são instalados pelo gerenciador do sistema. Outras
  distribuições precisam preparar dependências manualmente.

O primeiro build baixa bibliotecas e navegadores e pode levar vários minutos.
No macOS, a senha de administrador deve ser informada na janela local. O helper
`macos-askpass.sh` é exclusivo do sudo; não o execute separadamente nem capture
sua saída. Cancelar uma janela preserva a preparação.

Referências: [Docker Compose](https://docs.docker.com/compose/install/),
[Docker Windows](https://docs.docker.com/desktop/setup/install/windows-install/),
[Docker macOS](https://docs.docker.com/desktop/setup/install/mac-install/),
[Docker Linux](https://docs.docker.com/engine/install/) e
[Homebrew](https://docs.brew.sh/Installation).

## Comandos e manutenção

macOS/Linux:

```bash
bash scripts/local.sh setup
bash scripts/local.sh doctor
bash scripts/local.sh start
bash scripts/local.sh stop
bash scripts/local.sh status
```

Windows:

```powershell
.\scripts\local.ps1 setup
.\scripts\local.ps1 doctor
.\scripts\local.ps1 start
.\scripts\local.ps1 stop
.\scripts\local.ps1 status
```

- `setup` instala dependências, clona os aplicativos, espera o `.env`, configura
  e inicia. Se faltar o arquivo, crie-o como indicado e execute setup novamente.
  Os caminhos absolutos dos aplicativos ficam em `.local/projects.json`.
- `start` valida que o `.env` existe e reutiliza a configuração privada existente.
- `stop` para somente esta stack e preserva volumes e arquivos.
- `status` mostra os serviços e o endereço local.
- `doctor` verifica Compose, sessão local, workers e acesso autenticado ao Hub; não
  dispara análises.

No Bash, use `--root`, `--port`, `--api-port`, `--no-browser` e
`--non-interactive`. No Windows, os equivalentes são `-Root`, `-Port`, `-ApiPort`,
`-NoBrowser` e `-NonInteractive`.
Portas mudam por setup. Não há opção de modo demo.

As configurações opcionais de ambiente são `INSIGHTS_DOCKER_CONTEXT`, para
selecionar um contexto Docker apenas nos comandos do instalador, e
`INSIGHTS_PROJECT_NAME`, para nomear esta stack (use o mesmo nome ao iniciar ou
parar). Não é necessário configurar perfil AWS.

## Acesso e alterações no código

A interface padrão fica em `http://localhost:3000` e a API em
`http://localhost:8000`. O administrador local é `admin@example.com`; a senha
aleatória fica em `.local/access.txt`. Esse usuário tem permissões locais para
utilizar os objetivos. Clientes e conexões reais devem ser selecionados pelo
fluxo do Hub disponível na interface. O banco não copia dados de produção.

No primeiro preparo do banco, o instalador executa uma vez o seeder do Review App
incluído no backend fixado em `sources.lock`. Ele preenche o banco local com
clientes, históricos e resumos sintéticos, sem chamar serviços externos. A senha
das contas sintéticas é a mesma do administrador local; `.local/access.txt`
indica onde consultar a lista de usuários. As tarefas agendadas de exemplo ficam
inativas para não disparar análises reais.

O frontend roda Next.js em desenvolvimento com `sources/frontend` montado e
observação por polling. Mudanças em componentes e estilos recarregam a página sem
reiniciar containers. O backend monta `sources/backend/app` e usa Uvicorn com
reload/polling. No Docker Desktop, a sincronização pode levar alguns segundos.

Código de tarefas Celery já carregadas exige reiniciar `worker` e
`playwright_worker`; dependências e Dockerfiles exigem reconstrução. Reinicie
apenas o serviço afetado e preserve o banco. Não execute `down -v`.

`sources.lock` fixa versões aprovadas para novos clones. Setup não faz pull,
reset ou checkout em repositórios já instalados. Checkouts alterados ou em outra
branch são reutilizados, preservando o trabalho local. Atualizar `sources.lock`
exige validar novamente a combinação dos aplicativos.
