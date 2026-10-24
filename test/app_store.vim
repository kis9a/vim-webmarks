scriptencoding utf-8
let s:suite = themis#suite('app_store')
let s:assert = themis#helper('assert')

function! s:suite.before_each() abort
  let s:dir = WebmarksTestReset()
  call webmarks#app#store#_reset()
  let s:calls = 0
endfunction

function! s:suite.after_each() abort
  call delete(s:dir, 'rf')
endfunction

function! s:add_folder(name, data) abort
  let s:calls += 1
  let [l:id, l:data] = webmarks#app#store#next_id(a:data, 'f')
  let l:data.folders = l:data.folders + [{'id': l:id, 'name': a:name, 'parent_id': v:null}]
  return {'ok': v:true, 'code': '', 'error': '', 'changed': v:true, 'data': l:data, 'id': l:id}
endfunction

function! s:suite.path_resolution() abort
  let g:webmarks_file = '~/x/%y#z.json'
  call s:assert.equals(webmarks#app#store#path(), expand('~') . '/x/%y#z.json')
  unlet g:webmarks_file
  let l:save = $XDG_DATA_HOME
  let $XDG_DATA_HOME = '/tmp/xdg'
  call s:assert.equals(webmarks#app#store#path(), '/tmp/xdg/webmarks/bookmarks.json')
  let $XDG_DATA_HOME = ''
  call s:assert.equals(webmarks#app#store#path(), expand('~') . '/.local/share/webmarks/bookmarks.json')
  let $XDG_DATA_HOME = l:save
endfunction

function! s:suite.mutate_saves_and_returns_extras() abort
  let l:r = webmarks#app#store#mutate(function('s:add_folder', ['A']))
  call s:assert.true(l:r.ok, string(l:r))
  call s:assert.equals(l:r.id, 'f1')
  call s:assert.false(has_key(l:r, 'data'))
  call s:assert.equals(webmarks#app#store#current().folders[0].name, 'A')
  call s:assert.true(filereadable(g:webmarks_file))
endfunction

function! s:suite.mutate_rereads_each_time() abort
  call webmarks#app#store#mutate(function('s:add_folder', ['A']))
  " another process writes the file
  let l:other = webmarks#storage#json#load(g:webmarks_file)
  let l:d = l:other.data
  let l:d.folders += [{'id': 'f9', 'name': 'Other', 'parent_id': v:null}]
  let l:d.next_id = 10
  call webmarks#storage#json#save(g:webmarks_file, l:d, l:other.mtime)
  let l:r = webmarks#app#store#mutate(function('s:add_folder', ['B']))
  call s:assert.equals(l:r.id, 'f10')
  call s:assert.equals(map(webmarks#app#store#current().folders, 'v:val.name'), ['A', 'Other', 'B'])
endfunction

function! s:fail(data) abort
  return {'ok': v:false, 'code': 'not_found', 'error': 'x', 'changed': v:false}
endfunction

function! s:throw(data) abort
  throw 'boom'
endfunction

function! s:nochange(data) abort
  let s:calls += 1
  return {'ok': v:true, 'code': '', 'error': '', 'changed': v:false}
endfunction

function! s:suite.no_save_on_failure_exception_or_no_change() abort
  call s:assert.equals(webmarks#app#store#mutate(function('s:fail')).code, 'not_found')
  let l:r = webmarks#app#store#mutate(function('s:throw'))
  call s:assert.equals(l:r.code, 'internal_error')
  call s:assert.match(l:r.error, 'boom')
  let l:r = webmarks#app#store#mutate(function('s:nochange'))
  call s:assert.true(l:r.ok)
  call s:assert.false(l:r.changed)
  call s:assert.false(filereadable(g:webmarks_file))
endfunction

" Fn that simulates another writer racing us between load and save
function! s:racing(times, data) abort
  let s:calls += 1
  if s:calls <= a:times
    let l:cur = webmarks#storage#json#load(g:webmarks_file)
    let l:d = l:cur.data
    let l:d.next_id += 1
    " bump the mtime so the lock sees a change
    call webmarks#storage#json#save(g:webmarks_file, l:d, l:cur.mtime)
    call system('touch -t ' . strftime('%Y%m%d%H%M.%S', getftime(g:webmarks_file) + s:calls * 10)
          \ . ' ' . shellescape(g:webmarks_file))
  endif
  return s:add_folder('R', a:data)
endfunction

function! s:suite.conflict_is_retried_once() abort
  call webmarks#storage#json#save(g:webmarks_file, webmarks#storage#json#empty(), -1)
  let s:calls = 0
  let l:r = webmarks#app#store#mutate(function('s:racing', [1]))
  call s:assert.true(l:r.ok, string(l:r))
  " add_folder counted too: racing x2 + add_folder x2
  call s:assert.equals(s:calls, 4)
  let s:calls = 0
  let l:r2 = webmarks#app#store#mutate(function('s:racing', [4]))
  call s:assert.equals(l:r2.code, 'conflict')
endfunction

function! s:suite.load_failure_keeps_memory_and_file() abort
  call webmarks#app#store#mutate(function('s:add_folder', ['A']))
  call writefile(['broken'], g:webmarks_file)
  let l:r = webmarks#app#store#reload()
  call s:assert.equals(l:r.code, 'load_failed')
  call s:assert.equals(webmarks#app#store#current().folders[0].name, 'A')
  call s:assert.equals(webmarks#app#store#mutate(function('s:add_folder', ['B'])).code, 'load_failed')
  call s:assert.equals(readfile(g:webmarks_file), ['broken'])
endfunction

function! s:suite.current_on_broken_file_is_empty() abort
  call writefile(['broken'], g:webmarks_file)
  call s:assert.equals(webmarks#app#store#current(), webmarks#storage#json#empty())
endfunction

function! s:suite.reload_reports_warnings() abort
  let l:d = webmarks#storage#json#empty()
  let l:d.next_id = 1
  let l:d.folders = [{'id': 'f3', 'name': 'x', 'parent_id': v:null}]
  call webmarks#storage#json#save(g:webmarks_file, l:d, -1)
  let l:r = webmarks#app#store#reload()
  call s:assert.true(l:r.ok)
  call s:assert.equals(len(l:r.warnings), 1)
endfunction

function! s:suite.next_id_shared_counter() abort
  let l:d = webmarks#storage#json#empty()
  let [l:a, l:d] = webmarks#app#store#next_id(l:d, 'b')
  let [l:b, l:d] = webmarks#app#store#next_id(l:d, 'f')
  call s:assert.equals([l:a, l:b, l:d.next_id], ['b1', 'f2', 3])
endfunction

function! s:not_a_result(data) abort
  return 'oops'
endfunction

function! s:no_data(data) abort
  return {'ok': v:true, 'code': '', 'error': '', 'changed': v:true}
endfunction

function! s:suite.a_broken_change_function_is_internal_error() abort
  call s:assert.equals(webmarks#app#store#mutate(function('s:not_a_result')).code, 'internal_error')
  call s:assert.equals(webmarks#app#store#mutate(function('s:no_data')).code, 'internal_error')
endfunction
