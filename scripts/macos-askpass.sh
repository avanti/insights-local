#!/bin/sh
# Only sudo consumes stdout. Never call this helper from chat or log its output.
exec /usr/bin/osascript <<'APPLESCRIPT'
set confirmation to display dialog "O Homebrew precisa de autorização para instalar as dependências do Avanti Insights. Informe a senha deste Mac nesta janela. Ela não será salva nem enviada ao chat." default answer "" with hidden answer buttons {"Cancelar", "Autorizar"} default button "Autorizar" cancel button "Cancelar" with title "Avanti Insights — autorização"
return text returned of confirmation
APPLESCRIPT
