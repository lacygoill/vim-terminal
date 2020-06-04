if exists('g:autoloaded_terminal#toggle_popup')
    finish
endif
let g:autoloaded_terminal#toggle_popup = 1

" Inspiration:
" https://github.com/junegunn/fzf/commit/7ceb58b2aadfcf0f5e99da83626cf88d282159b2
" https://github.com/junegunn/fzf/commit/a859aa72ee0ab6e7ae948752906483e468a501ee

" Init {{{1

const s:OPTS = {
    "\ percentage of the total width
    \ 'width': 0.9,
    "\ percentage of the total height
    \ 'height': 0.6,
    "\ the closer to 1 the further to the right
    \ 'xoffset': 0.5,
    "\ the closer to 1 the lower the window
    \ 'yoffset': 0.5,
    "\ border color when in terminal-normal mode
    \ 'normal_highlight': 'Title',
    "\ border color when in terminal-job mode
    \ 'job_highlight': 'Comment',
    \ }

fu s:sanitize() abort
    unlockvar s:OPTS
    for key in ['width', 'height', 'xoffset', 'yoffset']
        if s:OPTS[key] < 0
            let s:OPTS[key] = key =~# 'offset' ? 0 : 0.1
        elseif s:OPTS[key] > 1
            " not `1` for the height to still see what we write on the Ex command-line
            let s:OPTS[key] = key is# 'height' ? 0.99 : 1
        endif
    endfor
    lockvar s:OPTS
endfu
call s:sanitize()

let s:popup = {}

const s:DEBUG = 0
if s:DEBUG
    let g:popup = s:popup
endif

" Interface {{{1
fu terminal#toggle_popup#main() abort "{{{2
    " Why don't you set and inspect an ad-hoc buffer-local variable?{{{
    "
    " It would not be reliable.
    " In Nvim, the popup terminal window is not necessarily the current window.
    " I think the same is true in Vim, because you can open several popup terminals atm.
    "}}}
    if has_key(s:popup, 'winid')
        " if the popup terminal is already open on the current tab page, just close it
        if s:is_open_on_current_tabpage()
            return s:close()
        " if it's open on another tab page, close it, then re-open it in the current tab page
        else
            call s:close()
        endif
    endif

    let [bufnr, opts] = [get(s:popup, 'bufnr', -1), s:get_opts()]
    try
        let [term_bufnr, term_winid; border] = lg#popup#create(bufnr, opts)
    catch /^Vim\%((\a\+)\)\=:E117:/
        echohl ErrorMsg | echom 'need lg#popup#create(); install vim-lg-lib' | echohl NONE
        return
    endtry

    if !has_key(s:popup, 'bufnr') | let s:popup.bufnr = term_bufnr | endif
    let s:popup.winid = term_winid
    " If the buffer gets wiped out by accident, re-init the variable.{{{
    "
    " Otherwise, when you toggle the popup window  on, you get an error in Nvim,
    " and a different buffer in Vim (after every toggling).
    "}}}
    au BufWipeout <buffer> ++once let s:popup = {}
    " Necessary if we close the popup with a mapping which doesn't invoke this function.{{{
    "
    " A mapping which closes the popup via a simple `popup_close()`.
    " In that case, the key gets stale and  needs to be cleaned up, to not cause
    " errors the next time we want to toggle the popup on.
    "
    " Don't try to clean the key from `s:close()`:
    "
    "    - it's not reliable enough;
    "      again, you can close the popup in different ways
    "
    "    - this autocmd will do it already;
    "      doing it a second time would raise `E716` (yes, even with a bang after `:unlet`)
    "}}}
    " Do *not* use `BufWinLeave`.{{{
    "
    " Listening  to `BufWinLeave`  can lead  to gross  cascading problems  after
    " pressing `gf` on a file path.
    " That's because, in  that case, `BufWinLeave` is fired and  the `winid` key
    " is removed; but  the popup is not  closed, so we don't want  `winid` to be
    " removed, it's still valid.
    "
    " OTOH,  `WinLeave` is  *not* fired  when we  press `gf`,  so we  can safely
    " listen to it.
    "
    " Note  that a  popup terminal  window  is not  meant to  display a  regular
    " buffer.   If  you manage  to  do  it (e.g.  by  pressing  `gf` on  a  file
    " path),  you may  encounter all  sorts  of weird  issues (cursor  position,
    " `popup_close()` failure, ...).
    "}}}
    " Do *not* use `<buffer>`.{{{
    "
    " There is no guarantee that when you toggle off the popup, it will be still
    " displaying the terminal buffer.
    "
    " `*` would  cause issues in Nvim  if you try  to toggle on the  popup after
    " toggling it  off while it was  displaying a regular buffer  (can happen if
    " you press `gf` on a file path).
    "}}}
    au WinLeave * ++once unlet! s:popup.winid

    call s:terminal_job_mapping()
    call s:dynamic_border_color(has('nvim') ? border[1] : term_winid)
    call s:preserve_view()
    if has('nvim') | call s:preserve_lastmode() | endif
    return ''
