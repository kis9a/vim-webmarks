scriptencoding utf-8
" test/ui_edit.vim - edit mode in the real tree buffer

let s:suite = themis#suite('ui_edit')
let s:assert = themis#helper('assert')

let s:L = "⟨"
let s:R = "⟩"

function! s:m(id) abort
  return ' ' . s:L . a:id . s:R
endfunction

function! s:suite.before_each() abort
  let s:dir = WebmarksTestReset()
  call webmarks#app#store#_reset()
  call webmarks#app#title#_reset()
  unlet! g:loaded_webmarks
  runtime plugin/webmarks.vim
  set hidden
  let s:confirm = 1
  let s:asked = []
  let g:webmarks_test.prompt = {'confirm': function('s:confirm')}
  let g:webmarks_test.title_fetcher = function('WebmarksTestTitle', ['Fetched'])
  call webmarks#app#bookmark#add('https://a.example', 'Alpha', v:null, 1)
  call webmarks#app#folder#add('Dev', v:null)
  call webmarks#app#bookmark#add('https://g.example', 'Guide', 'f2', 1)
  messages clear
endfunction

function! s:suite.after_each() abort
  silent! tabonly!
  silent! only!
  enew!
  let l:buf = webmarks#ui#tree#bufnr()
  if l:buf > 0
    execute 'silent! bwipeout!' l:buf
  endif
  set nohidden
  call delete(s:dir, 'rf')
endfunction

function! s:confirm(msg) abort
  call add(s:asked, a:msg)
  return s:confirm
endfunction

" Match groups of a window (getmatches({win}) is unknown to the pinned vimlint)
function! s:groups(winid) abort
  return map(call('getmatches', [a:winid]), 'v:val.group')
endfunction

" Window option of any window, also in another tab page
function! s:wopt(winid, name) abort
  let [l:tab, l:win] = win_id2tabwin(a:winid)
  return gettabwinvar(l:tab, l:win, '&' . a:name)
endfunction

function! s:edit() abort
  Webmarks
  normal i
  call s:assert.equals(b:webmarks.mode, 'edit')
endfunction

function! s:suite.enter_switches_buffer_and_window_settings() abort
  Webmarks
  split
  normal i
  call s:assert.equals(getline(1, '$'), ['  Alpha  https://a.example' . s:m('b1'), 'Dev/' . s:m('f2'),
        \ '    Guide  https://g.example' . s:m('b3')])
  call s:assert.equals([&modifiable, &modified, &undolevels, &expandtab, &shiftwidth], [1, 0, &g:undolevels, 1, 2])
  call s:assert.equals(maparg('a', 'n'), '')
  call s:assert.equals(maparg('<CR>', 'n'), '')
  call s:assert.equals(maparg('q', 'n'), '<Plug>(webmarks-close)')
  for l:winid in win_findbuf(bufnr('%'))
    call s:assert.equals(getwinvar(l:winid, '&foldmethod'), 'manual')
    call s:assert.equals(getwinvar(l:winid, '&conceallevel'), 2)
    call s:assert.equals(s:groups(l:winid), ['Conceal'])
  endfor
endfunction

function! s:suite.write_applies_and_returns_to_view() abort
  call s:edit()
  call setline(1, "★ Alpha!  https://a.example" . s:m('b1'))
  call append('$', ['    https://new.example'])
  call s:assert.true(&modified)
  write
  call s:assert.equals(b:webmarks.mode, 'view')
  call s:assert.equals([&modifiable, &modified, &undolevels, &l:foldmethod, &l:foldlevel, &l:conceallevel],
        \ [0, 0, -1, 'expr', 99, 0])
  call s:assert.equals(maparg('a', 'n'), '<Plug>(webmarks-add)')
  call s:assert.equals(getline(1, '$'), ["★ Alpha!", 'Dev/', '    Fetched', '    Guide'])
  call s:assert.match(execute('messages'), 'applied: 1 added, 1 renamed, 1 favorite changed')
endfunction

