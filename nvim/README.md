# nvim

Binds e preferências pessoais, carregadas por cima do LazyVim que o pacote
`omarchy-nvim` instala em `~/.config/nvim`.

O objetivo aqui é ficar o mais perto possível do default do Omarchy. Nada neste
diretório troca um default dele: explorer, tema, extras do LazyVim e o
`lua/plugins` continuam sendo dele.

Não tem stow nem symlink, igual ao resto do repo: o `~/.config/nvim` fica
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

## O que tem aqui

    options.lua              fixendofline, :CopyAbsPath, :CopyRelPath
    keymaps.lua              jj/jk para esc, centralizar busca, colar sem
                             substituir, <leader>ba, <leader>yp, <leader>yr,
                             q desabilitado
    plugins/lsp.lua          inlay hints desligados
    plugins/mini-icons.lua   ícones para arquivos de teste e do NestJS
    plugins/tmux-navigator.lua

## O que ficou de fora, e por quê

**Extras do LazyVim.** A config antiga marcava nove (typescript, go, python,
docker, json, prisma, tailwind, eslint, prettier). O `lazyvim.json` é do
Omarchy; se um dia quiser algum de volta, o caminho é o `:LazyExtras`.

**Explorer.** O Omarchy usa o neo-tree, e é o extra `editor.neo-tree` que o
liga. Desabilitar só o plugin dele para usar o explorer do snacks quebrava os
dois: o do snacks só existe se `editor.snacks_explorer` estiver marcado, porque
é ele que passa `opts.explorer` — e é esse opts que substitui o netrw. Sem
nenhum dos dois, o netrw assumia o `nvim .`.

**Tema.** É todo do Omarchy: ele symlinka `lua/plugins/theme.lua` para o tema
atual, pré-carrega os colorschemes em `all-themes.lua` e faz hot-reload no
`omarchy theme set`.

## lazy-lock.json

Não é versionado. Ele mora em `~/.config/nvim`, que é território do Omarchy, e o
`lazy.lua` já usa `version = false` (sempre o último commit). Cada máquina
resolve os plugins na hora.
