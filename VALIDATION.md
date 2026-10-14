# Validação das alterações

Atualizado em 14 de outubro de 2026. Esta revisão remove a busca de credenciais
na AWS do instalador. O usuário cria `sources/backend/.env` localmente; setup e
start precisam interromper a inicialização antes dos serviços se esse arquivo
estiver ausente ou incompleto.

## Verificações executadas nesta revisão

- `python3 -m unittest discover -s tests -v`: 42 testes, 41 aprovados e um teste
  de compilação AppleScript ignorado por exigir macOS.
- `bash -n scripts/local.sh`, `bash -n scripts/macos.sh`,
  `sh -n scripts/macos-askpass.sh` e `bash scripts/local.sh help`: aprovados.
- Os testes de configuração usam credenciais sintéticas em
  `sources/backend/.env`; verificam variáveis necessárias, endpoint HTTPS do Hub,
  proteção POSIX, ausência de valores em diagnósticos e preservação das
  configurações geradas se o `.env` estiver incompleto.
- Teste do launcher Bash confirma que `start` não chama Compose para iniciar
  serviços sem `sources/backend/.env`.
- `git diff --check`: aprovado.

PowerShell 7 não está instalado neste host, portanto `tests/test_powershell.ps1`
não foi executado localmente. O teste foi atualizado para verificar que o
launcher do Windows interrompe `start` antes de `compose config` ou `compose up`
quando o `.env` está ausente. A CI configurada no GitHub executa a suíte em
Windows, macOS e Linux.

## Limite da validação integrada

Em 9 de outubro de 2026, os pins em `sources.lock` passaram por um smoke test de
stack real em Linux, incluindo build, banco local, seeder do Review App, frontend,
API, gateway, Redis, workers, scheduler, login, recarga automática e consulta
autenticada ao Hub com TLS verificado. Esse teste foi feito antes da remoção do
fluxo de obtenção automática das credenciais e não valida a leitura direta de
`sources/backend/.env` introduzida nesta revisão.

Não foi repetido o build integrado com um `.env` real nesta revisão porque o
clone público não contém os repositórios privados nem as credenciais de runtime.
Os testes locais cobrem a transformação da configuração com valores sintéticos;
é necessário fazer um smoke test com o arquivo privado local para confirmar a
instalação de ponta a ponta após a publicação.

As instalações com interfaces e permissões reais em Mac e Windows também
dependem de computadores desses sistemas. A CI verifica contratos de scripts,
mas não substitui uma instalação em máquinas limpas com Xcode Command Line Tools,
UAC, WSL e Docker Desktop.
