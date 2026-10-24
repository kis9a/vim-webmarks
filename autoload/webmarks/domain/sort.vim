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

" Sort a List of RankedBookmarks in place by {policy}; returns it.
function! webmarks#domain#sort#sort(policy, ranked) abort
  return sort(a:ranked, function('webmarks#domain#sort#compare', [a:policy]))
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
