scriptencoding utf-8
let s:suite = themis#suite('app_title')
let s:assert = themis#helper('assert')

function! s:suite.before_each() abort
  let s:dir = WebmarksTestReset()
  call webmarks#app#store#_reset()
  call webmarks#app#title#_reset()
  let s:events = []
  let s:deferred = []
  call webmarks#app#title#add_listener(function('s:listener'))
  call webmarks#app#bookmark#add('https://a.example', '', v:null, 1)
endfunction

function! s:suite.after_each() abort
  call delete(s:dir, 'rf')
endfunction

function! s:listener(event) abort
  call add(s:events, a:event)
endfunction

function! s:get(id) abort
  return webmarks#app#store#find_bookmark(webmarks#app#store#current(), a:id)
endfunction

" A fetcher that answers later: results are delivered by s:deliver().
function! s:deferring(url, ctx) abort
  call add(s:deferred, a:ctx)
  return v:null
endfunction

function! s:deliver(ctx, title) abort
  call webmarks#app#title#on_result({'ok': v:true, 'code': '', 'error': '', 'title': a:title}, a:ctx)
endfunction

function! s:immediate(url, ctx) abort
  return {'ok': v:true, 'title': 'Fetched ' . a:url}
endfunction

function! s:failing(url, ctx) abort
  return {'ok': v:false, 'code': 'fetch_failed', 'error': 'title not found'}
endfunction

function! s:suite.auto_disabled_does_not_request() abort
  let g:webmarks_test.title_fetcher = function('s:immediate')
  let l:r = webmarks#app#title#request('b1', 'https://a.example', 0, 0)
  call s:assert.true(l:r.ok)
  call s:assert.false(l:r.requested)
  call s:assert.equals(s:get('b1').name_source, 'url')
endfunction

function! s:suite.applies_and_notifies_changed() abort
  let g:webmarks_test.title_fetcher = function('s:immediate')
  let l:r = webmarks#app#title#request('b1', 'https://a.example', 0, 1)
  call s:assert.true(l:r.requested)
  call s:assert.equals(s:get('b1').display_name, 'Fetched https://a.example')
  call s:assert.equals(s:events, [{'id': 'b1', 'changed': v:true, 'warning': ''}])
  call s:assert.equals(webmarks#app#title#pending_ids(), [])
endfunction

function! s:suite.stale_result_keeps_newer_pending() abort
  let g:webmarks_test.title_fetcher = function('s:deferring')
  call webmarks#app#title#request('b1', 'https://a.example', 0, 1)
  call webmarks#app#title#request('b1', 'https://a.example', 0, 1)
  call s:assert.equals(webmarks#app#title#pending_ids(), ['b1'])
  call s:deliver(s:deferred[0], 'Old')
  call s:assert.equals(webmarks#app#title#pending_ids(), ['b1'])
  call s:assert.equals(s:events, [])
  call s:assert.equals(s:get('b1').name_source, 'url')
  call s:deliver(s:deferred[1], 'New')
  call s:assert.equals(s:get('b1').display_name, 'New')
  call s:assert.equals(webmarks#app#title#pending_ids(), [])
endfunction

function! s:suite.auto_never_overwrites_manual_force_does() abort
  call webmarks#app#bookmark#rename('b1', 'Mine')
  let g:webmarks_test.title_fetcher = function('s:immediate')
  call webmarks#app#title#request('b1', 'https://a.example', 0, 1)
  call s:assert.equals(s:get('b1').display_name, 'Mine')
  call s:assert.false(s:events[-1].changed)
  call webmarks#app#title#request('b1', 'https://a.example', 1, 0)
  call s:assert.equals([s:get('b1').display_name, s:get('b1').name_source], ['Fetched https://a.example', 'fetched'])
  call s:assert.true(s:events[-1].changed)
endfunction

function! s:suite.failure_warns_only_when_forced() abort
  let g:webmarks_test.title_fetcher = function('s:failing')
  call webmarks#app#title#request('b1', 'https://a.example', 0, 1)
  call s:assert.equals(s:events[-1], {'id': 'b1', 'changed': v:false, 'warning': ''})
  call webmarks#app#title#request('b1', 'https://a.example', 1, 1)
  call s:assert.equals(s:events[-1].warning, 'title not found')
endfunction

function! s:suite.renamed_while_fetching_is_kept() abort
  let g:webmarks_test.title_fetcher = function('s:deferring')
  call webmarks#app#title#request('b1', 'https://a.example', 0, 1)
  call webmarks#app#bookmark#rename('b1', 'Typed')
  call s:deliver(s:deferred[0], 'Fetched')
  call s:assert.equals(s:get('b1').display_name, 'Typed')
endfunction

function! s:suite.listener_errors_are_contained() abort
  call webmarks#app#title#add_listener({e -> execute('throw "x"')})
  let g:webmarks_test.title_fetcher = function('s:immediate')
  call webmarks#app#title#request('b1', 'https://a.example', 0, 1)
  call s:assert.equals(len(s:events), 1)
endfunction
