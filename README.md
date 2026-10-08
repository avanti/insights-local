# Avanti Insights local

Instalador para executar Avanti Insights AI e Avanti Synapse (Backend Insights)
no computador, usando o Codex como assistente. Suporta Windows, macOS e Linux.

O instalador e publico. Os aplicativos continuam privados: cada pessoa precisa
de uma conta GitHub com acesso a ambos os repositorios da organizacao Avanti.
O codigo dos aplicativos, os dados locais e as credenciais ficam fora do Git
deste repositorio.

## Comecar pelo Codex

Copie este pedido para uma conversa local no Codex:

> Prepare o Avanti Insights local neste computador usando
> https://github.com/avanti/insights-local. Baixe a release v0.1.0 numa pasta
> permanente, leia AGENTS.md e execute setup em modo demo. Instale as dependencias
> ausentes e confirme o login pela interface. Abra .local/access.txt no editor
> para eu consultar o acesso, sem colocar senhas no chat.

O Codex deve escolher uma pasta permanente da pessoa, fora de pastas temporarias.
Quando necessario, a pessoa conclui o login GitHub pelo navegador, informa sua
senha de administrador, aceita os termos do Docker ou reinicia o computador.
Depois basta pedir ao Codex para executar setup novamente.

## Sem Git ou outras ferramentas instaladas

