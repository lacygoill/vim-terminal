fu terminal#setup_neovim() abort "{{{1
    " `'scrolloff'` causes an issue with our zsh snippets:{{{
    "
    "     $ nvim -Nu NONE +'set so=3 | 10sp | term' +'startinsert'
    "     # press C-g C-g Esc
    "     # insert some random characters
    "     # the terminal window flickers
    "
    " Imo, it's a bug:
    " https://github.com/neovim/neovim/issues/11072#issuecomment-533828802
    " But the devs closed the issue.
    "
    " There may be other similar issues:
    " https://github.com/neovim/neovim/search?q=terminal+scrolloff&type=Issues
    "
    " Anyway, let's reset the option in a terminal window to avoid any issue.
    "}}}
    " TODO: Remove these 2 autocmds once the PR #11854 is merged.  Replace them with a single `setl so=0`.
    au TermEnter <buffer> setlocal scrolloff=0
    au TermLeave <buffer> setlocal scrolloff=3

    nno <buffer><nowait><silent> I  I<c-a>
    nno <buffer><nowait><silent> A  A<c-e>
    nno <buffer><nowait><silent> C  i<c-k>
    nno <buffer><nowait><silent> D  i<c-k><c-\><c-n>
    nno <buffer><nowait><silent> cc i<c-e><c-u>
    nno <buffer><nowait><silent> dd i<c-e><c-u><c-\><c-n>

    xno <buffer><nowait><silent> c <nop>
    xno <buffer><nowait><silent> d <nop>
    xno <buffer><nowait><silent> p <nop>
    xno <buffer><nowait><silent> x <nop>
endfu

fu terminal#setup_vim() abort "{{{1
    " Neovim automatically disables `'wrap'` in a terminal buffer.
    " Not Vim. We do it in this function.
    setlocal nowrap
    " Here, `'termwinkey'` seems to behave a little like `C-r` in insert mode.
    " With one difference though: when specifying the register, you need to prefix it with `"`.
    exe 'nnoremap <buffer><nowait><silent> p i<c-e>'..&l:termwinkey..'""'

    " TODO: Once Vim supports `ModeChanged`, get rid of `s:fire_termenter()`.{{{
    "
    " Instead, refactor your autocmds to listen to `ModeChanged`.
    "
    " See: https://github.com/vim/vim/issues/2487#issuecomment-353735824
    " And `:h todo /modechanged`.
    "}}}
    nno <buffer><nowait><silent> i :<c-u>call <sid>fire_termenter('i')<cr>
    nno <buffer><nowait><silent> a :<c-u>call <sid>fire_termenter('a')<cr>

    nno <buffer><nowait><silent> I :<c-u>call <sid>fire_termenter('I<c-v><c-a>')<cr>
    nno <buffer><nowait><silent> A :<c-u>call <sid>fire_termenter('A<c-v><c-e>')<cr>

    nno <buffer><nowait><silent> C  :<c-u>call <sid>fire_termenter('i<c-v><c-k>')<cr>
    nno <buffer><nowait><silent> cc :<c-u>call <sid>fire_termenter('i<c-v><c-e><c-v><c-u>')<cr>
    nno <buffer><nowait><silent> D   i<c-k><c-\><c-n>
    nno <buffer><nowait><silent> dd  i<c-e><c-u><c-\><c-n>

    xno <buffer><nowait><silent> c <nop>
    xno <buffer><nowait><silent> d <nop>
    xno <buffer><nowait><silent> p <nop>
    xno <buffer><nowait><silent> x <nop>
endfu

fu s:fire_termenter(rhs) abort "{{{1
    exe 'norm! '..a:rhs[0]
    " Why does `TermEnter` need to be fired?{{{
    "
    " We have  a few autocmds  which listen to this  event to detect  that we've
    " switched from Terminal-Normal mode to Terminal-Job mode.
    "
    " ---
    "
    " It also fixes another issue.
    " In  a popup  terminal, if  you press  `i` while  in the  middle of  a long
    " scrollback buffer (e.g. `$ infocmp -1x`), Vim doesn't move the cursor back
    " to the bottom.
    " This leads to an unexpected screen: it doesn't display the end of the last
    " shell command (like what would happen in a normal terminal), and the shell
    " prompt is not visible until you insert a character.
    "}}}
    " Why not `CursorMoved`?{{{
    "
    " It's an unreliable proxy event.
    " It's fired  most of the time when we enter terminal-job mode, but not always.
    " For example, it's not fired when we're on the last line of the terminal buffer.
    "
    " Besides, using `CursorMoved` here means that  we would need to do the same
    " in any  autocmd whose purpose  is to  execute a command  when Terminal-Job
    " mode  is  entered.  But  `CursorMoved`  can  be  fired too  frequently  in
    " Terminal-Normal mode; so  our autocmds could be executed  too often (which
    " may have an impact even with a guard such as `if mode() is# 't'`).
    "}}}
    if exists('#User#TermEnter') | do <nomodeline> User TermEnter | endif
    if len(a:rhs) == 1 | return | endif
    call term_sendkeys('', a:rhs[1:])
endfu

fu terminal#fire_termleave() abort "{{{1
    if exists('#User#TermLeave')
        do <nomodeline> User TermLeave
    endif
    " Sometimes, the view is altered.{{{
    "
    "    1. open a popup terminal
    "    2. run `$ ls` a few times (enough to get a full screen of output)
    "    4. escape to terminal-normal mode
    "    6. re-enter terminal-job mode
    "    8. run `$ ls` one more time
    "    10. re-escape to terminal-normal mode
    "
    " The topline changes.
    " We don't want that; `zb` should preserve the view.
    "}}}
    norm! zb
endfu

