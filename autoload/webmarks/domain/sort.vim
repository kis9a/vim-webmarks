scriptencoding utf-8
" domain/sort.vim - SortPolicy, a value: {criterion, favorite_first}
"
" Compares RankedBookmarks {bookmark, score}. Pure: defaults come from
" the caller, never from g: variables.

let s:save_cpo = &cpoptions
set cpoptions&vim

let s:criteria = ['name', 'recent', 'frecency']

function! webmarks#domain#sort#criteria() abort
  return copy(s:criteria)
endfunction

function! s:cmp(x, y) abort
  return a:x ==# a:y ? 0 : a:x <# a:y ? -1 : 1
endfunction

function! s:num(x, y) abort
  return a:x == a:y ? 0 : a:x < a:y ? -1 : 1
endfunction

" compare(policy, a, b) -> -1 / 0 / 1
function! webmarks#domain#sort#compare(policy, a, b) abort
  let l:x = a:a.bookmark
  let l:y = a:b.bookmark
  if a:policy.favorite_first && l:x.is_favorite != l:y.is_favorite
    return l:x.is_favorite ? -1 : 1
  endif
  let l:c = a:policy.criterion
  if l:c ==# 'recent'
    let l:p = l:x.usage.last_launch_at
    let l:q = l:y.usage.last_launch_at
    if l:p is v:null || l:q is v:null
      if !(l:p is v:null && l:q is v:null)
        return l:p is v:null ? 1 : -1
      endif
    elseif l:p != l:q
      return l:p > l:q ? -1 : 1
    endif
  elseif l:c ==# 'frecency'
    if a:a.score != a:b.score
      return a:a.score > a:b.score ? -1 : 1
    endif
  endif
  let l:r = s:cmp(tolower(l:x.display_name), tolower(l:y.display_name))
  if l:r != 0
    return l:r
  endif
  return s:num(str2nr(l:x.id[1:]), str2nr(l:y.id[1:]))
endfunction

" The order of compare() as one string per item, so sort() can compare
" plain strings (1,000 items: ~2 ms instead of ~25 ms with a Funcref).
" "\x01" ends the name: it sorts before every character a sanitized name
" can contain, so a name sorts before its own extensions, as with <#.
function! s:key(policy, r) abort
  let l:b = a:r.bookmark
  let l:fav = a:policy.favorite_first ? (l:b.is_favorite ? '0' : '1') : '0'
  if a:policy.criterion ==# 'recent'
    let l:last = l:b.usage.last_launch_at
    let l:main = l:last is v:null ? '1' . repeat('0', 15) : printf('0%015d', 999999999999999 - l:last)
  elseif a:policy.criterion ==# 'frecency'
    let l:main = printf('%015d', 999999999999999 - a:r.score)
  else
    let l:main = ''
  endif
  return l:fav . l:main . tolower(l:b.display_name) . "\x01" . printf('%012d', str2nr(l:b.id[1:]))
endfunction

" Sort a List of RankedBookmarks by {policy} (same order as compare());
" returns a new List.
function! webmarks#domain#sort#sort(policy, ranked) abort
  let l:by_key = {}
  for l:r in a:ranked
    let l:by_key[s:key(a:policy, l:r)] = l:r
  endfor
  return map(sort(keys(l:by_key)), 'l:by_key[v:val]')
endfunction

" normalize(policy, defaults) -> a valid policy; bad fields fall back to
" {defaults} (which the caller has validated).
function! webmarks#domain#sort#normalize(policy, defaults) abort
  let l:p = type(a:policy) == v:t_dict ? a:policy : {}
  let l:c = get(l:p, 'criterion', '')
  if type(l:c) != v:t_string || index(s:criteria, l:c) < 0
    let l:c = a:defaults.criterion
  endif
  let l:f = get(l:p, 'favorite_first', v:null)
  if index([v:t_number, v:t_bool], type(l:f)) < 0
    let l:f = a:defaults.favorite_first
  endif
  return {'criterion': l:c, 'favorite_first': l:f ? v:true : v:false}
endfunction

let &cpoptions = s:save_cpo
unlet s:save_cpo