function! s:suite.errors_keep_edit_mode_and_jump() abort
  call s:edit()
  call append('$', ['oops', '      deep  https://d.example'])
  write
  call s:assert.equals(b:webmarks.mode, 'edit')
  call s:assert.true(&modified)
  call s:assert.equals(line('.'), 4)
  let l:msg = execute('messages')
  call s:assert.match(l:msg, 'line 4: URL is required')
  call s:assert.match(l:msg, 'line 5: bad indent')
endfunction

function! s:suite.wq_with_errors_keeps_the_window() abort
  call s:edit()
  call append('$', ['oops'])
  let l:wins = winnr('$')
  silent! wq
  call s:assert.equals(winnr('$'), l:wins)
  call s:assert.equals(bufname('%'), 'webmarks://tree')
endfunction

function! s:suite.reload_bang_discards() abort
  call s:edit()
  call setline(1, '  Changed  https://a.example' . s:m('b1'))
  edit!
  call s:assert.equals(b:webmarks.mode, 'view')
  call s:assert.equals(getline(1), '  Alpha')
  call s:assert.false(&modified)
  call s:assert.equals(webmarks#app#store#find_bookmark(webmarks#app#store#current(), 'b1').display_name, 'Alpha')
endfunction

function! s:suite.flat_view_cannot_edit() abort
  Webmarks
  normal T
  normal i
  call s:assert.equals(b:webmarks.mode, 'view')
  call s:assert.match(execute('messages'), 'edit mode is available in tree view only')
endfunction

function! s:suite.redraws_wait_until_edit_mode_ends() abort
  call s:edit()
  call setline(1, '  Mine  https://a.example' . s:m('b1'))
  " a change arrives from elsewhere while editing
  call webmarks#app#bookmark#add('https://other.example', 'Other', v:null, 1)
  call webmarks#ui#tree#on_changed()
  call webmarks#ui#tree#render()
  call s:assert.equals(getline(1), '  Mine  https://a.example' . s:m('b1'))
  call s:assert.equals(b:webmarks.edit.dirty, 1)
  write
  call s:assert.equals(getline(1, '$'), ['  Mine', '  Other', 'Dev/', '    Guide'])
endfunction

function! s:suite.q_warns_when_modified() abort
  call s:edit()
  call setline(1, '  x  https://a.example' . s:m('b1'))
  normal q
  call s:assert.equals(b:webmarks.mode, 'edit')
  call s:assert.match(execute('messages'), 'unsaved edits')
  setlocal nomodified
  normal q
  call s:assert.equals(b:webmarks.mode, 'view')
  call s:assert.equals(bufname('%'), 'webmarks://tree')
endfunction

function! s:suite.hidden_with_quit_and_reopened() abort
  call s:edit()
  call setline(1, '  Kept  https://a.example' . s:m('b1'))
  quit
  call s:assert.equals(winnr('$'), 1)
  Webmarks
  call s:assert.equals(b:webmarks.mode, 'edit')
  call s:assert.equals(getline(1), '  Kept  https://a.example' . s:m('b1'))
  call s:assert.match(execute('messages'), 'unsaved edits')
  call s:assert.equals(&l:conceallevel, 2)
endfunction

function! s:suite.unmodified_quit_then_open_returns_to_view() abort
  call s:edit()
  quit
  Webmarks
  call s:assert.equals(b:webmarks.mode, 'view')
  call s:assert.equals(getline(1), '  Alpha')
endfunction

function! s:suite.other_tab_window_gets_edit_settings() abort
  Webmarks
  let l:buf = bufnr('%')
  tab sbuffer webmarks://tree
  let l:other = win_getid()
  tabprevious
  call webmarks#ui#tree#focus('bookmark', 'b1')
  execute bufwinnr(l:buf) . 'wincmd w'
  normal i
  call s:assert.equals(s:wopt(l:other, 'conceallevel'), 2)
  call s:assert.equals(s:wopt(l:other, 'foldmethod'), 'manual')
  write
  call s:assert.equals(s:wopt(l:other, 'conceallevel'), 0)
  call s:assert.equals(s:wopt(l:other, 'foldmethod'), 'expr')
  call s:assert.equals(s:groups(l:other), ['WebmarksFolder'])
endfunction

function! s:suite.foldlevel_is_restored() abort
  Webmarks
  normal! zM
  normal i
  write
  call s:assert.equals(&l:foldlevel, 99)
endfunction

function! s:suite.write_to_another_file_is_ignored() abort
  call s:edit()
  call setline(1, '  x  https://a.example' . s:m('b1'))
  execute 'write' fnameescape(s:dir . '/other.txt')
  call s:assert.false(filereadable(s:dir . '/other.txt'))
  call s:assert.equals(b:webmarks.mode, 'edit')
  call s:assert.equals(webmarks#app#store#find_bookmark(webmarks#app#store#current(), 'b1').display_name, 'Alpha')
endfunction

function! s:suite.delete_asks_once_and_can_be_cancelled() abort
  call s:edit()
  call deletebufline('%', 3)
  let s:confirm = 0
  write
  call s:assert.equals(s:asked, ['Delete 1 item(s)?'])
  call s:assert.equals(b:webmarks.mode, 'edit')
  call s:assert.not_equals(webmarks#app#store#find_bookmark(webmarks#app#store#current(), 'b3'), v:null)
  let s:confirm = 1
  write
  call s:assert.equals(webmarks#app#store#find_bookmark(webmarks#app#store#current(), 'b3'), v:null)
  call s:assert.equals(getline(1, '$'), ['  Alpha', 'Dev/'])
endfunction

function! s:suite.empty_store_shows_a_hint() abort
  call webmarks#app#bookmark#remove('b1')
  call webmarks#app#bookmark#remove('b3')
  call webmarks#app#folder#remove('f2')
  call s:edit()
  call s:assert.equals(getline(1, '$'), ['# add lines here:  name  https://example.com'])
  call setline(2, '  First  https://first.example')
  write
  call s:assert.equals(getline(1, '$'), ['  First'])
endfunction

function! s:suite.webmarks_edit_command() abort
  WebmarksEdit
  call s:assert.equals(b:webmarks.mode, 'edit')
  " again: no second reload, still editing
  WebmarksEdit
  call s:assert.equals(b:webmarks.mode, 'edit')
endfunction

function! s:suite.undo_does_not_go_back_to_the_view_text() abort
  call s:edit()
  let l:lines = getline(1, '$')
  silent! undo
  call s:assert.equals(getline(1, '$'), l:lines)
endfunction

" --- review regressions ----------------------------------------------------

function! s:suite.title_arriving_while_editing_survives_write() abort
  let s:pending = []
  let g:webmarks_test.title_fetcher = function('s:defer')
  call webmarks#add('https://late.example', '', v:null)
  call s:edit()
  call webmarks#app#title#on_result({'ok': v:true, 'code': '', 'error': '', 'title': 'Late title'}, s:pending[0])
  call setline(1, '  Alpha 2  https://a.example' . s:m('b1'))
  write
  let l:b = webmarks#app#store#find_bookmark(webmarks#app#store#current(), 'b4')
  call s:assert.equals([l:b.display_name, l:b.name_source], ['Late title', 'fetched'])
  call s:assert.match(execute('messages'), 'applied: 1 renamed')
endfunction

function! s:defer(url, ctx) abort
  call add(s:pending, a:ctx)
  return v:null
endfunction

function! s:suite.q_is_still_listed_after_edit_mode() abort
  Webmarks
  let l:keys = copy(b:webmarks.mapped_keys)
  normal i
  edit!
  call s:assert.equals(b:webmarks.mapped_keys, l:keys)
  call s:assert.match(execute('normal g?'), 'q\s\+close')
  call s:assert.equals(maparg('a', 'n'), '<Plug>(webmarks-add)')
endfunction

function! s:suite.reload_bang_shows_what_is_on_disk() abort
  call s:edit()
  " another Vim adds a bookmark while we edit
  let l:cur = webmarks#storage#json#load(g:webmarks_file)
  let l:d = l:cur.data
  call add(l:d.bookmarks, extend(copy(l:d.bookmarks[0]), {'id': 'b9', 'url': 'https://z.example', 'display_name': 'Zed'}))
  let l:d.next_id = 10
  call webmarks#storage#json#save(g:webmarks_file, l:d, l:cur.mtime)
  edit!
  call s:assert.equals(getline(1, '$'), ['  Alpha', '  Zed', 'Dev/', '    Guide'])
endfunction
