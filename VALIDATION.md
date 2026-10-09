# Validação das alterações locais

Executada em 9 de outubro de 2026. Estas alterações ainda não foram publicadas
no GitHub: não houve push, release nem execução da CI remota.

## Contratos automatizados

- 50 testes Python executados: 49 aprovados e um de compilação AppleScript
  ignorado neste host Linux por exigir macOS.
- Configuração com credenciais reais obrigatórias, Google Sheets opcional,
  importação do JSON recebido pela entrada padrão, ausência de valores nos
  diagnósticos, permissões POSIX e preservação de arquivos após erros.
- Migração da configuração antiga de demonstração, preservação de portas e
  senhas, banco/Redis sempre locais e distribuição das chaves entre os servidores
  frontend e backend.
- Login AWS de Console e SSO simulado, reutilização de sessão, recusa de login
  não interativo, versão mínima da CLI e preservação após falha parcial da AWS.
- Simulação de download Linux com assinatura inválida: a extração e a instalação
  não acontecem. Simulação de atualização AWS CLI pelo Brew no macOS.
- Contratos macOS para Apple Silicon e Intel: preparação das ferramentas Apple,
  Homebrew, gh e Docker, confirmação local, checksum/cache, cancelamento,
  espera, repetição e registro da etapa interrompida.
- Toda a suíte Python passou também usando Bash 3.2.0. Sintaxe e help dos
  launchers foram verificados nessa versão; ShellCheck 0.10.0 passou nos quatro
  scripts Bash/sh.
- PowerShell 7.4.6: parser e contratos de status, isolamento de perfis Compose,
  parada sem remoção de volumes, atalhos e setup interrompido aprovados.
  As funções AWS foram executadas com comandos simulados: versão da CLI,
  login de navegador, reutilização de sessão, segredo por stdin e falha de leitura.
- git diff --check aprovado.

## Stack real em Linux

Ambiente isolado `insights-connected-validation`, Docker no contexto default,
com os dois aplicativos nas revisões de sources.lock. Os arquivos privados de
validação ficam fora do checkout público.

- Leitura real do segredo synapse/review-app/env em us-east-1 usando uma sessão
  AWS já autorizada. Valores transferidos por stdin, sem exibição ou cópia para
  arquivos versionados. A CLI existente nessa máquina foi suficiente para a
  leitura; o novo login de navegador foi testado com mocks.
- Configuração, build e inicialização a partir de um banco local novo aprovados.
  API, frontend, gateway, PostgreSQL, Redis e ambos os workers ficaram saudáveis;
  scheduler permaneceu em execução.
- Interface em loopback na porta 3197 e API na porta 8197. Login pelo frontend,
  persistência da sessão e GET autenticado /api/customers do Hub com TLS
  verificado aprovados, sem exibir dados dos clientes.
- doctor aprovado, incluindo ping separado dos workers Celery e Playwright e
  verificação da execução do scheduler.
- Recarga automática verificada com duas alterações sucessivas em rotas
  temporárias no frontend e na API. As novas respostas apareceram pelo localhost
  e os horários de início dos containers permaneceram iguais. Os arquivos da
  cópia de teste foram restaurados ao terminar.
- Stack de teste parada pelo comando stop, preservando os volumes.

Não foram disparadas análises de IA, uploads, notificações, agendamentos nem
operações nos clientes para validar a instalação. O acesso ao Hub e a presença
das configurações não comprovam a execução de todos os objetivos: os serviços
externos e as conexões de cada cliente precisam estar disponíveis.

## Verificações que dependem de outras máquinas

- Instalação completa em Mac limpo com janelas Apple, sudo, Brew e Docker Desktop,
  e login GitHub/AWS com as permissões reais do Codex.
- Windows com UAC, winget, WSL, Docker Desktop, reinicialização e ACLs NTFS reais.
  Os contratos executados em Linux com PowerShell 7 não substituem esse teste
  nem uma execução em Windows PowerShell 5.1.
- Instalação nativa de pacotes e acesso sudo em Linux limpo, além de hardware
  ARM/Apple Silicon.
- Login AWS interativo de uma nova identidade com SignInLocalDevelopmentAccess
  e GetSecretValue concedidos pelo administrador. Nenhum usuário ou política IAM
  foi criado ou alterado nesta tarefa.
- Cadastro permanente dos projetos na barra lateral do Codex: os contratos
  validam caminhos e links; é necessário conferir o resultado no aplicativo.

A CI está configurada para repetir os contratos em Linux, macOS e Windows.
Ela não instala Docker Desktop, não recebe segredos e não clona os aplicativos
privados.

## Integração do seeder do Review App

sources.lock aponta para as revisões publicadas
`4211827a2ddadc8b48fa2fe3ff1109a2878b6bae` (backend) e
`5625dc7d76627c368083105634d16a00fb18dee6` (frontend). A revisão do backend
inclui o seeder. Em 9 de outubro, os dois pins foram construídos em uma stack
temporária com banco novo e configurações locais já existentes; os checkouts e
dados locais originais não foram alterados.

- API, frontend, gateway, PostgreSQL, Redis, workers, scheduler e bootstrap
  ficaram saudáveis no Compose.
- O primeiro bootstrap criou o dataset sintético do Review App. Uma segunda
  execução no mesmo banco não repetiu o seeder.
- As 9 tarefas sintéticas de Review ficaram inativas antes do scheduler iniciar.
- A stack e os volumes temporários foram removidos depois da verificação.
- O `npm ci` do frontend concluiu, mas reportou 23 vulnerabilidades nas
  dependências (1 baixa, 1 moderada, 19 altas e 2 críticas). Esta tarefa não
  alterou as dependências do repositório privado do frontend.

Este smoke test cobre o build local e o bootstrap/seeder com os pins novos; não
repete o login AWS nem a chamada autenticada ao Hub nessa stack temporária.
