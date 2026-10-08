# Avanti Insights local

Este repositorio publico prepara dois aplicativos privados da organizacao Avanti.

- Leia README.md antes de iniciar. Use scripts/local.ps1 no Windows e
  scripts/local.sh no macOS/Linux. O primeiro comando e setup.
- Comece em modo demo, a menos que a pessoa solicite explicitamente connected.
- Verifique acesso aos repositorios de sources.lock. Login GitHub, senha sudo,
  termos do Docker e reinicializacao devem ser concluidos pela pessoa quando exigidos.
- Para iniciar sem Git, baixe o ZIP da release ou o script avulso descrito no README.
- Execute doctor e a verificacao de login antes de declarar o ambiente pronto.
- Nunca imprima .local/*.env, secrets.json, access.txt, tokens ou senhas no chat.
  Abra access.txt no editor local para a pessoa consultar o primeiro acesso.
- sources/ e .local/ sao privados e ignorados pelo Git. Publique apenas arquivos
  explicitamente revisados do instalador; nunca copie codigo dos apps para este repo.
- setup pode parar os containers deste instalador, mas deve preservar os volumes,
  senhas existentes e alteracoes nos checkouts. Nao execute down -v nem git reset.
- O banco e preparado pelo bootstrap local atual, sem reproduzir a historia
  legada do Alembic. Nunca aponte este instalador para bancos compartilhados.
- O modo demo bloqueia escritas fora da autenticacao e nao tem egress de rede.
  Nao remova essas protecoes para ocultar falhas de integracoes.
- Rode python -m unittest discover -s tests -v, bash -n scripts/local.sh e
  os testes PowerShell antes de publicar alteracoes.
- Atualizacoes de sources.lock exigem novo smoke test com os dois aplicativos.
