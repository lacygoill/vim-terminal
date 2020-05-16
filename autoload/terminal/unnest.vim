" Interface {{{1
fu terminal#unnest#main() abort "{{{2
    " Why do you check this again?  We already did it in `plugin/terminal.vim`...{{{
    "
    " Just in case we call this function manually by accident.
    "}}}
    if !s:in_vim_terminal() | return | endif

    let terminal = s:terminal()
    if s:vim_used_as_manpager()
        return s:open_manpage(terminal)
    endif

    let tempfile = s:write_filepaths()
    call s:open_files(terminal, tempfile)
    if s:called_by_vipe()
        call s:parse_ansi_sequences(terminal)
    endif

    " Why the delay?{{{
    "
    "     $ vim +term
    "     $ trans hedge | vipe
    "
    " The buffer which is opened in the outer Vim is empty.
    " Delaying `:qa!` fixes the issue.
    "}}}
    call timer_start(0, {-> execute('qa!')})
endfu
"}}}1
" Core {{{1
fu s:open_manpage(outer) abort "{{{2
    let page = matchstr(expand('%:p'), 'man://\zs.*')
    if a:outer is# 'vim'
        " Why `json_encode()` instead of `string()`?{{{
        "
        " The man page must be surrounded by double quotes, not single quotes.
        "}}}
        call writefile(["\e"..']51;["call", "Tapi_man", '..json_encode(page)..']'.."\007"], '/dev/tty', 'b')
    else
        call system('nvr --servername "$VIM_SERVERNAME" --remote-expr "Tapi_man(0, '..string(page)..')"')
    endif
    qa!
endfu

fu s:write_filepaths() abort "{{{2
    let files = map(argv(), {_,v -> fnamemodify(v, ':p')})
    " Don't try to pass the file paths directly to the outer Vim.{{{
    "
    " It makes the code much more verbose.
    " Indeed, if there  are too many files, and the  OSC 51 sequence gets too long,
    " the command fails; the outer Vim doesn't open anything.
    " You have to split the command `:tab drop file1 file2 ...` into sth like:
    "
    "     :tab drop file1 ... file50
    "     :argadd file51 ...
    "     :argadd file101 ...
    "     ...
    "
    " So, you need a  while loop to iterate over the list  of files, and you
    " need an additional `Tapi_` function to execute `:argadd`.
    "}}}
    let tempfile = tempname()
    call writefile(files, tempfile)
    return tempfile
endfu

fu s:open_files(outer, tempfile) abort "{{{2
    " to avoid error message due to swap files when opening files in the outer Vim
    %bd
    if a:outer is# 'vim'
        " open files in the outer Vim instance using `:h terminal-api`
        call writefile(["\e"..']51;["call", "Tapi_drop", "'..a:tempfile..'"]'.."\007"], '/dev/tty', 'b')
    else
        " open files in the outer Nvim instance using `nvr`: https://github.com/mhinz/neovim-remote
        call system('nvr --servername "$VIM_SERVERNAME" --remote-expr "Tapi_drop(0, '..string(a:tempfile)..')"')
    endif
endfu

fu s:parse_ansi_sequences(outer) abort "{{{2
    " correctly highlight a buffer containing ansi escape sequences{{{
    "
    "     $ vim +term
    "     $ trans word 2>&1 | vipe >/dev/null
    "}}}
    if a:outer is# 'vim'
        call writefile(["\e"..']51;["call", "Tapi_call", "lg#textprop#ansi"]'.."\007"], '/dev/tty', 'b')
    else
        call system('nvr --servername "$VIM_SERVERNAME" --remote-expr "Tapi_call(0, ''lg#textprop#ansi'')"')
    endif
endfu
"}}}1
" Utilities {{{1
fu s:in_vim_terminal() abort "{{{2
    return !empty($VIM_TERMINAL) || !empty($NVIM_TERMINAL)
endfu

fu s:vim_used_as_manpager() abort "{{{2
    return expand('%:p') =~# '^\Cman://'
endfu

fu s:terminal() abort "{{{2
    return !empty($VIM_TERMINAL) ? 'vim' : 'nvim'
endfu

fu s:called_by_vipe() abort "{{{2
    return $_ =~# '\C/vipe$'
endfu

