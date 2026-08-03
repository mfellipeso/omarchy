# nvim

Config pessoal do LazyVim, carregada por cima do que o pacote `omarchy-nvim`
instala em `~/.config/nvim`.

`~/.config/nvim` fica **stock**. As migrations do Omarchy dão `install -m 0644`
por cima de arquivos de lá (foi assim que o `remote_clipboard.lua` chegou), então
qualquer coisa escrita direto naqueles arquivos vira alvo de sobrescrita. O que
plantamos são três linhas, uma por fase de carregamento do LazyVim:

| Arquivo do Omarchy         | Linha plantada                    | Quando roda        |
|----------------------------|-----------------------------------|--------------------|
| `lua/config/lazy.lua`      | `rtp:prepend` + `import`          | antes do lazy      |
| `lua/config/options.lua`   | `require("dotfiles.options")`     | antes do lazy      |
| `lua/config/keymaps.lua`   | `require("dotfiles.keymaps")`     | no `VeryLazy`      |

O namespace é `dotfiles.` justamente para não colidir com o `config.` e o
`plugins.` que o Omarchy já ocupa no `~/.config/nvim/lua`.

## Tema

Quem manda no tema é o Omarchy: ele symlinka `lua/plugins/theme.lua` para
`~/.local/state/omarchy/current/theme/neovim.lua`, pré-carrega todos os
colorschemes em `all-themes.lua` e faz hot-reload no `omarchy theme set`.

`dotfiles/plugins/colorscheme.lua` só existe como rede: enquanto aquele symlink
resolver, ele devolve `{}` e não disputa o `opts.colorscheme`. Sem Omarchy — ou
com o symlink quebrado — o LazyVim cairia no default dele, tokyonight; aqui o
fallback é o ashen, o mesmo do tema Solitude.

O teste é pela presença do `theme.lua`, e não pelo caminho do tema em
`~/.local/state`: é o symlink que decide se o Omarchy está no controle, e
`fs_stat` o segue, então um link pendurado também cai para o fallback.

O `install.colorscheme` do `lazy.lua` também aponta para o ashen. Ele é só o que
o lazy pinta enquanto instala os plugins no primeiro boot — cosmético, e a
única linha em que trocamos um valor de arquivo do Omarchy em vez de acrescentar
uma. Um update do pacote `omarchy-nvim` pode desfazer; rodar o
`setup/setup-nvim.sh` de novo recoloca.

## lazy-lock.json

Não é versionado. Ele mora em `~/.config/nvim`, que é território do Omarchy, e o
`lazy.lua` já usa `version = false` (sempre o último commit). Cada máquina
resolve os plugins na hora.
