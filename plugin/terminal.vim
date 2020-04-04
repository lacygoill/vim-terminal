if exists('g:loaded_terminal')
    finish
endif
let g:loaded_terminal = 1

" Mappings {{{1

" Why not `C-g C-g`?{{{
"
" It would interfere with our zsh snippets key binding.
"}}}
" And why `C-g C-k`?{{{
"
" It's easy to press with the current layout.
"}}}
" Why do you use a variable?{{{
"
" To have the guarantee to always be  able to toggle the popup from normal mode,
" *and* from Terminal-Job mode with the same key.
" Have a look at `s:mapping()` in `autoload/terminal/toggle_popup.vim`.
"}}}
let g:_termpopup_lhs = '<c-g><c-k>'
exe 'nno <silent> '..g:_termpopup_lhs..' :<c-u>call terminal#toggle_popup#main()<cr>'

" Options {{{1

if !has('nvim')
    " What does `'termwinkey'` do?{{{
    "
    " It controls which key can be pressed to issue a command to Vim rather than
    " the foreground shell process in the terminal.
    "}}}
    " Why do yo change its value?{{{
    "
    " By default, its value is `<c-w>`; so  you can press `C-w :` to enter Vim's
    " command-line; but I don't like that `c-w` should delete the previous word.
    "}}}
    " Warning: do *not* use `C-g`{{{
    "
    " If you do, when  we want to use one of our zsh  snippets, we would need to
    " press `C-g` 4 times instead of twice.
    "}}}
    set termwinkey=<c-s>
endif

" Autocmds {{{1

augroup my_terminal
    au!
    if has('nvim')
        au TermOpen * call terminal#setup() | call terminal#setup_neovim() | startinsert
    else
        au TerminalWinOpen * call terminal#setup() | call terminal#setup_vim()
    endif
augroup END

" Why do you install a mapping whose lhs is `Esc Esc`?{{{
"
" In Vim, we can't use `Esc` in the  lhs of a mapping, because any key producing
" a sequence  of keycodes  containing `Esc`,  would be  subject to  an undesired
" remapping (`M-b`, `M-f`, `Left`, `Right`, ...).
"
" Example:
" `M-b` produces `Esc` (enter Terminal-Normal mode) + `b` (one word backward).
" We *do* want to go one word backward, but we also want to stay in Terminal-Job
" mode.
"}}}
" Why do you use an autocmd and buffer-local mappings?{{{
"
" When fzf opens a terminal buffer, we don't want our mapping to be installed.
"
" Otherwise,  we need  to press  Escape  twice, then  press `q`;  that's 3  keys
" instead of one single Escape.
"
" We need our `Esc  Esc` mapping in all terminal buffers,  except the ones whose
" filetype is fzf; that's why we use a buffer-local mapping (when removed,
" it only affects the current buffer), and that's why we remove it in an autocmd
" listening to `FileType fzf`.
"}}}
" Do you need to do all of that in Neovim too?{{{
"
" No, Neovim doesn't suffer from this issue.
"
" So, to  go from Terminal-Job mode  to Terminal-Normal mode, we  could use this
" mapping:
"
"     exe 'tno <buffer> '..(has('nvim') ? '<esc>' : '<esc><esc>')..' <c-\><c-n>'
"
" But I  prefer to  stay consistent:  double Escape  in Vim  → double  escape in
" Neovim.
"}}}
" TODO: Find a way to send an Escape key to the foreground program running in the terminal.{{{
"
" Maybe something like this:
"
"     exe "set <m-[>=\e["
"     tno <m-[> <esc>
"
" It doesn't work, but you get the idea.
"}}}
augroup install_escape_mapping_in_terminal
    au!
    if !has('nvim')
        " Do *not* install this mapping:  `tno <buffer> <esc>: <c-\><c-n>:`{{{
        "
        " Watch:
        "
        "     z<      open a terminal
        "     Esc :   enter command-line
        "     Esc     get back to terminal normal mode
        "     z>      close terminal
        "
        " The meta keysyms are disabled.
                " }}}
        au TerminalWinOpen * tno <buffer><nowait><silent> <esc><esc> <c-\><c-n>:call terminal#fire_termleave()<cr>
        au TerminalWinOpen * tno <buffer><nowait><silent> <c-\><c-n> <c-\><c-n>:call terminal#fire_termleave()<cr>
    else
        au TermOpen * tno <buffer><nowait> <esc><esc> <c-\><c-n>
    endif
    au FileType fzf tunmap <buffer> <esc><esc>
augroup END

