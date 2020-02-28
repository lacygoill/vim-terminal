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
    \ 'term_normal_highlight': 'Title',
    "\ border color when in terminal-job mode
    \ 'term_job_highlight': 'Comment',
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

" Interface {{{1
fu terminal#toggle_popup#main() abort "{{{2
    " close popup terminal window if it's already on
    if exists('b:popup_terminal')
        return s:close()
    " in Nvim, the popup terminal window is not necessarily the current window
    elseif has('nvim') && s:is_popup_terminal_on()
        call s:close(s:popup_winid)
    endif

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
    let [width, height, row, col] = s:get_term_geometry()

    if has('nvim')
        " create border
        let border = s:get_border(width, height)
        let [border_bufnr, border_winid] = s:popup({
            \ 'width': width,
            \ 'height': height,
            \ 'row': row,
            \ 'col': col,
            \ 'hl': s:OPTS.term_normal_highlight,
            \ 'border': border,
            \ })
        " create float
        let [term_bufnr, _] = s:popup({
            \ 'width': width - 4,
            \ 'height': height - 2,
            \ 'row': row + 1,
            \ 'col': col + 2,
            \ 'hl': 'Normal',
            \ })
        call s:wipe_border_when_toggling_off(border_bufnr)
        let s:popup_winid = win_getid()
        call s:dynamic_border_color(border_winid)
    else
        let [term_bufnr, term_winid] = s:popup({
            \ 'width': width - 4,
            \ 'height': height - 2,
            \ 'row': row + 1,
            \ 'col': col + 2,
            \ })
        call s:dynamic_border_color(term_winid)
    endif

    call s:persistent_view()
    if !exists('s:popup_bufnr') | let s:popup_bufnr = term_bufnr | endif
endfu
"}}}1
" Core {{{1
if has('nvim')
    fu s:popup(opts) abort "{{{2
        let opts = extend({'relative': 'editor', 'style': 'minimal'}, a:opts)
        let is_border = has_key(opts, 'border')
        let border = is_border ? remove(opts, 'border') : []
        if is_border || !exists('s:popup_bufnr')
            let bufnr = nvim_create_buf(v:false, v:true)
        else
            let bufnr = s:popup_bufnr
        endif
        " open window
        let hl = remove(opts, 'hl')
        let winid = nvim_open_win(bufnr, v:true, opts)
        " highlight background
        call setwinvar(winid, '&winhighlight', 'NormalFloat:'..hl)
        if is_border
            call nvim_buf_set_lines(bufnr, 0, -1, v:true, border)
        elseif !exists('s:popup_bufnr')
            " `termopen()` does not create a new buffer; it converts the current buffer into a terminal buffer
            call termopen(&shell)
            let b:popup_terminal = v:true
        endif
        return [bufnr, winid]
    endfu
else "{{{2
    fu s:popup(opts) abort "{{{2
        " Do *not* use `get()`.{{{
        "
        "     let bufnr = get(s:, 'bufnr', term_start(&shell, #{hidden: 1}))
        "
        " Every time you would toggle the window, a new terminal buffer would be
        " created.  This is because  `term_start()` is evaluated before `get()`.
        " IOW, before `get()` checks whether `s:popup_bufnr` exists.
        "}}}
        if exists('s:popup_bufnr')
            let bufnr = s:popup_bufnr
        else
            let bufnr = term_start(&shell, #{hidden: v:true})
            call setbufvar(bufnr, 'popup_terminal', v:true)
        endif

        " We really need the `maxwidth` and `maxheight` keys.{{{
        "
        " Otherwise, when  we scroll back  in a  long shell command  output, the
        " terminal buffer contents goes beyond the end of the window.
        "}}}
        let winid = popup_create(bufnr, #{
            \ line: a:opts.row,
            \ col: a:opts.col,
            \ minwidth: a:opts.width,
            \ maxwidth: a:opts.width,
            \ minheight: a:opts.height,
            \ maxheight: a:opts.height,
            \ highlight: 'Normal',
            \ border: [],
            \ borderhighlight: [s:OPTS.term_normal_highlight],
            \ borderchars: ['─', '│', '─', '│', '┌', '┐', '┘', '└'],
            \ padding: [0, 1, 0, 1],
            \ zindex: 50,
            \ })

        " Install our custom terminal settings as soon as the terminal buffer is displayed in a window.{{{
        "
        " Useful, for example,  to get our `Esc Esc` key  binding, and for `M-p`
        " to work (i.e. recall latest command starting with current prefix).
        "}}}
        if exists('#TerminalWinOpen') | do <nomodeline> TerminalWinOpen | endif
        if exists('#User#TermEnter') | do <nomodeline> User TermEnter | endif

        return [winbufnr(winid), winid]
    endfu
    "}}}2
endif
fu s:close(...) abort "{{{2
    let s:view = winsaveview()
    if has('nvim')
        if a:0
            let curwinid = win_getid()
            call win_gotoid(a:1)
            close
            call win_gotoid(curwinid)
        else
            close
        endif
    else
        call popup_close(win_getid())
    endif
endfu

fu s:get_border(width, height) abort "{{{2
    let top = '┌'..repeat('─', a:width - 2)..'┐'
    let mid = '│'..repeat(' ', a:width - 2)..'│'
    let bot = '└'..repeat('─', a:width - 2)..'┘'
    let border = [top] + repeat([mid], a:height - 2) + [bot]
    return border
endfu

