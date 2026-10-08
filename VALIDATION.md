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
