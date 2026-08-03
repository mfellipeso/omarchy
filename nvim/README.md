# nvim

Binds e preferências pessoais do LazyVim, carregadas por cima do que o pacote
`omarchy-nvim` instala em `~/.config/nvim`.

Não tem stow nem symlink aqui, igual ao resto do repo: o `~/.config/nvim` fica
**stock** e ganha três linhas que apontam para cá, uma por fase de carregamento
do LazyVim. As migrations do Omarchy dão `install -m 0644` por cima de arquivos
de lá — foi assim que o `remote_clipboard.lua` chegou — então qualquer coisa
escrita direto naqueles arquivos vira alvo de sobrescrita.

| Arquivo do Omarchy         | Linha plantada                    | Quando roda   |
|----------------------------|-----------------------------------|---------------|
| `lua/config/lazy.lua`      | `rtp.paths` + `import`            | antes do lazy |
| `lua/config/options.lua`   | `require("dotfiles.options")`     | antes do lazy |
| `lua/config/keymaps.lua`   | `require("dotfiles.keymaps")`     | no `VeryLazy` |

O namespace é `dotfiles.` justamente para não colidir com o `config.` e o
`plugins.` que o Omarchy já ocupa no `~/.config/nvim/lua`.

O `rtp` entra por `performance.rtp.paths`, e não por um `vim.opt.rtp:prepend`
antes do `setup()`: o lazy roda com `performance.rtp.reset = true` e reconstrói
o rtp do zero lá dentro, descartando qualquer prepend anterior.

## Extras

Os extras do LazyVim não vêm por import daqui — eles vão para o `lazyvim.json`,
o mesmo arquivo que o `:LazyExtras` edita, escritos pelo `setup/setup-nvim.sh`.

Assim o LazyVim resolve sozinho a ordem que ele mesmo exige (`lazyvim.plugins`
-> extras -> plugins próprios) e o `lazy.lua` fica com um import nosso só.
Importar extras por um módulo nosso quebrava essa ordem e o LazyVim reclamava em
cima da tela.

O setup só acrescenta, com uma exceção: ele troca o extra `editor.neo-tree`, que
o Omarchy marca, pelo `editor.snacks_explorer`. Fora essa, o que o Omarchy tiver
marcado ali continua marcado.

A troca tem que ser no extra, não no plugin. É o extra que liga cada explorer —
o `snacks_explorer` é quem passa `opts.explorer`, e é esse opts que faz o snacks
substituir o netrw e abrir diretório. Desabilitar só o plugin do neo-tree
deixava os dois explorers desligados e o netrw assumindo o `nvim .`.

## Tema

Não tem nada de tema aqui. Quem manda é o Omarchy: ele symlinka
`lua/plugins/theme.lua` para o tema atual, pré-carrega todos os colorschemes em
`all-themes.lua` e faz hot-reload no `omarchy theme set`.

## lazy-lock.json

Não é versionado. Ele mora em `~/.config/nvim`, que é território do Omarchy, e o
`lazy.lua` já usa `version = false` (sempre o último commit). Cada máquina
resolve os plugins na hora.
