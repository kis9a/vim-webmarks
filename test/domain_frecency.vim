scriptencoding utf-8
let s:suite = themis#suite('domain_frecency')
let s:assert = themis#helper('assert')

function! s:usage(rank, last) abort
  return {'rank': a:rank, 'open_count': 1, 'last_launch_at': a:last}
endfunction

function! s:suite.z_compatible_values() abort
  " dx = 0: 10000 * rank * 3.75 / 1.25 = 30000 * rank
  call s:assert.equals(webmarks#domain#frecency#score(s:usage(1.0, 1000), 1000), 30000)
  call s:assert.equals(webmarks#domain#frecency#score(s:usage(2.0, 1000), 1000), 60000)
  " dx = 10000 s: 3.75 / 2.25
  call s:assert.equals(webmarks#domain#frecency#score(s:usage(1.0, 0), 10000), float2nr(10000.0 * 3.75 / 2.25))
endfunction

function! s:suite.unused_is_zero() abort
  call s:assert.equals(webmarks#domain#frecency#score(s:usage(5.0, v:null), 10), 0)
endfunction

function! s:suite.future_launch_is_clamped() abort
  call s:assert.equals(webmarks#domain#frecency#score(s:usage(1.0, 2000), 1000), 30000)
endfunction

function! s:suite.total_rank() abort
  call s:assert.equals(webmarks#domain#frecency#total_rank([{'usage': s:usage(1.5, 0)}, {'usage': s:usage(2.0, 0)}]), 3.5)
endfunction

function! s:suite.age_boundary() abort
  let l:list = [{'id': 'b1', 'usage': s:usage(100.0, 0)}]
  let l:r = webmarks#domain#frecency#age(l:list, 9000.0)
  call s:assert.false(l:r.changed)
  call s:assert.equals(l:r.bookmarks[0].usage.rank, 100.0)
  let l:r2 = webmarks#domain#frecency#age(l:list, 9000.5)
  call s:assert.true(l:r2.changed)
  call s:assert.equals(l:r2.bookmarks[0].usage.rank, 99.0)
  " input untouched
  call s:assert.equals(l:list[0].usage.rank, 100.0)
endfunction