endfu
"}}}1
" Core {{{1
fu s:close() abort "{{{2
    let s:popup.view = winsaveview()
    if !has('nvim')
        try
            call popup_close(s:popup.winid)
        " can happen after you've loaded a regular file in a terminal popup by pressing `gf`
        catch /^Vim\%((\a\+)\)\=:E994:/
            return lg#catch()
        endtry
    else
        if s:popup.winid == win_getid()
            close
        else
            let curwinid = win_getid()
            call win_gotoid(s:popup.winid)
            close
            call win_gotoid(curwinid)
        endif
    endif
endfu

fu s:terminal_job_mapping() abort "{{{2
    if !exists('g:_termpopup_lhs') | return | endif

    " Assumption: `g:_termpopup_lhs` starts with `<c-g>`
    " Purpose:{{{
    "
    " When we  press `C-g  C-g` in a  terminal popup, the  zsh snippets  are not
    " visible until we press another key, or until the timeout.
    "
    " Here's what happens.
    "
    " When you press the first `C-g`, it's written in the typeahead buffer.
    " It's  not  executed,  because  Vim  sees   that  you  have  a  mapping  in
    " Terminal-Job mode starting with `C-g`.  Vim must wait until the timeout to
    " know whether `C-g` should be remapped.
    "
    " When you  press the second  `C-g` immediately  after the first,  it's also
    " written in the  typeahead buffer.  No mapping starts with  2 `C-g`, so now
    " Vim knows that  you didn't want to use  the first `C-g` as the  start of a
    " mapping; it can't be remapped and so gets executed, i.e. sent to the shell
    " job.
    "
    " But the  second `C-g`  suffers from the  same issue as  did the  first one
    " previously; Vim must wait until the timeout.
    "
    " Issue: How to avoid this timeout?
    " Solution: Install a  mapping which remaps  `C-g C-g` into itself,  so that
    " when you press `C-g C-g`, it gets remapped and executed immediately.
    "}}}
    tno <buffer><nowait> <c-g><c-g> <c-g><c-g>

    if has('nvim')
        exe 'tno <buffer><nowait><silent> '..g:_termpopup_lhs
            \ ..' <c-\><c-n>:call <sid>nvim_toggle()<cr>'
    else
        exe printf('tno <buffer><nowait><silent> %s %s:<c-u>call terminal#toggle_popup#main()<cr>',
            \ g:_termpopup_lhs, &l:twk == '' ? '<c-w>' : &l:twk)
    endif
endfu

