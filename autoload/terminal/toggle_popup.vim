if exists('g:autoloaded_terminal#toggle_popup')
    finish
endif
let g:autoloaded_terminal#toggle_popup = 1

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
    "\ frame color when in terminal-normal mode
    \ 'term_normal_highlight': 'Title',
    "\ frame color when in terminal-job mode
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
    " close popup terminal window if one already exists
    if exists('b:popup_terminal')
        return s:close()
    " In Nvim, we can toggle several windows on.{{{
    "
    " This can create a whole lot of issues.
    "
    " Solution: make sure there is only 1 window per Vim instance.
    " In the  future, you could  try 1  window per tab  page; but that  would be
    " inconsistent with  Vim, where you can  only have 1 popup  terminal per Vim
    " instance.
    "}}}
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
    " and execute `:LogEvents`,  then toggle the terminal window  on, you should
    " see that the frame is wrong.
    "}}}
    let [width, height, row, col] = s:get_term_geometry()
    let frame = s:get_frame(width, height)

    " create frame
    let [frame_bufnr, frame_winid] = s:popup(s:OPTS.term_normal_highlight, {
        \ 'row': row,
        \ 'col': col,
        \ 'width': width,
        \ 'height': height,
        \ 'frame': frame,
        \ })

    " create terminal
    let [term_bufnr, _] = s:popup('Normal', {
        \ 'row': row + 1,
        \ 'col': col + 2,
        \ 'width': width - 4,
        \ 'height': height - 2,
        \ })
    if has('nvim')
        call s:load_terminal_buffer()
        call s:wipe_frame_buffer_when_toggling_off(frame_bufnr)
        let s:popup_winid = win_getid()
    endif

    call s:dynamic_frame_color(frame_winid)

    " Vim doesn't restore the cursor position, nor the topline.  Nvim restores the cursor, but not the topline.
    if exists('s:view') | call winrestview(s:view) | endif
    if !exists('s:popup_bufnr') | let s:popup_bufnr = term_bufnr | endif
endfu
"}}}1
" Core {{{1
if has('nvim')
    fu s:popup(hl, opts) abort "{{{2
        let bufnr = nvim_create_buf(v:false, v:true)
        let opts = extend({'relative': 'editor', 'style': 'minimal'}, a:opts)
        let frame = has_key(opts, 'frame') ? remove(opts, 'frame') : []
        let winid = nvim_open_win(bufnr, v:true, opts)
        call setwinvar(winid, '&winhighlight', 'NormalFloat:'..a:hl)
        if !empty(frame)
          call nvim_buf_set_lines(bufnr, 0, -1, v:true, frame)
        endif
        return [bufnr, winid]
    endfu
else "{{{2
    fu s:popup(hl, opts) abort "{{{2
        let is_frame = has_key(a:opts, 'frame')
        " Do *not* use `get()`.{{{
        "
        "     let bufnr = get(s:, 'bufnr', term_start(&shell, #{hidden: 1}))
        "
        " Every time you would toggle the window, a new terminal buffer would be
        " created.  This is because  `term_start()` is evaluated before `get()`.
        " IOW, before `get()` checks whether `s:popup_bufnr` exists.
        "}}}
        if is_frame
            let bufnr = ''
        elseif exists('s:popup_bufnr')
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
        let id = popup_create(bufnr, #{
            \ line: a:opts.row,
            \ col: a:opts.col,
            \ minwidth: a:opts.width,
            \ maxwidth: a:opts.width,
            \ minheight: a:opts.height,
            \ maxheight: a:opts.height,
            \ zindex: 50 - is_frame,
            \ })

        call setwinvar(id, '&wincolor', a:hl)

        if is_frame
            call setbufline(winbufnr(id), 1, a:opts.frame)
            exe 'au BufWipeout,BufHidden * ++once call popup_close('..id..')'
        else
            " Install our custom terminal settings as soon as the terminal buffer is displayed in a window.{{{
            "
            " Useful, for  example, to get  our `Esc  Esc` key binding,  and for
            " `M-p` to  work (i.e. recall  latest command starting  with current
            " prefix).
            "}}}
            if exists('#TerminalWinOpen') | do <nomodeline> TerminalWinOpen | endif
            " Why the delay?{{{
            "
            " The   `TermEnter`   autocmd   which  updates   the   frame   color
            " depending  on  the  terminal  mode  has  not  been  installed  yet.
            " `s:dynamic_frame_color()` will be invoked later.
            "}}}
            au SafeState * ++once if exists('#User#TermEnter') | do <nomodeline> User TermEnter | endif
        endif

        return [winbufnr(id), id]
    endfu
    "}}}2
endif
fu s:close(...) abort "{{{2
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
        let s:view = winsaveview()
        call popup_close(win_getid())
    endif
endfu

fu s:get_frame(width, height) abort "{{{2
    let top = '┌'..repeat('─', a:width - 2)..'┐'
    let mid = '│'..repeat(' ', a:width - 2)..'│'
    let bot = '└'..repeat('─', a:width - 2)..'┘'
    let frame = [top] + repeat([mid], a:height - 2) + [bot]
    return frame
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
    " Vim and Nvim don't start to count rows and columns from the same number.{{{
    "
    " From `:h popup_create-arguments /first line`:
    "
    " >     The first line is 1.
    "
    " From `:h popup_create-arguments /first column`:
    "
    " >     The first column is 1.
    "
    " From `:h nvim_open_win()`:
    "
    " >     With relative=editor (row=0,col=0) refers to the top-left
    " >     corner of the screen-grid ...
    "
    " So, if `row` is 0 in Nvim (first screen line), it needs to be 1 in Vim.
    "}}}
    if !has('nvim')
        let row += 1
        let col += 1
    endif

    return [width, height, row, col]
endfu

fu s:load_terminal_buffer() abort "{{{2
    if exists('s:popup_bufnr')
        exe 'b '..s:popup_bufnr
        bw#
    else
        call termopen(&shell) | let b:popup_terminal = v:true
    endif
endfu

fu s:wipe_frame_buffer_when_toggling_off(frame) abort "{{{2
    augroup wipe_frame
        au! * <buffer>
        exe 'au BufHidden,BufWipeout <buffer> '
            \ 'exe "au! wipe_frame * <buffer>" | bw '..a:frame
    augroup END
endfu

fu s:dynamic_frame_color(frame_winid) abort "{{{2
    augroup dynamic_frame_color
        au! * <buffer>
        if has('nvim')
            exe 'au TermEnter <buffer> '
                \ ..printf('call setwinvar(%d, "&winhighlight", "NormalFloat:%s")',
                \ a:frame_winid, s:OPTS.term_job_highlight)
            exe 'au TermLeave <buffer> '
                \ ..printf('call setwinvar(%d, "&winhighlight", "NormalFloat:%s")',
                \ a:frame_winid, s:OPTS.term_normal_highlight)
        else
            exe 'au! User TermEnter '
                \ ..printf('call setwinvar(%d, "&wincolor", "%s")',
                \ a:frame_winid, s:OPTS.term_job_highlight)
            exe 'au! User TermLeave '
                \ ..printf('call setwinvar(%d, "&wincolor", "%s")',
                \ a:frame_winid, s:OPTS.term_normal_highlight)
        endif
    augroup END
endfu
"}}}1
" Util {{{1
fu s:is_popup_terminal_on() abort "{{{2
    return index(map(getwininfo(), {_,v -> getbufvar(v.bufnr, 'popup_terminal')}), v:true) != -1
endfu

