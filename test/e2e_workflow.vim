scriptencoding utf-8
" test/e2e_workflow.vim - the whole path with only the outside world faked:
" :WebmarksAdd -> file -> :Webmarks -> <CR> -> usage -> wipe -> reload

let s:suite = themis#suite('e2e_workflow')
let s:assert = themis#helper('assert')

function! s:suite.before_each() abort
  let s:dir = WebmarksTestReset()
  call webmarks#app#store#_reset()
  call webmarks#app#title#_reset()
  unlet! g:loaded_webmarks
  runtime plugin/webmarks.vim
  let s:opened = []
  let g:webmarks_browser_cmd = ['fake-browser', '--new-tab']
  let g:webmarks_test.cmd_runner = function('s:runner')
  let g:webmarks_test.title_fetcher = function('WebmarksTestTitle', ['Example Domain'])
endfunction

function! s:suite.after_each() abort
  silent! only!
  let l:buf = webmarks#ui#tree#bufnr()
  if l:buf > 0
    execute 'silent! bwipeout!' l:buf
  endif
  call delete(s:dir, 'rf')
endfunction

function! s:runner(argv, opts) abort
  call add(s:opened, a:argv)
  return {'exit_code': 0, 'stdout': ''}
endfunction

function! s:suite.add_open_launch_reload() abort
  WebmarksAdd https://example.com/
  " one bookmark line in the file, title applied
  let l:file = readfile(g:webmarks_file)
  call s:assert.equals(len(filter(copy(l:file), 'v:val =~# ''"id": "b1"''')), 1)
  call s:assert.match(join(l:file), '"display_name": "Example Domain", "name_source": "fetched"')
  Webmarks
  call s:assert.equals(getline(1, '$'), ['  Example Domain'])
  let g:webmarks_test.now = 1700000500
  execute "normal \<CR>"
  call s:assert.equals(s:opened, [['fake-browser', '--new-tab', 'https://example.com/']])
  let l:usage = webmarks#app#store#find_bookmark(webmarks#app#store#current(), 'b1').usage
  call s:assert.equals(l:usage, {'rank': 1.0, 'open_count': 1, 'last_launch_at': 1700000500})
  let l:saved = readfile(g:webmarks_file)
  " forget everything in memory and read the file again
  let l:buf = webmarks#ui#tree#bufnr()
  execute 'bwipeout!' l:buf
  call webmarks#app#store#_reset()
  call s:assert.true(webmarks#app#store#reload().ok)
  let l:b = webmarks#app#store#current().bookmarks[0]
  call s:assert.equals([l:b.url, l:b.display_name, l:b.usage], ['https://example.com/', 'Example Domain', l:usage])
  call s:assert.equals(readfile(g:webmarks_file), l:saved)
  call s:assert.equals(getfperm(g:webmarks_file), 'rw-------')
endfunction

function! s:suite.organise_with_folders_and_edit_mode() abort
  WebmarksAdd https://a.example Alpha
  WebmarksAdd https://b.example Beta
  WebmarksEdit
  call append(0, ['Work/'])
  " move both bookmarks into Work
  call setline(2, '    ' . trim(getline(2)))
  call setline(3, '    ' . trim(getline(3)))
  write
  call s:assert.equals(getline(1, '$'), ['Work/', '    Alpha', '    Beta'])
  let l:data = webmarks#app#store#current()
  call s:assert.equals(map(copy(l:data.bookmarks), 'v:val.folder_id'), ['f3', 'f3'])
  " the key-driven path agrees with the text
  call cursor(1, 1)
  execute "normal \<CR>"
  call s:assert.not_equals(foldclosed(1), -1)
endfunction
