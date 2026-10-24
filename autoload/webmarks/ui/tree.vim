scriptencoding utf-8
" ui/tree.vim - the webmarks://tree buffer
"
" One buffer, any number of windows (also in other tab pages). Rendering
" is split into a buffer part (rows + lines, once) and a window part
" (cursor, highlights, folds; for every window via win_execute()), so a
" redraw never switches tab pages or moves the user's window.

let s:save_cpo = &cpoptions
set cpoptions&vim

let s:name = 'webmarks://tree'
let s:edit_msg = 'unsaved edits: :w to apply, :e! to discard'

" action -> default key, in help order
let s:actions = [
      \ ['open', '<CR>'], ['add', 'a'], ['add-folder', 'A'], ['rename', 'r'],
      \ ['edit-url', 'e'], ['move', 'm'], ['delete', 'd'], ['favorite', '*'],
      \ ['refetch', 't'], ['yank', 'y'], ['sort-recent', 'S'], ['sort-name', '~'],
      \ ['sort-frecency', 'F'], ['toggle-favorite-first', 'P'], ['toggle-view', 'T'],
      \ ['search', 's'], ['reload', 'R'], ['edit', 'i'], ['close', 'q'], ['help', 'g?'],
      \ ]

" --- options -------------------------------------------------------------

" name -> [allowed type(s), allowed values or [] for any, default]
let s:option_rules = {
      \ 'open': [[v:t_string], ['vsplit', 'split', 'edit', 'tab'], 'vsplit'],
      \ 'width': [[v:t_number], [], 40],
      \ 'default_sort': [[v:t_string], ['name', 'recent', 'frecency'], 'frecency'],
      \ 'favorite_first': [[v:t_number, v:t_bool], [], 1],
      \ 'default_view': [[v:t_string], ['tree', 'flat'], 'tree'],
      \ 'fetch_title': [[v:t_number, v:t_bool], [], 1],
      \ 'no_default_mappings': [[v:t_number, v:t_bool], [], 0],
      \ }

function! s:valid_option(name, value) abort
  let [l:types, l:values, l:_] = s:option_rules[a:name]
  if index(l:types, type(a:value)) < 0
    return 0
  endif
  if !empty(l:values)
    return index(l:values, a:value) >= 0
  endif
  return a:name !=# 'width' || a:value > 0
endfunction

" option(name) -> the validated value of g:webmarks_{name}. A bad value
" falls back to the built-in default with a one-time warning.
function! webmarks#ui#tree#option(name) abort
  let l:default = s:option_rules[a:name][2]
  if !exists('g:webmarks_' . a:name)
    return l:default
  endif
  let l:v = get(g:, 'webmarks_' . a:name)
  if s:valid_option(a:name, l:v)
    return l:v
  endif
  call webmarks#compat#notify#warn_once('bad_option:' . a:name . ':' . string(l:v),
        \ printf('invalid g:webmarks_%s: %s (using default)', a:name, string(l:v)))
  return l:default
endfunction

