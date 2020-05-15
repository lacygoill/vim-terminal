fu terminal#unnest#main() abort
    " Why do you check this again?  We already did it in `plugin/terminal.vim`...{{{
    "
    " Just in case we call this function manually by accident.
    "}}}
    if empty($VIM_TERMINAL) && empty($NVIM_TERMINAL)
        return
    endif
    let file = escape(expand('%:p'), '"')
    " to avoid error message due to swap file
    bd
    if !empty($VIM_TERMINAL)
        " open file in the outer Vim instance using `:h terminal-api`
        call writefile(["\e"..']51;["call", "Tapi_drop", "'..file..'"]'.."\007"], '/dev/tty', 'b')
    else
        " open file in the outer Nvim instance using `nvr`; https://github.com/mhinz/neovim-remote
        call system('nvr --servername "$VIM_SERVERNAME" --remote-expr'
            "\ `%q` instead of `%s` to support file names containing quotes
            \ ..' "$(printf -- ''Tapi_drop(0, "%q")'' "'..file..'")"')
    endif
    qa!
endfu

