vim9script noclear

if exists('loaded') | finish | endif
var loaded = true

# FAQ {{{1
# How to change the function name prefix `Tapi_`? {{{2
#
# Use the `term_setapi()` function.
#
#     term_setapi(buf, 'Myapi_')
#                 ^^^
#                 number of terminal buffer for which you want to change the prefix
#
# Its effect  is local  to a given  buffer, so if  you want  to apply it  to all
# terminal buffers, you'll need an autocmd.
#
#     autocmd TerminalWinOpen * expand('<abuf>')->str2nr()->term_setapi('Myapi_')
#}}}1

import Catch from 'lg.vim'

# Mappings {{{1

# Why not `C-g C-g`?{{{
#
# It would interfere with our zsh snippets key binding.
#}}}
# And why `C-g C-j`?{{{
#
# It's easy to press with the current layout.
#}}}
# Why do you use a variable?{{{
#
# To have the guarantee to always be  able to toggle the popup from normal mode,
# *and* from Terminal-Job mode with the same key.
# Have a look at `TerminalJobMapping()` in `autoload/terminal/toggle_popup.vim`.
#}}}
g:_termpopup_lhs = '<C-G><C-J>'
execute 'nnoremap <unique> ' .. g:_termpopup_lhs .. ' <Cmd>call terminal#togglePopup#main()<CR>'

# Options {{{1

# What does `'termwinkey'` do?{{{
#
# It controls which key can be pressed to issue a command to Vim rather than the
# foreground shell process in the terminal.
#}}}
# Why do yo change its value?{{{
#
# By default,  its value is  `<C-W>`; so  you can press  `C-w :` to  enter Vim's
# command-line; but I don't like that `C-w` should delete the previous word.
#}}}
# Warning: do *not* use `C-g`{{{
#
# If you do, when we want to use one of our zsh snippets, we would need to press
# `C-g` 4 times instead of twice.
#}}}
&termwinkey = '<C-S>'

# Autocmds {{{1

augroup MyTerminal | autocmd!
    autocmd TerminalWinOpen * terminal#setup()
augroup END

# Why do you install a mapping whose lhs is `Esc Esc`?{{{
#
# In Vim, we can't use `Esc` in the  lhs of a mapping, because any key producing
# a sequence  of key codes  containing `Esc`, would  be subject to  an undesired
# remapping (`M-b`, `M-f`, `Left`, `Right`, ...).
#
# Example:
# `M-b` produces `Esc` (enter Terminal-Normal mode) + `b` (one word backward).
# We *do* want to go one word backward, but we also want to stay in Terminal-Job
# mode.
#}}}
# Why do you use an autocmd and buffer-local mappings?{{{
#
# When fzf opens a terminal buffer, we don't want our mapping to be installed.
#
# Otherwise,  we need  to press  Escape  twice, then  press `q`;  that's 3  keys
# instead of one single Escape.
#
# We need our `Esc  Esc` mapping in all terminal buffers,  except the ones whose
# filetype is fzf; that's why we use a buffer-local mapping (when removed,
# it only affects the current buffer), and that's why we remove it in an autocmd
# listening to `FileType fzf`.
#}}}
# TODO: Find a way to send an Escape key to the foreground program running in the terminal.{{{
#
# Maybe something like this:
#
#     execute "set <M-[>=\<Esc>["
#     tnoremap <M-[> <Esc>
#
# It doesn't work, but you get the idea.
#}}}
augroup InstallEscapeMappingInTerminal | autocmd!
    # Do *not* install this mapping:  `tnoremap <buffer> <Esc>: <C-\><C-N>:`{{{
    #
    # Watch:
    #
    #     z<      open a terminal
    #     Esc :   enter command-line
    #     Esc     get back to terminal normal mode
    #     z>      close terminal
    #
    # The meta keysyms are disabled.
            # }}}
    autocmd TerminalWinOpen * tnoremap <buffer><nowait> <Esc><Esc> <C-\><C-N><Cmd>call terminal#fireTermleave()<CR>
    autocmd TerminalWinOpen * tnoremap <buffer><nowait> <C-\><C-N> <C-\><C-N><Cmd>call terminal#fireTermleave()<CR>
    autocmd FileType fzf tunmap <buffer> <Esc><Esc>
augroup END

# We sometimes – accidentally – start a nested Vim instance inside a Vim terminal.
# Let's fix this by re-opening the file(s) in the outer instance.
if !empty($VIM_TERMINAL)
    # Why delay until `VimEnter`?{{{
    #
    # During my limited tests, it didn't  seem necessary, but I'm concerned that
    # Vim hasn't loaded the file yet when this plugin is sourced.
    #
    # Also, without the  autocmd, sometimes, a bunch of empty  lines are written
    # in the terminal.
    #}}}
    autocmd VimEnter * terminal#unnest#main()
endif

# Functions {{{1
# Interface {{{2
def g:Tapi_drop(_, file_listing: string) #{{{3
    # Open a file in the *current* Vim instance, rather than in a nested one.{{{
    #
    # The function  is called  automatically by `terminal#unnest#main()`  if Vim
    # detects that it's running inside a Vim terminal.
    #
    # Useful to avoid  the awkward user experience inside a  nested Vim instance
    # (and all the pitfalls which come with it).
    #}}}
    var files: list<string>
    if empty(file_listing)
        return
    else
        files = readfile(file_listing)
        if empty(files)
            return
        endif
    endif
    try
        if win_gettype() == 'popup'
            win_getid()->popup_close()
        endif
        execute 'drop ' .. files
            ->map((_, v: string) => fnameescape(v))
            ->join()
    # E994, E863, ...
    catch
        Catch()
        return
    endtry
enddef

def g:Tapi_exe(_, cmd: string) #{{{3
    # Run an arbitrary Ex command.
    # `:silent` is useful to prevent `:lcd` from printing the new Vim cwd on the
    # command-line.
    execute 'silent ' .. cmd
enddef

def g:Tapi_man(_, page: string) #{{{3
    # open manpage in outer Vim
    if exists(':Man') != 2
        echomsg ':Man needs to be installed'
        return
    endif
    try
        execute 'tab Man ' .. page
    catch
        Catch()
        return
    endtry
enddef
#}}}2
