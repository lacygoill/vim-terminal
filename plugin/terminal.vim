if exists('g:loaded_terminal')
    finish
endif
let g:loaded_terminal = 1

" FAQ {{{1
" How to change the function name prefix `Tapi_`? {{{2
"
" Use the `term_setapi()` function.
"
"     :call term_setapi(buf, 'Myapi_')
"                       ^^^
"                       number of terminal buffer for which you want to change the prefix
"
" Its effect  is local  to a given  buffer, so if  you want  to apply it  to all
" terminal buffers, you'll need an autocmd.
"
"     au TerminalWinOpen * call term_setapi(str2nr(expand('<abuf>')), 'Myapi_')
"}}}1

" Mappings {{{1

" Why not `C-g C-g`?{{{
"
" It would interfere with our zsh snippets key binding.
"}}}
" And why `C-g C-j`?{{{
"
" It's easy to press with the current layout.
"}}}
" Why do you use a variable?{{{
"
" To have the guarantee to always be  able to toggle the popup from normal mode,
" *and* from Terminal-Job mode with the same key.
" Have a look at `s:mapping()` in `autoload/terminal/toggle_popup.vim`.
"}}}
let g:_termpopup_lhs = '<c-g><c-j>'
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

augroup my_terminal | au!
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
augroup install_escape_mapping_in_terminal | au!
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

" Commands {{{1

" We sometimes – accidentally – start a nested (N)Vim instance inside a N(Vim) terminal.
" Let's fix this by re-opening the file in the outer instance.
if !empty($VIM_TERMINAL) || !empty($NVIM_TERMINAL)
    " Why delay until `VimEnter`?{{{
    "
    " During my limited tests, it didn't  seem necessary, but I'm concerned that
    " the (N)Vim hasn't loaded the file yet when this plugin is sourced.
    "
    " Also, without the  autocmd, sometimes, a bunch of empty  lines are written
    " in the  terminal (only  seems to  happen when we've  started a  nested Vim
    " instance, not a nested Nvim).
    "}}}
    au VimEnter * call terminal#unnest#main()
endif

" Functions {{{1
fu Tapi_lcd(_, cwd) abort "{{{2
    " Change (N)Vim's window local working directory so that it matches the shell's cwd.{{{
    "
    " The function  is called automatically  from the  zsh hook `chpwd`,  via an
    " OSC51 sequence in Vim,  and via `nvr` in Nvim.  Useful to  help Vim find a
    " file when pressing `gf` (& friends) while in a terminal buffer.
    "}}}
    exe 'lcd '..a:cwd
    return ''
endfu

fu Tapi_drop(_, file) abort "{{{2
    " Open a file in the *current* (N)Vim instance, rather than in a nested one.{{{
    "
    " The function  can be called manually  via the custom shell  script `vimr`;
    " it's  also  called  automatically by  `terminal#unnest#main()`  if  (N)Vim
    " detects that it's running inside an (N)Vim terminal.
    "
    " Useful  to  avoid the  awkward  user  experience  inside a  nested  (N)Vim
    " instance (and all the pitfalls which come with it).
    "}}}
    if !has('nvim') && win_gettype() is# 'popup' || a:file is# ''
        return
    endif
    exe 'tab drop '..fnameescape(a:file)
    " to prevent 0 from being printed in Nvim's terminal{{{
    "
    " This is because  the function is invoked via  the `--remote-expr` argument
    " of the `nvr` command.
    "}}}
    return ''
endfu