fu s:dynamic_border_color(winid) abort "{{{2
    augroup dynamic_border_color
        if has('nvim')
            au! * <buffer>
            exe 'au TermEnter <buffer> '
                \ ..printf('call setwinvar(%d, "&winhighlight", "NormalFloat:%s")',
                \ a:winid, s:OPTS.job_highlight)
            exe 'au TermLeave <buffer> '
                \ ..printf('call setwinvar(%d, "&winhighlight", "NormalFloat:%s")',
                \ a:winid, s:OPTS.normal_highlight)
        else
            let cmd = printf('if win_getid() == %d|call popup_setoptions(%d, %s)|endif',
                \ a:winid, a:winid, #{borderhighlight: [s:OPTS.job_highlight]})
            exe 'au! User TermEnter '..cmd
            " Why inspecting `mode()`?{{{
            "
            " Initially, the border is highlighted by `s:OPTS.normal_highlight`.
            " This command resets the highlighting to `s:OPTS.job_highlight`.
            " This is correct  the first time we toggle the  popup on, because we're
            " automatically in Terminal-Job mode.
            " Afterwards,  this   is  wrong;   we're  no  longer   automatically  in
            " Terminal-Job mode; we stay in Terminal-Normal mode.
            "
            " I *think* that when you display  a *new* terminal buffer, Vim puts you
            " in Terminal-Job mode automatically.
            " OTOH, when  you display  an *existing*  terminal buffer,  Vim probably
            " remembers the last mode you were in.
            "}}}
            if mode() is# 't' | exe cmd | endif
            " Why `:redraw`?{{{
            "
            " To make Vim apply the new color on the border.
            "
            " ---
            "
            " Note that  – at the moment  – we don't need  `:redraw`, but that's
            " only  thanks to  a side-effect  of an  autocmd in  `vim-readline`,
            " whose effect can be reproduced with:
            "
            "     au CmdlineEnter : call timer_start(0, {-> 0})
            "
            " But that's probably brittle, and I don't fully understand what happens.
            " I guess we have some terminal mappings which trigger `CmdlineEnter`,
            " which in turn invoke the timer, which in turn causes the redraw.
            "}}}
            exe 'au! User TermLeave '
                \ ..printf('if win_getid() == %d|call popup_setoptions(%d, %s)|redraw|endif',
                \ a:winid, a:winid, #{borderhighlight: [s:OPTS.normal_highlight]})
        endif
    augroup END
endfu

fu s:preserve_view() abort "{{{2
    " Make the view persistent when we toggle the window on and off.{{{
    "
    " By  default, Vim  doesn't seem  to restore  the cursor  position, nor  the
    " topline.  Nvim restores the cursor, but not the topline.
    "}}}
    " We already have an autocmd restoring the view in `vim-window`.  Why is this necessary?{{{
    "
    " This autocmd doesn't work for special buffers (including terminal buffers).
    " Besides, it can only work when you re-display a buffer in the same window.
    " That's not what is happening here; we re-display a buffer in a *new* window.
    "}}}
    if has_key(s:popup, 'view') | call winrestview(s:popup.view) | endif
endfu

fu s:preserve_lastmode() abort "{{{2
    " if the  last time we  toggled the popup  off, we were  in Terminal-Job
    " mode, we want to get back in Terminal-Job mode now
    if get(s:popup, 'lastmode', 'n') is# 't'
        call feedkeys('i', 'in')
    endif
    let s:popup.lastmode = 'n'
endfu

fu s:nvim_toggle() abort "{{{2
    let s:popup.lastmode = 't'
    call terminal#toggle_popup#main()
endfu
"}}}1
" Util {{{1
fu s:get_opts() abort "{{{2
    " Do *not* move these assignments outside this function.{{{
    "
    " These variables must be re-computed at runtime, on every toggling.
    " That's because Vim's geometry (i.e. `&columns`, `&lines`) can change at runtime.
    " In particular, the geometry it had  at startup time is not necessarily the
    " same as when this function is invoked.
    "
    " For example, if  you move these assignments directly to  the script level,
    " and execute  `:LogEvents`, then toggle  the popup terminal window  on, you
    " should see that the border is wrong.
    "}}}
    let [row, col, width, height] = s:get_geometry()
    let opts = {
        \ 'row': row,
        \ 'col': col,
        \ 'width': width,
        \ 'height': height,
        \ }
    call extend(opts, {'borderhighlight': s:OPTS.normal_highlight, 'term': v:true})
    return opts
endfu

fu s:get_geometry() abort "{{{2
    let width = float2nr(&columns * s:OPTS.width) - 4
    let height = float2nr(&lines * s:OPTS.height) - 2

    " Why `&lines - height`?  Why not just `&lines`{{{
    "
    " If your `yoffset`  is 1, and you  just write `&lines`, then  `row` will be
    " set to `&lines`, which  is wrong; the top of the popup  window can't be on
    " the last line of the screen; the lowest it can be is `&lines - height`.
    "}}}
    let row = float2nr(s:OPTS.yoffset * (&lines - height))
    let col = float2nr(s:OPTS.xoffset * (&columns - width))

    return [row, col, width, height]
endfu

fu s:is_open_on_current_tabpage() abort "{{{2
    if !has('nvim')
        " If the popup is in the current tab page, the key 'tabpage' will have the value 0.{{{
        "
        " If it's  global (i.e. displayed on  all tab pages), the  key will have
        " the value  -1.  And if  it's only displayed  on another tab  page, its
        " value will be the index of that tab page.
        "}}}
        return get(popup_getoptions(s:popup.winid), 'tabpage', -1) == 0
    else
        return get(get(getwininfo(s:popup.winid), 0), 'tabnr') == tabpagenr()
    endif
endfu