function! webmarks#ui#tree#default_policy() abort
  return {'criterion': webmarks#ui#tree#option('default_sort'),
        \ 'favorite_first': webmarks#ui#tree#option('favorite_first') ? v:true : v:false}
endfunction

" The policy of the tree buffer if it exists, else the defaults.
function! webmarks#ui#tree#current_policy() abort
  let l:buf = webmarks#ui#tree#bufnr()
  let l:state = l:buf > 0 ? getbufvar(l:buf, 'webmarks', {}) : {}
  return empty(l:state) ? webmarks#ui#tree#default_policy() : copy(l:state.policy)
endfunction

" --- buffer ----------------------------------------------------------------

" The tree buffer number, or -1.
function! webmarks#ui#tree#bufnr() abort
  " exact name: bufnr() treats its argument as a pattern
  for l:info in getbufinfo()
    if l:info.name ==# s:name
      return l:info.bufnr
    endif
  endfor
  return -1
endfunction

function! s:ensure_buffer() abort
  let l:buf = webmarks#ui#tree#bufnr()
  if l:buf > 0
    return l:buf
  endif
  let l:buf = exists('*bufadd') ? bufadd(s:name) : bufnr(s:name, 1)
  call bufload(l:buf)
  " before any window shows it: no swapfile, never written to disk
  call setbufvar(l:buf, '&buftype', 'acwrite')
  call setbufvar(l:buf, '&bufhidden', 'hide')
  call setbufvar(l:buf, '&swapfile', 0)
  call setbufvar(l:buf, '&buflisted', 0)
  call setbufvar(l:buf, '&modeline', 0)
  call setbufvar(l:buf, '&undolevels', -1)
  call setbufvar(l:buf, '&modifiable', 0)
  return l:buf
endfunction

" Called once, with the tree buffer current.
function! s:init_buffer() abort
  " FileType first: the user's `autocmd FileType webmarks nmap <buffer>`
  " runs before our hasmapto() checks
  setlocal filetype=webmarks
  let b:webmarks = {
        \ 'policy': webmarks#ui#tree#default_policy(),
        \ 'view': webmarks#ui#tree#option('default_view'),
        \ 'rows': [], 'mode': 'view', 'mapped_keys': [],
        \ 'edit': {'snapshot_ids': [], 'mapped_keys': [], 'dirty': 0},
        \ }
  call s:define_plug_maps()
  call s:map_default_keys()
  call webmarks#ui#tree#define_highlights()
  augroup webmarks
    autocmd!
    autocmd ColorScheme * call webmarks#ui#tree#define_highlights()
  augroup END
  augroup webmarks_buf
    autocmd! * <buffer>
    autocmd BufWriteCmd <buffer> call webmarks#ui#tree#on_write()
    autocmd BufReadCmd <buffer> call webmarks#ui#tree#on_read()
    autocmd BufWinEnter <buffer> call webmarks#ui#tree#on_buf_win_enter()
    " :split of the tree fires WinEnter but not BufWinEnter
    autocmd WinEnter <buffer> if !exists('w:webmarks_layout') | call webmarks#ui#tree#on_buf_win_enter() | endif
    autocmd BufLeave <buffer> call webmarks#ui#tree#on_buf_leave()
  augroup END
endfunction

function! webmarks#ui#tree#define_highlights() abort
  highlight default link WebmarksFolder Directory
  highlight default link WebmarksFavorite Special
  highlight default link WebmarksPending Comment
  highlight default link WebmarksPath Comment
  highlight default link WebmarksEmpty Comment
endfunction

function! s:define_plug_maps() abort
  for [l:action, l:_] in s:actions
    if l:action ==# 'search'
      " the fzf picker belongs to the command layer, not to ui/tree
      nnoremap <buffer> <silent> <Plug>(webmarks-search) :<C-u>WebmarksSearch<CR>
    else
      execute printf('nnoremap <buffer> <silent> <Plug>(webmarks-%s) :<C-u>call webmarks#ui#tree#action(%s)<CR>',
            \ l:action, string(l:action))
    endif
  endfor
endfunction

" Map the default keys that the user has not mapped to the action.
" Returns the keys that were mapped.
function! s:action_of(key) abort
  for [l:action, l:key] in s:actions
    if l:key ==# a:key
      return l:action
    endif
  endfor
  return ''
endfunction

function! s:map_default_keys() abort
  let b:webmarks.mapped_keys = []
  if webmarks#ui#tree#option('no_default_mappings')
    return
  endif
  for [l:action, l:key] in s:actions
    let l:plug = '<Plug>(webmarks-' . l:action . ')'
    if !hasmapto(l:plug, 'n')
      execute 'nmap <buffer> <nowait>' l:key l:plug
      call add(b:webmarks.mapped_keys, l:key)
    endif
  endfor
endfunction

" --- windows ---------------------------------------------------------------

function! s:windows(buf) abort
  return win_findbuf(a:buf)
endfunction

" Window-local settings for the current window (a tree window).
function! s:apply_window_options() abort
  setlocal nowrap nonumber norelativenumber cursorline foldcolumn=0 nolist
  if exists('+signcolumn')
    setlocal signcolumn=no
  endif
  let l:want = b:webmarks.mode ==# 'edit' ? 'edit' : b:webmarks.view
  if get(w:, 'webmarks_layout', '') ==# l:want
    return
  endif
  let w:webmarks_layout = l:want
  if l:want ==# 'tree'
    setlocal foldmethod=expr foldexpr=webmarks#ui#tree#foldexpr(v:lnum)
    setlocal foldtext=webmarks#ui#tree#foldtext() foldlevel=99 foldminlines=0
    setlocal conceallevel=0
  else
    setlocal foldmethod=manual
    silent! normal! zE
    if l:want ==# 'edit'
      setlocal conceallevel=2 concealcursor=nc
    else
      setlocal conceallevel=0
    endif
  endif
endfunction

function! s:clear_matches() abort
  for l:id in get(w:, 'webmarks_match_ids', [])
    silent! call matchdelete(l:id)
  endfor
  let w:webmarks_match_ids = []
endfunction

function! s:apply_matches() abort
  call s:clear_matches()
  if b:webmarks.mode ==# 'edit'
    return
  endif
  let l:by_group = {}
  let l:lnum = 0
  for l:row in b:webmarks.rows
    let l:lnum += 1
    for [l:group, l:col, l:len] in l:row.hl
      if !has_key(l:by_group, l:group)
        let l:by_group[l:group] = []
      endif
      call add(l:by_group[l:group], [l:lnum, l:col, l:len])
    endfor
  endfor
  for [l:group, l:pos] in items(l:by_group)
    " Vim 8.2's help limits a call to 8 positions
    let l:i = 0
    while l:i < len(l:pos)
      call add(w:webmarks_match_ids, matchaddpos(l:group, l:pos[l:i : l:i + 7], 10))
      let l:i += 8
    endwhile
  endfor
endfunction

" Record where every window of {buf} is, by item rather than line.
function! s:capture(buf) abort
  let s:captured = {}
  for l:winid in s:windows(a:buf)
    call win_execute(l:winid, 'call s:capture_current()')
  endfor
  return s:captured
endfunction

function! s:capture_current() abort
  let l:view = winsaveview()
  let l:row = get(b:webmarks.rows, l:view.lnum - 1, {})
  let s:captured[win_getid()] = {'lnum': l:view.lnum, 'col': l:view.col,
        \ 'leftcol': l:view.leftcol,
        \ 'kind': get(l:row, 'kind', ''), 'id': get(l:row, 'id', '')}
endfunction

function! s:restore_current() abort
  call s:apply_window_options()
  let l:saved = get(s:captured, win_getid(), {})
  if !empty(l:saved)
    let l:lnum = s:find_row(l:saved.kind, l:saved.id)
    if l:lnum < 1
      let l:lnum = min([l:saved.lnum, line('$')])
    endif
    call cursor(l:lnum, l:saved.col + 1)
    " only leftcol: a full winrestview() would undo the cursor move
    call winrestview({'leftcol': l:saved.leftcol})
  endif
  call s:apply_matches()
endfunction

function! s:find_row(kind, id) abort
  if a:id ==# ''
    return 0
  endif
  let l:i = 0
  for l:row in b:webmarks.rows
    let l:i += 1
    if l:row.kind ==# a:kind && l:row.id ==# a:id
      return l:i
    endif
  endfor
  return 0
endfunction

" --- rendering -------------------------------------------------------------

" Write rows into {buf}. Lines are overwritten in place (not deleted and
" re-added) so closed folds survive the redraw.
function! s:render_buffer(buf) abort
  let l:state = getbufvar(a:buf, 'webmarks')
  let l:rows = webmarks#app#listing#rows(webmarks#app#store#current(), l:state.policy,
        \ l:state.view, webmarks#compat#clock#now(), webmarks#app#title#pending_ids())
  " foldexpr reads the rows: update them before the lines
  let l:state.rows = l:rows
  let l:texts = map(copy(l:rows), 'v:val.text')
  call setbufvar(a:buf, '&modifiable', 1)
  call setbufline(a:buf, 1, l:texts)
  " (not getbufinfo().linecount: Vim 8.2.0019+)
  if len(getbufline(a:buf, 1, '$')) > len(l:texts)
    silent call deletebufline(a:buf, len(l:texts) + 1, '$')
  endif
  call setbufvar(a:buf, '&modifiable', 0)
  call setbufvar(a:buf, '&modified', 0)
endfunction

function! s:render_all(buf) abort
  let l:captured = s:capture(a:buf)
  call s:render_buffer(a:buf)
  let s:captured = l:captured
  for l:winid in s:windows(a:buf)
    call win_execute(l:winid, 'call s:restore_current()')
  endfor
endfunction

" Redraw the tree. In edit mode nothing is overwritten: it is marked
" dirty and redrawn when edit mode ends.
function! webmarks#ui#tree#render() abort
  let l:buf = webmarks#ui#tree#bufnr()
  if l:buf < 0 || empty(getbufvar(l:buf, 'webmarks'))
    return
  endif
  let l:state = getbufvar(l:buf, 'webmarks')
  if l:state.mode ==# 'edit'
    let l:state.edit.dirty = 1
    return
  endif
  call s:render_all(l:buf)
endfunction

" Something changed outside the tree (a title fetch finished, a command
" added a bookmark, fzf opened one). event: {id, changed, warning}.
function! webmarks#ui#tree#on_changed(...) abort
  let l:event = get(a:000, 0, {})
  if type(l:event) == v:t_dict && get(l:event, 'warning', '') !=# ''
    call webmarks#compat#notify#warn(l:event.warning)
  endif
  call s:changed(0)
endfunction

" Defer while a redraw could disturb the user. state() is not used for
" this: it always contains 'c' inside a timer or job callback (measured),
" so a check on it would never let the deferred redraw run.
function! s:busy() abort
  " Ex mode (vim -e, gQ) is a command line too, but it never ends while a
  " script runs; redraw there
  if mode(1) =~# '^c[ve]'
    return 0
  endif
  if getcmdtype() !=# '' || mode(1) =~# '^c'
    return 2
  endif
  if mode(1) !~# '^n' || (exists('*state') && state('m') !=# '')
    return 1
  endif
  return 0
endfunction

" (a timer passes its id as an extra argument)
function! s:changed(tries, ...) abort
  let l:buf = webmarks#ui#tree#bufnr()
  if l:buf < 0 || empty(s:windows(l:buf)) || empty(getbufvar(l:buf, 'webmarks'))
    return
  endif
  let l:state = getbufvar(l:buf, 'webmarks')
  if l:state.mode ==# 'edit'
    let l:state.edit.dirty = 1
    return
  endif
  let l:busy = s:busy()
  " the command line (an input() prompt): wait as long as it takes;
  " Insert/Visual/pending operator: give up waiting after ~3 s
  if l:busy == 2 || (l:busy == 1 && a:tries < 60)
    call timer_start(a:tries == 0 ? 0 : 50, function('s:changed', [a:tries + 1]))
    return
  endif
  call s:render_all(l:buf)
endfunction

" Put the cursor of every tree window on {id} (no window change).
function! webmarks#ui#tree#focus(kind, id) abort
  let l:buf = webmarks#ui#tree#bufnr()
  if l:buf < 0
    return
  endif
  let s:focus = [a:kind, a:id]
  for l:winid in s:windows(l:buf)
    call win_execute(l:winid, 'call s:focus_current()')
  endfor
endfunction

function! s:focus_current() abort
  let l:lnum = s:find_row(s:focus[0], s:focus[1])
  if l:lnum > 0
    call cursor(l:lnum, 1)
    silent! normal! zv
  endif
endfunction

" --- open / close ------------------------------------------------------------

" Is a tree window open in the current tab page?
function! webmarks#ui#tree#is_open() abort
  let l:buf = webmarks#ui#tree#bufnr()
  return l:buf > 0 && bufwinid(l:buf) > 0
endfunction

" open() -> Result
function! webmarks#ui#tree#open() abort
  let l:buf = webmarks#ui#tree#bufnr()
  let l:state = l:buf > 0 ? getbufvar(l:buf, 'webmarks', {}) : {}
  let l:editing = !empty(l:state) && l:state.mode ==# 'edit'
  if !l:editing
    let l:r = webmarks#app#store#reload()
    if !l:r.ok
      call webmarks#compat#notify#error(l:r.error)
      return l:r
    endif
    for l:w in l:r.warnings
      call webmarks#compat#notify#warn(l:w)
    endfor
  endif
  let l:buf = s:ensure_buffer()
  let l:wins = s:windows(l:buf)
  if !empty(l:wins)
    call win_gotoid(l:wins[0])
  else
    let l:how = webmarks#ui#tree#option('open')
    try
      if l:how ==# 'vsplit'
        execute 'silent vertical topleft sbuffer' l:buf
        execute 'vertical resize' webmarks#ui#tree#option('width')
      elseif l:how ==# 'split'
        execute 'silent topleft sbuffer' l:buf
      elseif l:how ==# 'tab'
        execute 'silent tab sbuffer' l:buf
      else
        execute 'silent buffer' l:buf
      endif
    catch /^Vim\%((\a\+)\)\=:E/
      " e.g. E37 with g:webmarks_open = 'edit' and a modified buffer
      let l:msg = substitute(v:exception, '^Vim\%((\a\+)\)\=:', '', '')
      call webmarks#compat#notify#error(l:msg)
      return {'ok': v:false, 'code': 'open_failed', 'error': l:msg, 'changed': v:false}
    endtry
  endif
  if !exists('b:webmarks')
    call s:init_buffer()
  endif
  call s:apply_window_options()
  if b:webmarks.mode ==# 'edit'
    if &modified
      call webmarks#compat#notify#warn(s:edit_msg)
      return s:ok()
    endif
    " left with :x / :update and nothing changed: back to view mode
    call webmarks#ui#tree#leave_edit()
    return s:ok()
  endif
  call webmarks#ui#tree#render()
  return s:ok()
endfunction

function! s:ok() abort
  return {'ok': v:true, 'code': '', 'error': '', 'changed': v:false}
endfunction

" Close the tree window in the current tab page (the current window if
" it shows the tree).
function! webmarks#ui#tree#close() abort
  let l:buf = webmarks#ui#tree#bufnr()
  if l:buf < 0
    return
  endif
  let l:winid = bufnr('%') == l:buf ? win_getid() : bufwinid(l:buf)
  if l:winid <= 0
    return
  endif
  call win_gotoid(l:winid)
  let l:how = webmarks#ui#tree#option('open')
  if l:how ==# 'edit'
    let l:alt = bufnr('#')
    if l:alt > 0 && buflisted(l:alt) && l:alt != bufnr('%')
      buffer #
    else
      enew
    endif
  elseif winnr('$') == 1
    if tabpagenr('$') == 1
      enew
    else
      tabclose
    endif
  else
    close
  endif
endfunction

" --- buffer events -----------------------------------------------------------

function! webmarks#ui#tree#on_buf_win_enter() abort
  if !exists('b:webmarks')
    return
  endif
  call s:apply_window_options()
  if b:webmarks.mode ==# 'edit'
    call webmarks#ui#tree#_edit_window_on()
  else
    call s:apply_matches()
  endif
endfunction

" Window matches outlive the buffer in a window. BufWinLeave does not fire
" while another window still shows the tree, so after any BufLeave check
" on the next tick whether this window switched to another buffer.
function! webmarks#ui#tree#on_buf_leave() abort
  let l:winid = win_getid()
  let l:buf = str2nr(expand('<abuf>'))
  call timer_start(0, function('s:check_left', [l:winid, l:buf]))
endfunction

function! s:check_left(winid, buf, ...) abort
  if win_id2win(a:winid) > 0 && winbufnr(a:winid) != a:buf
    call win_execute(a:winid, 'call s:forget_window()')
  endif
endfunction

function! s:forget_window() abort
  call s:clear_matches()
  if exists('w:webmarks_conceal_id')
    silent! call matchdelete(w:webmarks_conceal_id)
    unlet w:webmarks_conceal_id
  endif
  unlet! w:webmarks_layout
endfunction

function! webmarks#ui#tree#on_write() abort
  if expand('<amatch>') !=# bufname('%')
    call webmarks#compat#notify#warn('the tree cannot be written to another file')
    return
  endif
  if !exists('b:webmarks') || b:webmarks.mode !=# 'edit'
    setlocal nomodified
    return
  endif
  call webmarks#ui#tree#_edit_write()
endfunction

function! webmarks#ui#tree#on_read() abort
  if !exists('b:webmarks')
    return
  endif
  " :e! / :e means "show me what is on disk now"
  let l:r = webmarks#app#store#reload()
  if !l:r.ok
    call webmarks#compat#notify#error(l:r.error)
  endif
  if b:webmarks.mode ==# 'edit'
    setlocal nomodified
    call webmarks#ui#tree#leave_edit()
    return
  endif
  call webmarks#ui#tree#render()
endfunction

" --- folds -------------------------------------------------------------------

function! webmarks#ui#tree#foldexpr(lnum) abort
  let l:row = get(get(b:, 'webmarks', {'rows': []}).rows, a:lnum - 1, v:null)
  if l:row is v:null || l:row.kind ==# 'empty'
    return 0
  endif
  return l:row.kind ==# 'folder' ? '>' . l:row.depth : l:row.depth
endfunction

function! webmarks#ui#tree#foldtext() abort
  let l:row = get(get(b:, 'webmarks', {'rows': []}).rows, v:foldstart - 1, v:null)
  let l:text = l:row is v:null ? getline(v:foldstart) : l:row.text
  return l:text . ' (' . (v:foldend - v:foldstart) . ')'
endfunction

" --- actions -----------------------------------------------------------------

function! s:row() abort
  return get(b:webmarks.rows, line('.') - 1, v:null)
endfunction

function! s:report(r) abort
  if !a:r.ok && a:r.code !=# 'cancelled'
    call webmarks#compat#notify#error(a:r.error)
  endif
  return a:r.ok
endfunction

" The folder new items go to: the folder on the cursor line, the folder
" of the bookmark on it, or the root.
function! s:target_folder() abort
  let l:row = s:row()
  if l:row is v:null || l:row.kind ==# 'empty'
    return v:null
  endif
  return l:row.kind ==# 'folder' ? l:row.id : l:row.bookmark.folder_id
endfunction

function! s:need(kind) abort
  let l:row = s:row()
  if l:row is v:null || l:row.kind !=# a:kind
    call webmarks#compat#notify#warn(a:kind ==# 'bookmark' ? 'not a bookmark' : 'not a folder')
    return v:null
  endif
  return l:row
endfunction

function! webmarks#ui#tree#action(name) abort
  if !exists('b:webmarks')
    return
  endif
  if b:webmarks.mode ==# 'edit' && a:name !=# 'close'
    return
  endif
  call call('s:do_' . substitute(a:name, '-', '_', 'g'), [])
endfunction

function! s:do_open() abort
  let l:row = s:row()
  if l:row is v:null || l:row.kind ==# 'empty'
    call s:do_add()
    return
  endif
  if l:row.kind ==# 'folder'
    silent! normal! za
    return
  endif
  let l:r = webmarks#app#bookmark#launch(l:row.id, webmarks#compat#clock#now())
  if l:r.ok
    call webmarks#ui#tree#render()
  elseif get(l:r, 'launched', v:false)
    call webmarks#compat#notify#warn('opened, but could not record usage: ' . l:r.error)
  else
    call webmarks#compat#notify#error(l:r.error)
  endif
endfunction

function! s:do_add() abort
  let l:folder = s:target_folder()
  let l:url = webmarks#ui#prompt#text('URL: ', matchstr(expand('<cfile>'), '^https\?://\S\+'))
  if !s:report(l:url) || trim(l:url.value) ==# ''
    return
  endif
  let l:name = webmarks#ui#prompt#text('Name (empty = fetch title): ', '')
  if !s:report(l:name)
    return
  endif
  let l:r = webmarks#app#bookmark#add(l:url.value, l:name.value, l:folder, webmarks#compat#clock#now())
  if !l:r.ok
    if l:r.code ==# 'duplicate_url'
      call webmarks#compat#notify#warn(l:r.error)
      call webmarks#ui#tree#render()
      call webmarks#ui#tree#focus('bookmark', l:r.existing.id)
    else
      call webmarks#compat#notify#error(l:r.error)
    endif
    return
  endif
  if l:r.fetch_title
    call webmarks#app#title#request(l:r.id, l:r.bookmark.url, 0, webmarks#ui#tree#option('fetch_title'))
  endif
  call webmarks#ui#tree#render()
  call webmarks#ui#tree#focus('bookmark', l:r.id)
endfunction

function! s:do_add_folder() abort
  let l:parent = s:target_folder()
  let l:name = webmarks#ui#prompt#text('Folder name: ', '')
  if !s:report(l:name)
    return
  endif
  let l:r = webmarks#app#folder#add(l:name.value, l:parent)
  if s:report(l:r)
    call webmarks#ui#tree#render()
    call webmarks#ui#tree#focus('folder', l:r.id)
  endif
endfunction

function! s:do_rename() abort
  let l:row = s:row()
  if l:row is v:null || l:row.kind ==# 'empty'
    call webmarks#compat#notify#warn('not a bookmark or folder')
    return
  endif
  let l:current = l:row.kind ==# 'folder' ? l:row.folder.name : l:row.bookmark.display_name
  let l:name = webmarks#ui#prompt#text('Name: ', l:current)
  if !s:report(l:name)
    return
  endif
  let l:r = l:row.kind ==# 'folder'
        \ ? webmarks#app#folder#rename(l:row.id, l:name.value)
        \ : webmarks#app#bookmark#rename(l:row.id, l:name.value)
  if s:report(l:r)
    call webmarks#ui#tree#render()
  endif
endfunction

function! s:do_edit_url() abort
  let l:row = s:need('bookmark')
  if l:row is v:null
    return
  endif
  let l:url = webmarks#ui#prompt#text('URL: ', l:row.bookmark.url)
  if !s:report(l:url) || trim(l:url.value) ==# ''
    return
  endif
  let l:r = webmarks#app#bookmark#change_url(l:row.id, l:url.value)
  if !l:r.ok
    call webmarks#compat#notify#error(l:r.error)
    return
  endif
  if l:r.fetch_title
    call webmarks#app#title#request(l:row.id, l:r.bookmark.url, 0, webmarks#ui#tree#option('fetch_title'))
  endif
  call webmarks#ui#tree#render()
endfunction

function! s:do_move() abort
  let l:row = s:row()
  if l:row is v:null || l:row.kind ==# 'empty'
    call webmarks#compat#notify#warn('not a bookmark or folder')
    return
  endif
  let l:data = webmarks#app#store#current()
  let l:to = webmarks#ui#prompt#choose_folder(l:data, l:row.kind ==# 'folder' ? l:row.id : v:null)
  if !s:report(l:to)
    return
  endif
  let l:r = l:row.kind ==# 'folder'
        \ ? webmarks#app#folder#move(l:row.id, l:to.value)
        \ : webmarks#app#bookmark#move(l:row.id, l:to.value)
  if s:report(l:r)
    call webmarks#ui#tree#render()
  endif
endfunction

function! s:do_delete() abort
  let l:row = s:row()
  if l:row is v:null || l:row.kind ==# 'empty'
    call webmarks#compat#notify#warn('not a bookmark or folder')
    return
  endif
  let l:name = l:row.kind ==# 'folder' ? l:row.folder.name : l:row.bookmark.display_name
  if !webmarks#ui#prompt#confirm(printf('Delete "%s"?', l:name))
    return
  endif
  let l:r = l:row.kind ==# 'folder'
        \ ? webmarks#app#folder#remove(l:row.id)
        \ : webmarks#app#bookmark#remove(l:row.id)
  if s:report(l:r)
    call webmarks#ui#tree#render()
  endif
endfunction

function! s:do_favorite() abort
  let l:row = s:need('bookmark')
  if l:row isnot v:null && s:report(webmarks#app#bookmark#toggle_favorite(l:row.id))
    call webmarks#ui#tree#render()
  endif
endfunction

function! s:do_refetch() abort
  let l:row = s:need('bookmark')
  if l:row is v:null
    return
  endif
  let l:r = webmarks#app#title#request(l:row.id, l:row.bookmark.url, 1, 1)
  if !l:r.ok
    call webmarks#compat#notify#warn(l:r.error)
    return
  endif
  call webmarks#ui#tree#render()
endfunction

function! s:do_yank() abort
  let l:row = s:need('bookmark')
  if l:row is v:null
    return
  endif
  call setreg('"', l:row.bookmark.url)
  if has('clipboard')
    silent! call setreg('+', l:row.bookmark.url)
  endif
  echo 'yanked: ' . l:row.bookmark.url
endfunction

function! s:set_policy(key, value) abort
  let b:webmarks.policy[a:key] = a:value
  call webmarks#ui#tree#render()
  call s:echo_status()
endfunction

function! s:echo_status() abort
  echo printf('sort: %s%s, view: %s', b:webmarks.policy.criterion,
        \ b:webmarks.policy.favorite_first ? ', favorites first' : '', b:webmarks.view)
endfunction

function! s:do_sort_recent() abort
  call s:set_policy('criterion', 'recent')
endfunction

function! s:do_sort_name() abort
  call s:set_policy('criterion', 'name')
endfunction

function! s:do_sort_frecency() abort
  call s:set_policy('criterion', 'frecency')
endfunction

function! s:do_toggle_favorite_first() abort
  call s:set_policy('favorite_first', b:webmarks.policy.favorite_first ? v:false : v:true)
endfunction

function! s:do_toggle_view() abort
  let b:webmarks.view = b:webmarks.view ==# 'tree' ? 'flat' : 'tree'
  call webmarks#ui#tree#render()
  call s:echo_status()
endfunction

function! s:do_reload() abort
  let l:r = webmarks#app#store#reload()
  if !s:report(l:r)
    return
  endif
  for l:w in l:r.warnings
    call webmarks#compat#notify#warn(l:w)
  endfor
  call webmarks#ui#tree#render()
endfunction

function! s:do_close() abort
  if b:webmarks.mode ==# 'edit'
    if &modified
      call webmarks#compat#notify#warn(s:edit_msg)
    else
      call webmarks#ui#tree#leave_edit()
    endif
    return
  endif
  call webmarks#ui#tree#close()
endfunction

function! s:do_edit() abort
  call webmarks#ui#tree#enter_edit()
endfunction

function! s:do_help() abort
  let l:lines = []
  for [l:action, l:_] in s:actions
    let l:keys = []
    for l:k in b:webmarks.mapped_keys
      if maparg(l:k, 'n') ==# '<Plug>(webmarks-' . l:action . ')'
        call add(l:keys, l:k)
      endif
    endfor
    call add(l:lines, printf('%-6s %s', empty(l:keys) ? '-' : join(l:keys, ' '), l:action))
  endfor
  echo join(l:lines, "\n")
endfunction

" --- edit mode -----------------------------------------------------------------


function! webmarks#ui#tree#enter_edit() abort
  if !exists('b:webmarks')
    return
  endif
  if b:webmarks.view !=# 'tree'
    call webmarks#compat#notify#warn('edit mode is available in tree view only')
    return
  endif
  if b:webmarks.mode ==# 'edit'
    return
  endif
  let l:r = webmarks#app#store#reload()
  if !l:r.ok
    call webmarks#compat#notify#error(l:r.error)
    return
  endif
  let l:buf = bufnr('%')
  call s:render_buffer(l:buf)
  let l:edit = webmarks#app#listing#edit_lines(webmarks#app#store#current(), b:webmarks.policy,
        \ webmarks#compat#clock#now())
  let b:webmarks.edit = {'snapshot_ids': l:edit.ids, 'shown': l:edit.shown,
        \ 'mapped_keys': filter(copy(b:webmarks.mapped_keys), 'v:val !=# "q"'), 'dirty': 0}
  let b:webmarks.mode = 'edit'
  " still undolevels=-1 here: the view text cannot be undone into
  setlocal modifiable
  call setline(1, l:edit.lines)
  if line('$') > len(l:edit.lines)
    silent call deletebufline(l:buf, len(l:edit.lines) + 1, '$')
  endif
  setlocal undolevels< expandtab shiftwidth=2 softtabstop=2
  for l:winid in s:windows(l:buf)
    call win_execute(l:winid, 'call webmarks#ui#tree#_edit_window_on()')
  endfor
  for l:key in b:webmarks.edit.mapped_keys
    execute 'silent! nunmap <buffer>' l:key
  endfor
  " setline() sets 'modified' even for identical text
  setlocal nomodified
  echo '-- WEBMARKS EDIT -- :w to apply, :e! to discard'
endfunction

" Edit-mode window settings for the current window.
function! webmarks#ui#tree#_edit_window_on() abort
  call s:apply_window_options()
  call s:clear_matches()
  if !exists('w:webmarks_conceal_id')
    let w:webmarks_conceal_id = matchadd('Conceal', '\s\?' . "⟨" . '[bf]\d\+' . "⟩",
          \ 20, -1, {'conceal': ''})
  endif
endfunction

function! s:edit_window_off() abort
  if exists('w:webmarks_conceal_id')
    silent! call matchdelete(w:webmarks_conceal_id)
    unlet w:webmarks_conceal_id
  endif
  call s:apply_window_options()
endfunction

function! webmarks#ui#tree#leave_edit() abort
  if !exists('b:webmarks') || b:webmarks.mode !=# 'edit'
    return
  endif
  let b:webmarks.mode = 'view'
  let l:buf = bufnr('%')
  for l:winid in s:windows(l:buf)
    call win_execute(l:winid, 'call s:edit_window_off()')
  endfor
  setlocal undolevels=-1 nomodifiable expandtab< shiftwidth< softtabstop<
  " map back exactly the keys enter_edit() removed (q stayed mapped)
  for l:key in b:webmarks.edit.mapped_keys
    let l:action = s:action_of(l:key)
    if l:action !=# '' && !hasmapto('<Plug>(webmarks-' . l:action . ')', 'n')
      execute 'nmap <buffer> <nowait>' l:key '<Plug>(webmarks-' . l:action . ')'
    endif
  endfor
  let b:webmarks.edit.dirty = 0
  call webmarks#ui#tree#render()
  setlocal nomodified
endfunction

" :w in edit mode
function! webmarks#ui#tree#_edit_write() abort
  let l:p = webmarks#app#edit#parse(getline(1, '$'), b:webmarks.edit.snapshot_ids)
  if !l:p.ok
    call s:show_errors(l:p)
    return
  endif
  if !empty(l:p.delete_ids)
        \ && !webmarks#ui#prompt#confirm(printf('Delete %d item(s)?', len(l:p.delete_ids)))
    call webmarks#compat#notify#warn('cancelled')
    return
  endif
  let l:r = webmarks#app#edit#commit(l:p.entries, l:p.delete_ids, webmarks#compat#clock#now(),
        \ get(b:webmarks.edit, 'shown', {}))
  if !l:r.ok
    call s:show_errors(l:r)
    return
  endif
  for l:w in get(l:r, 'warnings', [])
    call webmarks#compat#notify#warn(l:w)
  endfor
  setlocal nomodified
  for l:f in get(l:r, 'fetch_title', [])
    call webmarks#app#title#request(l:f.id, l:f.url, 0, webmarks#ui#tree#option('fetch_title'))
  endfor
  call webmarks#ui#tree#leave_edit()
  call webmarks#compat#notify#info(s:summary(get(l:r, 'counts', {})))
endfunction

" Errors keep the buffer modified and in edit mode (so :wq does not close).
function! s:show_errors(r) abort
  let l:errors = get(a:r, 'errors', [])
  if empty(l:errors)
    let l:errors = [{'lnum': 0, 'error': a:r.error}]
  endif
  for l:e in l:errors
    call webmarks#compat#notify#error(l:e.error)
  endfor
  for l:e in l:errors
    if l:e.lnum > 0
      call cursor(l:e.lnum, 1)
      break
    endif
  endfor
endfunction

function! s:summary(counts) abort
  let l:parts = []
  for [l:key, l:label] in [['added', 'added'], ['renamed', 'renamed'], ['moved', 'moved'],
        \ ['url_changed', 'URL changed'], ['favorite_changed', 'favorite changed'], ['deleted', 'deleted']]
    if get(a:counts, l:key, 0) > 0
      call add(l:parts, a:counts[l:key] . ' ' . l:label)
    endif
  endfor
  return empty(l:parts) ? 'no changes' : 'applied: ' . join(l:parts, ', ')
endfunction

let &cpoptions = s:save_cpo
unlet s:save_cpo
