scriptencoding utf-8
let s:suite = themis#suite('app_bookmark')
let s:assert = themis#helper('assert')

function! s:suite.before_each() abort
  let s:dir = WebmarksTestReset()
  call webmarks#app#store#_reset()
  let s:argvs = []
  let s:exit = 0
  let s:hook = v:null
  let g:webmarks_test.cmd_runner = function('s:runner')
  let g:webmarks_browser_cmd = ['fake-browser']
endfunction

function! s:suite.after_each() abort
  call setfperm(s:dir, 'rwx------')
  call delete(s:dir, 'rf')
endfunction

function! s:runner(argv, opts) abort
  call add(s:argvs, a:argv)
  if s:hook isnot v:null
    call call(s:hook, [])
  endif
  return {'exit_code': s:exit, 'stdout': ''}
endfunction

function! s:add(url, ...) abort
  let l:r = webmarks#app#bookmark#add(a:url, get(a:000, 0, ''), get(a:000, 1, v:null), 1000)
  call s:assert.true(l:r.ok, string(l:r))
  return l:r
endfunction

function! s:get(id) abort
  return webmarks#app#store#find_bookmark(webmarks#app#store#current(), a:id)
endfunction

" Write the file as another process would.
function! s:external(Fn) abort
  let l:cur = webmarks#storage#json#load(g:webmarks_file)
  call webmarks#storage#json#save(g:webmarks_file, call(a:Fn, [l:cur.data]), l:cur.mtime)
endfunction

function! s:set_first(fields, data) abort
  call extend(a:data.bookmarks[0], a:fields)
  return a:data
endfunction

function! s:set_ranks(first, second, data) abort
  let a:data.bookmarks[0].usage = {'rank': a:first, 'open_count': 1, 'last_launch_at': 1}
  let a:data.bookmarks[1].usage = {'rank': a:second, 'open_count': 1, 'last_launch_at': 1}
  return a:data
endfunction

function! s:suite.add_ok() abort
  let l:r = s:add('https://a.example')
  call s:assert.equals(l:r.id, 'b1')
  call s:assert.true(l:r.fetch_title)
  let l:r2 = s:add('https://b.example', 'Named')
  call s:assert.false(l:r2.fetch_title)
  call s:assert.equals(s:get('b2').display_name, 'Named')
endfunction

