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

Não há nada de tema aqui. O Omarchy 4 resolve isso sozinho: ele symlinka
`lua/plugins/theme.lua` para `~/.local/state/omarchy/current/theme/neovim.lua`,
pré-carrega todos os colorschemes em `all-themes.lua` e faz hot-reload no
`omarchy theme set`.

A config antiga tinha um `colorscheme.lua` que lia
`~/.config/omarchy/current/theme/neovim.lua` — caminho do Omarchy 3, que não
existe mais. Trazê-lo faria ele cair no fallback tokyonight e brigar com o
`theme.lua` pelo `opts.colorscheme`.

## lazy-lock.json

Não é versionado. Ele mora em `~/.config/nvim`, que é território do Omarchy, e o
`lazy.lua` já usa `version = false` (sempre o último commit). Cada máquina
resolve os plugins na hora.
