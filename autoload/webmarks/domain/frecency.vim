scriptencoding utf-8
" domain/frecency.vim - rupa/z compatible score and aging
"
" Pure: `now` is always an argument.

let s:save_cpo = &cpoptions
set cpoptions&vim

let s:age_threshold = 9000.0
let s:age_factor = 0.99

" score(usage, now) -> Number. Unused bookmarks score 0.
function! webmarks#domain#frecency#score(usage, now) abort
  if a:usage.last_launch_at is v:null
    return 0
  endif
  let l:dx = max([0, a:now - a:usage.last_launch_at])
  return float2nr(10000.0 * a:usage.rank * (3.75 / ((0.0001 * l:dx + 1.0) + 0.25)))
endfunction

function! webmarks#domain#frecency#total_rank(bookmarks) abort
  let l:total = 0.0
  for l:b in a:bookmarks
    let l:total += l:b.usage.rank
  endfor
  return l:total
endfunction

" age(bookmarks, pre_total) -> Result {bookmarks}
" pre_total is the sum of ranks *before* this launch was added, the same
" point z.sh checks its threshold at.
function! webmarks#domain#frecency#age(bookmarks, pre_total) abort
  if a:pre_total <= s:age_threshold
    return {'ok': v:true, 'code': '', 'error': '', 'changed': v:false,
          \ 'bookmarks': deepcopy(a:bookmarks)}
  endif
  let l:out = deepcopy(a:bookmarks)
  for l:b in l:out
    let l:b.usage.rank = l:b.usage.rank * s:age_factor
  endfor
  return {'ok': v:true, 'code': '', 'error': '', 'changed': v:true, 'bookmarks': l:out}
endfunction

let &cpoptions = s:save_cpo
unlet s:save_cpo
