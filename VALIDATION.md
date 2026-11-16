# Validação das alterações

Atualizado em 16 de novembro de 2026. Esta revisão atualiza `sources.lock` para a
`main` atual dos dois aplicativos e prepara bancos locais existentes para o
backend novo.

- Backend `avanti/avanti-synapse`: `185b858c7bbed10516e0ec19a3a37185e0ca3a13`
  (antes `4211827`, de 7 de outubro). O `requirements.txt` agora trava todas as
  dependências, inclusive `kombu==5.6.2`. A revisão anterior não fixava o kombu;
  builds novos instalavam o kombu 5.7.0, que exige redis-py 6.4 ou mais novo, e
  `worker` e `playwright_worker` caíam com `VersionMismatch` contra `redis==5.2.0`.
- Frontend `avanti/avanti-insights-ai`: `3ca1ca4a98328824cbd3debd96710869774aaf7c`
  (antes `5625dc7`).

## Mudanças no instalador

- O bootstrap acrescenta ao banco local as colunas que o backend atual tem e o
  banco ainda não tem, quando isso é seguro: colunas que aceitam nulo ou têm valor
  padrão no banco, seguidas das restrições únicas e índices que as usam. Nada é
  removido nem tem o tipo alterado. Se faltar uma coluna obrigatória sem valor
  padrão, o bootstrap para antes de alterar o banco e informa só os nomes.
- O backend novo provisiona rotinas automáticas ativas por cliente (Radar de
  mercado, Pulse e Performance do site), que chamam IA e o Hub reais, inclusive
  para os clientes sintéticos do Review App. O bootstrap cria essas rotinas
  pausadas antes de o scheduler iniciar. Rotinas que já existem não são alteradas.
- `VTEX_STATUS_SLACK_ENABLED` e `NEWS_AUTOGEN_ENABLED`, ligados por padrão no
  backend, ficam `false` no ambiente local, a menos que `sources/backend/.env`
  defina `true`.

## Verificações executadas nesta revisão

- `python3 -m unittest discover -s tests -v`: 42 testes, 41 aprovados e um teste
  de compilação AppleScript ignorado por exigir macOS.
- `bash -n scripts/local.sh` e `git diff --check`: aprovados.
- Smoke test em Linux (Docker 29.9.3, Compose 5.7.0) com `.env` real:
  1. Instalação na revisão anterior: reproduziu a queda dos dois workers por
     causa do kombu 5.7.0. Com `kombu==5.6.2` acrescentado localmente, setup e
     doctor passaram.
  2. Atualização desse checkout para as revisões novas, sobre o banco criado pelo
     backend anterior: sem a mudança no bootstrap, a inicialização falhava com
     `column Customer.slackIncludeDefaultChannelForObjectives does not exist`.
     Com a mudança, foram adicionadas 6 colunas e 2 restrições únicas; setup e
     doctor passaram e 33 rotinas de clientes foram criadas pausadas. Uma segunda
     inicialização não alterou o banco, e uma rotina ativada manualmente
     continuou ativa.
  3. Instalação limpa nas revisões novas, em outra pasta, com outro nome de
     projeto Compose e portas 3010/8010: setup e doctor passaram, o seeder do
     Review App rodou e as rotinas de clientes ficaram pausadas.
  Em todos os casos o doctor confirmou interface, login, sessão, Hub com TLS
  verificado, os dois workers e o scheduler.

PowerShell 7 não está instalado neste host, portanto `tests/test_powershell.ps1`
não foi executado localmente; a CI executa a suíte em Windows, macOS e Linux.

## Problemas conhecidos do backend fixado

- O scheduler registra a cada ciclo `Daily revenue goals maintenance failed`
  (`could not identify an equality operator for type json`). A consulta usa
  `SELECT DISTINCT` sobre `Customer`, cujas colunas `selectedIndicatorKeys` e
  `selectedIndicatorScopes` são `JSON` no modelo e nas migrations. O erro ocorre
  também na instalação limpa; não é causado pelo instalador. Os demais serviços
  continuam funcionando.
- Ao terminar, o bootstrap imprime avisos `Exception ignored ... Event loop is
  closed` de conexões Redis do backend; o código de saída é 0.

## Limites

A atualização de bancos existentes cobre colunas novas. Mudanças de tipo,
remoção de colunas e chaves estrangeiras em colunas adicionadas não são
reproduzidas. As instalações com interfaces e permissões reais em Mac e Windows
dependem de computadores desses sistemas; a CI verifica contratos de scripts,
mas não substitui uma instalação em máquinas limpas.