fu s:get_term_geometry() abort "{{{2
    let width = float2nr(&columns * s:OPTS.width)
    let height = float2nr(&lines * s:OPTS.height)

    " Why `&lines - height`?  Why not just `&lines`{{{
    "
    " If your `yoffset`  is 1, and you  just write `&lines`, then  `row` will be
    " set to `&lines`, which  is wrong; the top of the popup  window can't be on
    " the last line of the screen; the lowest it can be is `&lines - height`.
    "}}}
    let row = float2nr(s:OPTS.yoffset * (&lines - height))
    let col = float2nr(s:OPTS.xoffset * (&columns - width))
    " to get the exact same position in Vim and Nvim
    if !has('nvim') | let col -= 1 | endif

    return [width, height, row, col]
endfu

fu s:wipe_border_when_toggling_off(border) abort "{{{2
    augroup wipe_border
        au! * <buffer>
        exe 'au BufHidden,BufWipeout <buffer> '
            \ ..'exe "au! wipe_border * <buffer>" | bw '..a:border
    augroup END
endfu

fu s:dynamic_border_color(winid) abort "{{{2
    augroup dynamic_border_color
        au! * <buffer>
        if has('nvim')
            exe 'au TermEnter <buffer> '
                \ ..printf('call setwinvar(%d, "&winhighlight", "NormalFloat:%s")',
                \ a:winid, s:OPTS.term_job_highlight)
            exe 'au TermLeave <buffer> '
                \ ..printf('call setwinvar(%d, "&winhighlight", "NormalFloat:%s")',
                \ a:winid, s:OPTS.term_normal_highlight)
        else
            let cmd = printf('call popup_setoptions(%d, %s)',
                \ a:winid, {'borderhighlight': [s:OPTS.term_job_highlight]})
            exe 'au! User TermEnter '..cmd
            " Why inspecting `mode()`?{{{
            "
            " Initially, the border is highlighted by `s:OPTS.term_normal_highlight`.
            " This command resets the highlighting to `s:OPTS.term_job_highlight`.
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
            exe 'au! User TermLeave '
                \ ..printf('call popup_setoptions(%d, %s)',
                \ a:winid, {'borderhighlight': [s:OPTS.term_normal_highlight]})
        endif
    augroup END
endfu

fu s:persistent_view() abort "{{{2
    " make the view persistent when we enter/leave Terminal-Job mode
    if has('nvim')
        " TODO: Remove this function call, and the autocmd, once `'scrolloff'` becomes window-local (cf. PR #11854).{{{
        "
        " If  you  sometimes  notice  that  the view  is  altered  when  leaving
        " Terminal-Job mode, it's probably because of our autocmd which restores
        " the global value of `'so'` to 3.
        "
        " Don't try to fix that.  You probably can't.
        " Just wait for  the PR to be  merged, remove the code  here, then check
        " whether the view is still altered.
        "}}}
        call s:handle_scrolloff()
        au TermLeave <buffer> let s:_view = winsaveview()
            \ | call timer_start(0, {-> exists('s:_view') && winrestview(s:_view)})
    endif

    " FIXME: In Vim, the cursor position is often not preserved.{{{
    "
    "     C-g C-g
    "     $ infocmp -1x
    "     Esc Esc
    "     i
    "     $ ls
    "     Esc Esc  " unexpected view
    "
    " ---
    "
    "     C-g C-g
    "     $ infocmp -1x
    "     C-l
    "     Esc Esc  " unexpected view
    "     gg
    "     i
    "     Esc Esc  " unexpected view
    "     i        " unexpected view
    "
    " Don't try to install an autocmd like for Nvim; it doesn't work.
    " This is a bug.
    "
    " I can also reproduce even without running any shell command; just quitting
    " to Terminal-Normal mode once or twice.
    " Note that in reality, the cursor position is correct; it's just "drawn"
    " in the wrong position; if you press some motion key, you'll see that the cursor
    " was in the correct position.  Vim doesn't seem to redraw enough.
    "
    " I can also reproduce without leaving Terminal-Normal mode.
    " Just press `50%`, then `l`.
    " Or just enter and  leave the Ex command-line (this one  is probably due to
    " our custom mapping, but still...).
    "
    " The issue is influenced by the 'border' and 'padding' keys.
    " And by:
    "
    "    - `'startofline'`
    "    - the matchup plugin; probably because of the `%` mapping
    "    - the readline plugin; because of an autocmd listening to `CmdlineEnter :` which invokes a timer:
    "
    "         au CmdlineEnter : call timer_start(0, {-> execute('')})
    "
    " Also, note that most (any?) custom normal command seem to alter the cursor
    " position (even our custom `m` command).
    "}}}
    " temporary workaround
    if !has('nvim')
        if mode(1) is# 'n'
            call timer_start(0, {-> s:fix_pos()})
        endif
        au User TermLeave call timer_start(0, {-> s:fix_pos()})
    endif

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
    if exists('s:view') | call winrestview(s:view) | endif
endfu
"}}}1
" Util {{{1
fu s:is_popup_terminal_on() abort "{{{2
    return index(map(getwininfo(), {_,v -> getbufvar(v.bufnr, 'popup_terminal')}), v:true) != -1
endfu

fu s:handle_scrolloff() abort "{{{2
    au! terminal_disable_scrolloff * <buffer>
    set so=0
    augroup popup_terminal_toggle_scrolloff
        au! * <buffer>
        au WinLeave <buffer> set so=3
        au WinEnter <buffer> set so=0
    augroup END
endfu

fu s:fix_pos() abort "{{{2
    let pos = getpos("'m")
    call feedkeys('mmk`m', 'int')
    call timer_start(0, {-> setpos("'m", pos)})
endfu

