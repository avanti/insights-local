# Validacao da release v0.1.0

Executada em 8 de outubro de 2026.

- Linux x86_64, Docker Engine 28.4.0: imagens dos dois aplicativos construidas
  a partir dos SHAs de sources.lock; banco novo preparado; interface e Swagger
  acessiveis pelo host; login via front-end e sessao persistente confirmados.
- Modo demo: POSTs de analise, upload e registro bloqueados com HTTP 503;
  conexao externa do container da API bloqueada; workers e scheduler ausentes.
- Parada e reinicializacao: volumes e credenciais preservados e login funcionando.
- Configuracao: 18 testes unitarios para modos, portas, segredos, repeticao de
  setup, bloqueio de operacoes e contratos dos scripts.
- Bash: sintaxe, ShellCheck 0.10.0 e compatibilidade de sintaxe/help com Bash 3.2.
- PowerShell 7.4: parser, help e contratos de status, perfis e parada usando mocks.

A CI repete a validacao dos scripts em runners Windows, macOS e Linux.
Ela nao instala Docker Desktop nem clona os aplicativos privados.

Ainda precisam de verificacao em computadores limpos: instalacao nativa com
UAC/WSL e reinicializacao no Windows; instalacao Apple/Docker no macOS;
permissoes sudo e instalacao de pacotes nas distribuicoes Linux suportadas.
ARM/Apple Silicon nao foi testado em hardware nesta validacao.
Analises reais em connected dependem das credenciais e das integracoes de cada pessoa.

## Atualizacao v0.1.1: atalhos para o Codex

- 23 testes Python: configuracao e protecoes existentes, caminhos reais do host
  para macOS/Linux/Windows, espacos/acentos/caracteres especiais, escape HTML,
  leitura dos atalhos macOS/Windows e abertura seletiva com um launcher simulado.
- Configuracao executada no container Python 3.11, com caminhos do host fornecidos
  explicitamente: os links apontam para sources/frontend e sources/backend no
  computador, sem usar o ponto de montagem /bootstrap do container.
- Bash: sintaxe com Bash 3.2 e ShellCheck 0.10.0 aprovados.
- PowerShell 7.4: parser e contratos existentes aprovados; abertura seletiva dos
  links e rejeicao de links invalidos verificadas com Start-Process simulado.

A CI executa os contratos nos tres sistemas. Estes testes nao abrem o aplicativo
Codex nem confirmam o cadastro permanente na barra lateral. A abertura pelo link
e o cadastro dos projetos devem ser conferidos na instalacao da pessoa.
Esta atualizacao nao muda os SHAs dos aplicativos nem o funcionamento da stack;
o teste completo da stack descrito acima foi realizado na v0.1.0.
