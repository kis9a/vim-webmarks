scriptencoding utf-8
let s:suite = themis#suite('domain_sort')
let s:assert = themis#helper('assert')

function! s:rb(id, name, fav, last, score) abort
  return {'bookmark': {'id': a:id, 'display_name': a:name, 'is_favorite': a:fav,
        \ 'usage': {'rank': 1.0, 'open_count': 1, 'last_launch_at': a:last}}, 'score': a:score}
endfunction

function! s:list() abort
  return [
        \ s:rb('b1', 'beta', v:false, 300, 10),
        \ s:rb('b2', 'Alpha', v:false, v:null, 0),
        \ s:rb('b3', 'gamma', v:true, 100, 5),
        \ s:rb('b4', 'delta', v:false, 200, 20),
        \ ]
endfunction

function! s:ids(policy) abort
  return map(webmarks#domain#sort#sort(a:policy, s:list()), 'v:val.bookmark.id')
endfunction

function! s:suite.name() abort
  call s:assert.equals(s:ids({'criterion': 'name', 'favorite_first': v:false}), ['b2', 'b1', 'b4', 'b3'])
  call s:assert.equals(s:ids({'criterion': 'name', 'favorite_first': v:true}), ['b3', 'b2', 'b1', 'b4'])
endfunction

function! s:suite.recent_null_last() abort
  call s:assert.equals(s:ids({'criterion': 'recent', 'favorite_first': v:false}), ['b1', 'b4', 'b3', 'b2'])
  call s:assert.equals(s:ids({'criterion': 'recent', 'favorite_first': v:true}), ['b3', 'b1', 'b4', 'b2'])
endfunction

function! s:suite.frecency() abort
  call s:assert.equals(s:ids({'criterion': 'frecency', 'favorite_first': v:false}), ['b4', 'b1', 'b3', 'b2'])
  call s:assert.equals(s:ids({'criterion': 'frecency', 'favorite_first': v:true}), ['b3', 'b4', 'b1', 'b2'])
endfunction

function! s:suite.ties_name_then_id() abort
  let l:list = [s:rb('b10', 'same', v:false, v:null, 0), s:rb('b9', 'Same', v:false, v:null, 0),
        \ s:rb('b2', 'same', v:false, v:null, 0)]
  for l:c in ['name', 'recent', 'frecency']
    let l:ids = map(webmarks#domain#sort#sort({'criterion': l:c, 'favorite_first': v:true}, copy(l:list)), 'v:val.bookmark.id')
    call s:assert.equals(l:ids, ['b2', 'b9', 'b10'], l:c)
  endfor
endfunction

function! s:suite.normalize() abort
  let l:d = {'criterion': 'frecency', 'favorite_first': v:true}
  call s:assert.equals(webmarks#domain#sort#normalize({'criterion': 'name', 'favorite_first': 0}, l:d),
        \ {'criterion': 'name', 'favorite_first': v:false})
  call s:assert.equals(webmarks#domain#sort#normalize({'criterion': 'bogus', 'favorite_first': 'x'}, l:d), l:d)
  call s:assert.equals(webmarks#domain#sort#normalize(3, l:d), l:d)
endfunction
