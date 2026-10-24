scriptencoding utf-8
" app/listing.vim - rows for the tree / flat views and fzf candidates
"
" UI independent. A Row is
"   {kind: 'folder'|'bookmark'|'empty', id, depth, text, hl, bookmark?, folder?}
" where hl = [[group, col, len], ...] (byte columns, 1-based) is ready for
" matchaddpos(); the caller adds the line number.
" Layout: indent -> star column (2 cells) -> name, the same in view and
" edit mode, so switching modes does not move the text.

let s:save_cpo = &cpoptions
set cpoptions&vim

let s:star = '★ '
let s:nostar = '  '
let s:empty_text = '[no bookmarks — press a to add]'

function! s:clean(s) abort
  " second line of defence: names are sanitized when stored
  return substitute(a:s, '[\t\n\r]', ' ', 'g')
endfunction

function! s:ranked(bookmarks, now) abort
  return map(copy(a:bookmarks), '{"bookmark": v:val, "score": webmarks#domain#frecency#score(v:val.usage, a:now)}')
endfunction

function! s:sorted(policy, bookmarks, now) abort
  return map(webmarks#domain#sort#sort(a:policy, s:ranked(a:bookmarks, a:now)), 'v:val.bookmark')
endfunction

function! s:same(a, b) abort
  return type(a:a) == type(a:b) && a:a ==# a:b
endfunction

function! s:bookmark_row(b, depth, pending) abort
  let l:indent = repeat('  ', a:depth)
  let l:name = s:clean(a:b.display_name)
  let l:text = l:indent . (a:b.is_favorite ? s:star : s:nostar) . l:name
        \ . (a:pending ? ' …' : '')
  let l:hl = []
  if a:b.is_favorite
    call add(l:hl, ['WebmarksFavorite', strlen(l:indent) + 1, strlen(s:star)])
  endif
  if a:b.name_source ==# 'url' || a:pending
    call add(l:hl, ['WebmarksPending', 1, strlen(l:text)])
  endif
  return {'kind': 'bookmark', 'id': a:b.id, 'depth': a:depth, 'text': l:text,
        \ 'hl': l:hl, 'bookmark': a:b}
endfunction

function! s:folder_row(f, depth) abort
  let l:text = repeat('  ', a:depth - 1) . s:clean(a:f.name) . '/'
  return {'kind': 'folder', 'id': a:f.id, 'depth': a:depth, 'text': l:text,
        \ 'hl': [['WebmarksFolder', 1, strlen(l:text)]], 'folder': a:f}
endfunction

function! s:empty_row() abort
  return {'kind': 'empty', 'id': '', 'depth': 0, 'text': s:empty_text,
        \ 'hl': [['WebmarksEmpty', 1, strlen(s:empty_text)]]}
endfunction

function! s:in_folder(data, folder_id) abort
  return filter(copy(a:data.bookmarks), 's:same(v:val.folder_id, a:folder_id)')
endfunction

function! s:tree_folder(rows, data, policy, now, pending, folder, depth) abort
  call add(a:rows, s:folder_row(a:folder, a:depth))
  if a:depth < 2
    for l:child in webmarks#domain#folder#children(a:data.folders, a:folder.id)
      call s:tree_folder(a:rows, a:data, a:policy, a:now, a:pending, l:child, a:depth + 1)
    endfor
  endif
  for l:b in s:sorted(a:policy, s:in_folder(a:data, a:folder.id), a:now)
    call add(a:rows, s:bookmark_row(l:b, a:depth, has_key(a:pending, l:b.id)))
  endfor
endfunction

" rows(data, policy, view, now, pending_ids) -> List of Rows
function! webmarks#app#listing#rows(data, policy, view, now, pending_ids) abort
  let l:pending = {}
  for l:id in a:pending_ids
    let l:pending[l:id] = 1
  endfor
  let l:rows = []
  if a:view ==# 'flat'
    for l:b in s:sorted(a:policy, a:data.bookmarks, a:now)
      let l:row = s:bookmark_row(l:b, 0, has_key(l:pending, l:b.id))
      let l:path = webmarks#domain#folder#path(a:data.folders, l:b.folder_id)
      if l:path !=# ''
        let l:suffix = '(' . s:clean(l:path) . ')'
        call add(l:row.hl, ['WebmarksPath', strlen(l:row.text) + 3, strlen(l:suffix)])
        let l:row.text .= '  ' . l:suffix
      endif
      call add(l:rows, l:row)
    endfor
  else
    " root bookmarks first, so they do not look like a folder's children
    for l:b in s:sorted(a:policy, s:in_folder(a:data, v:null), a:now)
      call add(l:rows, s:bookmark_row(l:b, 0, has_key(l:pending, l:b.id)))
    endfor
    for l:f in webmarks#domain#folder#children(a:data.folders, v:null)
      call s:tree_folder(l:rows, a:data, a:policy, a:now, l:pending, l:f, 1)
    endfor
  endif
  if empty(l:rows)
    call add(l:rows, s:empty_row())
  endif
  return l:rows
endfunction

" edit_lines(data, policy, now) -> {lines, ids}: the tree as editable
" text (app/edit#parse reads it back). Every line ends with an id marker
" the UI conceals; a provisional name (= the URL) is left out so the URL
" is not written twice.
function! webmarks#app#listing#edit_lines(data, policy, now) abort
  let l:lines = []
  let l:ids = []
  for l:row in webmarks#app#listing#rows(a:data, a:policy, 'tree', a:now, [])
    if l:row.kind ==# 'folder'
      call add(l:lines, repeat('  ', l:row.depth - 1) . s:clean(l:row.folder.name) . '/ ' . s:marker(l:row.id))
    elseif l:row.kind ==# 'bookmark'
      let l:b = l:row.bookmark
      let l:name = l:b.name_source ==# 'url' ? '' : s:clean(l:b.display_name) . '  '
      call add(l:lines, repeat('  ', l:row.depth) . (l:b.is_favorite ? s:star : s:nostar)
            \ . l:name . l:b.url . ' ' . s:marker(l:row.id))
    else
      continue
    endif
    call add(l:ids, l:row.id)
  endfor
  if empty(l:lines)
    call add(l:lines, '# add lines here:  name  https://example.com')
  endif
  return {'lines': l:lines, 'ids': l:ids}
endfunction

function! s:marker(id) abort
  return "\u27e8" . a:id . "\u27e9"
endfunction

" candidates(data, policy, now) -> List of "id\t★ name\tpath\turl"
function! webmarks#app#listing#candidates(data, policy, now) abort
  let l:out = []
  for l:b in s:sorted(a:policy, a:data.bookmarks, a:now)
    call add(l:out, join([l:b.id,
          \ (l:b.is_favorite ? s:star : s:nostar) . s:clean(l:b.display_name),
          \ s:clean(webmarks#domain#folder#path(a:data.folders, l:b.folder_id)),
          \ l:b.url], "\t"))
  endfor
  return l:out
endfunction

let &cpoptions = s:save_cpo
unlet s:save_cpo