function! s:suite.add_failures() abort
  call webmarks#app#folder#add('Dev', v:null)
  call s:add('https://a.example', 'A', 'f1')
  call s:assert.equals(webmarks#app#bookmark#add('ftp://x', '', v:null, 1).code, 'invalid_url')
  call s:assert.equals(webmarks#app#bookmark#add('https://n.example', "\xff", v:null, 1).code, 'invalid_text')
  call s:assert.equals(webmarks#app#bookmark#add('https://n.example', "​", v:null, 1).code, 'empty_name')
  call s:assert.equals(webmarks#app#bookmark#add('https://n.example', '', 'f7', 1).code, 'not_found')
  let l:dup = webmarks#app#bookmark#add('  https://a.example ', '', v:null, 1)
  call s:assert.equals(l:dup.code, 'duplicate_url')
  call s:assert.equals(l:dup.existing, {'id': 'b2', 'display_name': 'A', 'folder_path': 'Dev'})
  call s:assert.match(l:dup.error, 'already registered: A (Dev)')
  call s:assert.equals(len(webmarks#app#store#current().bookmarks), 1)
endfunction

function! s:suite.rename_change_url_move_remove_favorite() abort
  call s:add('https://a.example')
  call s:add('https://b.example', 'B')
  call webmarks#app#folder#add('Dev', v:null)
  call s:assert.equals(webmarks#app#bookmark#rename('b1', 'A').bookmark.name_source, 'manual')
  call s:assert.equals(webmarks#app#bookmark#rename('b9', 'A').code, 'not_found')
  call s:assert.equals(webmarks#app#bookmark#change_url('b1', 'https://b.example').code, 'duplicate_url')
  " same URL for itself is fine (no change)
  call s:assert.true(webmarks#app#bookmark#change_url('b2', 'https://b.example').ok)
  call s:assert.equals(webmarks#app#bookmark#change_url('b1', 'nope').code, 'invalid_url')
  let l:c = webmarks#app#bookmark#change_url('b1', 'https://c.example')
  call s:assert.false(l:c.fetch_title)
  call s:assert.equals(webmarks#app#bookmark#move('b1', 'f3').bookmark.folder_id, 'f3')
  call s:assert.equals(webmarks#app#bookmark#move('b1', 'f9').code, 'not_found')
  call s:assert.equals(webmarks#app#bookmark#move('b1', v:null).bookmark.folder_id, v:null)
  call s:assert.true(webmarks#app#bookmark#toggle_favorite('b1').bookmark.is_favorite)
  call s:assert.equals(webmarks#app#bookmark#remove('b1').removed.id, 'b1')
  call s:assert.equals(webmarks#app#bookmark#remove('b1').code, 'not_found')
  call s:assert.equals(s:get('b1'), v:null)
endfunction

function! s:suite.change_url_of_provisional_requests_fetch() abort
  call s:add('https://a.example')
  let l:r = webmarks#app#bookmark#change_url('b1', 'https://z.example')
  call s:assert.true(l:r.fetch_title)
  call s:assert.equals(l:r.bookmark.display_name, 'https://z.example')
endfunction

function! s:suite.launch_records_usage() abort
  call s:add('https://a.example')
  let l:r = webmarks#app#bookmark#launch('b1', 5000)
  call s:assert.true(l:r.ok, string(l:r))
  call s:assert.true(l:r.launched)
  call s:assert.true(l:r.recorded)
  call s:assert.equals(s:argvs, [['fake-browser', 'https://a.example']])
  call s:assert.equals(s:get('b1').usage, {'rank': 1.0, 'open_count': 1, 'last_launch_at': 5000})
endfunction

function! s:suite.launch_rereads_before_opening() abort
  call s:add('https://a.example')
  call webmarks#app#store#current()
  call s:external(function('s:set_first', [{'url': 'https://moved.example'}]))
  call webmarks#app#bookmark#launch('b1', 5000)
  call s:assert.equals(s:argvs[0][-1], 'https://moved.example')
endfunction

function! s:suite.launch_browser_failure_records_nothing() abort
  call s:add('https://a.example')
  let s:exit = 1
  let l:r = webmarks#app#bookmark#launch('b1', 5000)
  call s:assert.equals(l:r.code, 'browser_failed')
  call s:assert.false(l:r.launched)
  call s:assert.equals(s:get('b1').usage.open_count, 0)
  unlet g:webmarks_test.cmd_runner
  let g:webmarks_browser_cmd = ['webmarks-no-such-browser']
  call s:assert.equals(webmarks#app#bookmark#launch('b1', 5000).code, 'not_executable')
  call s:assert.equals(webmarks#app#bookmark#launch('b9', 5000).code, 'not_found')
endfunction

function! s:change_url_externally() abort
  call s:external(function('s:set_first', [{'url': 'https://other.example', 'display_name': 'https://other.example'}]))
endfunction

function! s:suite.launch_url_changed_meanwhile_is_not_recorded() abort
  call s:add('https://a.example')
  let s:hook = function('s:change_url_externally')
  let l:r = webmarks#app#bookmark#launch('b1', 5000)
  call s:assert.true(l:r.ok)
  call s:assert.true(l:r.launched)
  call s:assert.false(l:r.recorded)
  call s:assert.equals(s:get('b1').usage.open_count, 0)
endfunction

function! s:lock_dir() abort
  call setfperm(s:dir, 'r-x------')
endfunction

function! s:suite.launch_save_failure_reports_launched() abort
  call s:add('https://a.example')
  let s:hook = function('s:lock_dir')
  let l:r = webmarks#app#bookmark#launch('b1', 5000)
  call setfperm(s:dir, 'rwx------')
  call s:assert.false(l:r.ok)
  call s:assert.equals(l:r.code, 'save_failed')
  call s:assert.true(l:r.launched)
endfunction

function! s:suite.launch_ages_when_total_exceeds_9000() abort
  call s:add('https://a.example')
  call s:add('https://b.example')
  call s:external(function('s:set_ranks', [9000.0, 1.0]))
  call webmarks#app#bookmark#launch('b2', 5000)
  call s:assert.equals(s:get('b1').usage.rank, 9000.0 * 0.99)
  call s:assert.equals(s:get('b2').usage.rank, 2.0 * 0.99)
  " exactly 9000 before the launch: no aging
  call s:external(function('s:set_ranks', [8999.0, 1.0]))
  call webmarks#app#bookmark#launch('b2', 5000)
  call s:assert.equals(s:get('b2').usage.rank, 2.0)
endfunction

function! s:yes() abort
  return 1
endfunction

function! s:no() abort
  return 0
endfunction

function! s:suite.apply_title_conditions() abort
  call s:add('https://a.example')
  " (a) missing bookmark
  call s:assert.false(webmarks#app#bookmark#apply_title('b9', 'https://a.example', function('s:yes'), 'T').changed)
  " (b) URL differs
  call s:assert.false(webmarks#app#bookmark#apply_title('b1', 'https://x.example', function('s:yes'), 'T').changed)
  " (c) stale request
  call s:assert.false(webmarks#app#bookmark#apply_title('b1', 'https://a.example', function('s:no'), 'T').changed)
  call s:assert.equals(s:get('b1').name_source, 'url')
  " (d) manual name
  call webmarks#app#bookmark#rename('b1', 'Mine')
  call s:assert.false(webmarks#app#bookmark#apply_title('b1', 'https://a.example', function('s:yes'), 'T').changed)
  call s:assert.equals(s:get('b1').display_name, 'Mine')
  call webmarks#app#bookmark#change_url('b1', 'https://a2.example')
  call s:add('https://c.example')
  let l:r = webmarks#app#bookmark#apply_title('b2', 'https://c.example', function('s:yes'), ' Title ')
  call s:assert.true(l:r.changed)
  call s:assert.equals([s:get('b2').display_name, s:get('b2').name_source], ['Title', 'fetched'])
endfunction

function! s:suite.force_title() abort
  call s:add('https://a.example', 'Mine')
  call s:assert.equals(webmarks#app#bookmark#force_title('b1', 'https://a.example', 'T').bookmark.display_name, 'T')
  call s:assert.false(webmarks#app#bookmark#force_title('b1', 'https://x.example', 'U').changed)
  call s:assert.equals(webmarks#app#bookmark#force_title('b9', 'https://a.example', 'T').code, 'not_found')
endfunction