Baixe e extraia [o ZIP da release v0.1.0](https://github.com/avanti/insights-local/archive/refs/tags/v0.1.0.zip).
O ZIP inclui tudo para iniciar a preparacao. Python e Node.js sao usados apenas
nos containers.

Windows, a partir da pasta extraida:

```powershell
.\scripts\local.ps1 setup
```

macOS ou Linux:

```bash
bash scripts/local.sh setup
```

Se o Windows impedir a execucao do arquivo baixado, a pessoa ou o Codex pode
executar o arquivo revisado em um processo separado, sem alterar a politica global:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\local.ps1 setup
```

Tambem e possivel baixar apenas [local.ps1](https://raw.githubusercontent.com/avanti/insights-local/v0.1.0/scripts/local.ps1)
ou [local.sh](https://raw.githubusercontent.com/avanti/insights-local/v0.1.0/scripts/local.sh).
Nesse caso, use -Root no PowerShell ou --root no Bash para escolher a pasta.
O script avulso baixa o restante da mesma release antes de clonar os aplicativos.

## Dependencias e sistemas

- Windows: Windows compativel com Docker Desktop, virtualizacao habilitada,
  App Installer/winget e PowerShell 5.1 ou posterior. O script instala Git,
  GitHub CLI, prepara WSL quando necessario e instala Docker Desktop.
- macOS: Intel ou Apple Silicon, numa versao suportada pelo Docker Desktop.
  O script instala Git via ferramentas Apple quando ausente, GitHub CLI e Docker Desktop.
  A instalacao das ferramentas Apple precisa ser concluida na janela do sistema.
- Linux: instalacao automatica em Ubuntu, Debian e Fedora suportados pelo Docker.
  Instala Git, GitHub CLI, curl, unzip, Docker Engine e Compose. Outras distribuicoes
  podem usar o instalador depois de instalar essas dependencias manualmente.
  O usuario deve ter acesso ao daemon Docker ou sudo autorizado.

O script instala apenas dependencias ausentes; nao reinstala o Codex nem muda
globalmente o contexto Docker. O primeiro build baixa imagens, bibliotecas e
navegadores e pode demorar varios minutos. E preciso internet para essa preparacao.

Referencias: [Docker Compose](https://docs.docker.com/compose/install/),
[Windows](https://docs.docker.com/desktop/setup/install/windows-install/),
[macOS](https://docs.docker.com/desktop/setup/install/mac-install/),
[Linux](https://docs.docker.com/engine/install/).

## Comandos

Os dois scripts aceitam setup, start, stop, status, doctor e help.

- setup instala, clona, gera configuracao e inicia. Pode ser repetido.
- start sobe o ambiente configurado e verifica login e sessao.
- stop para somente a stack local e preserva dados.
- status mostra containers, modo e endereco da interface.
- doctor verifica dependencias, Compose e login; nao instala software.

No Windows use -Mode, -Port, -ApiPort, -NoBrowser e -NonInteractive.
No Bash use --mode, --port, --api-port, --no-browser e --non-interactive.
Modo e portas sao alterados por setup.

Exemplo para portas ocupadas:

```bash
bash scripts/local.sh setup --port 3100 --api-port 8100
```

Por padrao a interface abre em http://localhost:3000 e a API em
http://localhost:8000/docs. As portas sao expostas somente em 127.0.0.1.
PostgreSQL e Redis ficam acessiveis apenas aos containers.

Usuario, senha aleatoria e endereco ficam em .local/access.txt.
setup preserva senhas, banco e checkouts existentes. O administrador local
usa admin@example.com, sem envio de email. Alteracoes em sources/ nunca sao
descartadas automaticamente: o instalador pede que sejam preservadas.

## Modos

### demo (padrao)

Permite login, navegacao e consulta de dados ficticios. O bootstrap cria
administrador, permissoes, catalogo, cliente e historicos locais.

As analises, uploads, alteracoes e integracoes externas retornam uma mensagem
explicando que estao desativadas. Workers e scheduler nao sao iniciados.
Os aplicativos nao tem acesso externo de rede depois do build; somente o
proxy de acesso participa da rede que publica as portas locais. A imagem usa
marcadores sem credenciais reais para compatibilidade com a configuracao
obrigatoria dos aplicativos; esses marcadores nunca habilitam um provedor.

Este modo nao simula respostas novas de IA. Algumas telas dependentes de
integracoes podem ficar indisponiveis. Os dados ficticios sao identificados
como demonstracao.

### connected

Executa analises reais e inicia workers e scheduler, conforme as integracoes
configuradas. Configure credenciais proprias para desenvolvimento em
.local/integrations.env, usando .env.example como modelo.

Ao solicitar connected sem essas credenciais, setup cria o modelo e informa
quais nomes de variaveis faltam. Preencha o arquivo localmente e execute:

```bash
bash scripts/local.sh setup --mode connected
```

As integracoes exigidas hoje pelo backend sao OpenAI, Anthropic, AWS/S3 e Slack.
Recursos especificos podem exigir Marketing Hub, Google Sheets ou outras
integracoes. Este instalador nao provisiona essas contas ou servicos externos.

Ao trocar de modo, setup recria os containers e a rede preservando o banco.
Se voce tiver criado agendamentos em connected, eles podem voltar a executar
quando connected for iniciado novamente.

## Configuracao e manutencao

sources.lock fixa os SHAs dos aplicativos para evitar que um clone futuro
altere silenciosamente a combinacao validada. Atualizacoes sao feitas pelo
mantenedor, acompanhadas de smoke test e nova release.

O banco novo usa o bootstrap de esquema atual do backend e os seeds de
objetivos/permissoes. Ele nao reexecuta a historia legada do Alembic. Nao use
esta stack para validar migrations historicas.

.local/ armazena arquivos gerados e credenciais; sources/ contem os clones.
Ambas as pastas sao ignoradas pelo Git. Arquivos de segredos sao gerados com
permissao restrita nos sistemas que suportam permissoes POSIX.

INSIGHTS_DOCKER_CONTEXT seleciona explicitamente um contexto Docker.
INSIGHTS_PROJECT_NAME permite uma stack com outro nome. Use os mesmos valores
em todos os comandos para continuar operando o mesmo ambiente.

Validacao do instalador, sem acesso aos repositorios privados:

```bash
python3 -m unittest discover -s tests -v
bash -n scripts/local.sh
pwsh -NoProfile -File tests/test_powershell.ps1
```

A CI valida esses contratos em Linux, macOS e Windows. Instalacoes nativas
com UAC, janelas do sistema e reinicializacoes precisam de verificacao manual
em computadores limpos; testes de sintaxe e mocks nao substituem essa verificacao.
