scriptencoding utf-8
" app/edit.vim - the tree edited as text: parse lines, then apply the
" difference in one store#mutate (all or nothing).
"
"   parse(lines, snapshot_ids)      -> Result {entries, delete_ids, errors}
"   commit(entries, delete_ids, now) -> Result {fetch_title, warnings, counts}
"
" The UI asks for the delete confirmation between the two (app never
" prompts).

let s:save_cpo = &cpoptions
set cpoptions&vim

let s:max_errors = 10
let s:marker = '\s\?' . "⟨" . '\([bf]\d\+\)' . "⟩"
" (documentation of the URL rule; parse_line() implements it directly)
let s:url_token = '\%(^\|\s\+\)\zshttps\?://\S\+$'
let s:bookmark_head = '^\( *\)\(' . "★" . ' \|\* \|  \)\(.*\)$'

function! s:error(errors, lnum, code, msg) abort
  if len(a:errors) < s:max_errors
    call add(a:errors, {'lnum': a:lnum, 'code': a:code,
          \ 'error': (a:lnum > 0 ? 'line ' . a:lnum . ': ' : '') . a:msg})
  endif
endfunction

function! s:failed(errors) abort
  return {'ok': v:false, 'code': a:errors[0].code, 'error': a:errors[0].error,
        \ 'changed': v:false, 'errors': a:errors}
endfunction

" --- parse -------------------------------------------------------------

" One line -> Entry, v:null (ignored line) or an error dict {code, msg}.
function! s:parse_line(text) abort
  let l:line = substitute(a:text, '[[:space:]\r]*$', '', '')
  if l:line =~# '^ *\t'
    return {'code': 'parse_error', 'msg': 'bad indent (use spaces)'}
  endif
  let l:id = ''
  let l:m = matchlist(l:line, s:marker)
  if !empty(l:m)
    let l:id = l:m[1]
    let l:line = substitute(l:line, s:marker, '', '')
    if l:line =~# s:marker
      return {'code': 'parse_error', 'msg': 'multiple ids on one line'}
    endif
    let l:line = substitute(l:line, '[[:space:]\r]*$', '', '')
  endif
  if l:line =~# '^\s*$' || l:line =~# '^\s*#'
    return v:null
  endif
  " the URL first: a URL may end with '/' too. The last blank-separated
  " token, when it starts with http(s)://, is the URL (s:url_token; this
  " form avoids a slow backtracking regex on every line).
  let l:url = matchstr(l:line, '\S\+$')
  if l:url =~# '^https\?://'
    let l:rest = strpart(l:line, 0, strlen(l:line) - strlen(l:url))
    let l:h = matchlist(l:rest, s:bookmark_head)
    if empty(l:h) || strlen(l:h[1]) % 2
      return {'code': 'parse_error', 'msg': 'bad indent (bookmark lines need the 2-column star slot)'}
    endif
    let l:u = webmarks#domain#bookmark#validate_url(l:url)
    if !l:u.ok
      return {'code': 'invalid_url', 'msg': l:u.error}
    endif
    if l:id =~# '^f'
      return {'code': 'parse_error', 'msg': 'id ' . l:id . ' belongs to a folder'}
    endif
    return {'kind': 'bookmark', 'id': l:id, 'depth': strlen(l:h[1]) / 2,
          \ 'name': trim(l:h[3]), 'url': l:u.value, 'favorite': l:h[2] ==# '  ' ? v:false : v:true}
  endif
  if l:line =~# '/$'
    let l:h = matchlist(strpart(l:line, 0, strlen(l:line) - 1), '^\( *\)\(.*\)$')
    if strlen(l:h[1]) % 2
      return {'code': 'parse_error', 'msg': 'bad indent'}
    endif
    let l:depth = strlen(l:h[1]) / 2 + 1
    if l:depth > 2
      return {'code': 'depth_exceeded', 'msg': 'folders are limited to 2 levels'}
    endif
    if trim(l:h[2]) ==# ''
      return {'code': 'empty_name', 'msg': 'folder name is empty'}
    endif
    if l:id =~# '^b'
      return {'code': 'parse_error', 'msg': 'id ' . l:id . ' belongs to a bookmark'}
    endif
    return {'kind': 'folder', 'id': l:id, 'depth': l:depth, 'name': trim(l:h[2]),
          \ 'url': '', 'favorite': v:false}
  endif
  return {'code': 'parse_error', 'msg': 'URL is required (or end the line with / for a folder)'}
endfunction

" The column that decides nesting: a folder at depth d sits at 2(d-1),
" a bookmark at depth d at 2d.
function! s:column(e) abort
  return a:e.kind ==# 'folder' ? 2 * (a:e.depth - 1) : 2 * a:e.depth
endfunction

function! webmarks#app#edit#parse(lines, snapshot_ids) abort
  let l:entries = []
  let l:open = []
  let l:errors = []
  let l:seen = {}
  let l:lnum = 0
  for l:text in a:lines
    let l:lnum += 1
    let l:e = s:parse_line(l:text)
    if l:e is v:null
      continue
    endif
    if has_key(l:e, 'code')
      call s:error(l:errors, l:lnum, l:e.code, l:e.msg)
      continue
    endif
    let l:e.lnum = l:lnum
    if l:e.id !=# ''
      if has_key(l:seen, l:e.id)
        call s:error(l:errors, l:lnum, 'parse_error', 'duplicate id ' . l:e.id . ' (also on line ' . l:seen[l:e.id] . ')')
        continue
      endif
      let l:seen[l:e.id] = l:lnum
    endif
    " the tree check: the first line above with a smaller column must be
    " a folder exactly one level up
    " l:open holds the lines above with strictly increasing columns; after
    " popping those at or right of this one, its top is the first line
    " above with a smaller column
    let l:col = s:column(l:e)
    let l:e.col = l:col
    while !empty(l:open) && l:open[-1].col >= l:col
      call remove(l:open, -1)
    endwhile
    let l:e.parent_lnum = 0
    if l:col > 0
      let l:parent = empty(l:open) ? v:null : l:open[-1]
      if l:parent is v:null || l:parent.kind !=# 'folder' || l:parent.col != l:col - 2
        call s:error(l:errors, l:lnum, 'parse_error', 'bad indent (no parent folder at this level)')
        continue
      endif
      let l:e.parent_lnum = l:parent.lnum
    endif
    call add(l:open, l:e)
    call add(l:entries, l:e)
  endfor
  if !empty(l:errors)
    return s:failed(l:errors)
  endif
  let l:delete_ids = filter(copy(a:snapshot_ids), '!has_key(l:seen, v:val)')
  return {'ok': v:true, 'code': '', 'error': '', 'changed': v:false,
        \ 'entries': l:entries, 'delete_ids': l:delete_ids, 'errors': []}
endfunction

" --- commit ------------------------------------------------------------

function! webmarks#app#edit#commit(entries, delete_ids, now) abort
  return webmarks#app#store#mutate(function('s:transform', [a:entries, a:delete_ids, a:now]))
endfunction

function! s:same(a, b) abort
  return type(a:a) == type(a:b) && a:a ==# a:b
endfunction

" Plan and apply in one go against the freshly read {data}; returns the
" new data (the mutate contract). Fields are compared with the data as it
" was before this edit, never with values changed earlier in the loop.
function! s:transform(entries, delete_ids, now, data) abort
  let l:orig = a:data
  let l:work = deepcopy(a:data)
  let l:errors = []
  let l:warnings = []
  let l:fetch = []
  let l:counts = {'added': 0, 'renamed': 0, 'moved': 0, 'url_changed': 0,
        \ 'favorite_changed': 0, 'deleted': 0}
  let l:id_of = {0: v:null}
  let l:entry_of = {}
  " id -> item of the original data / index into l:work (no linear scans:
  " an edit of 1,000 lines would otherwise be quadratic)
  let l:orig_b = {}
  for l:b in l:orig.bookmarks
    let l:orig_b[l:b.id] = l:b
  endfor
  let l:orig_f = {}
  for l:f in l:orig.folders
    let l:orig_f[l:f.id] = l:f
  endfor
  let l:at_b = {}
  for l:i in range(len(l:work.bookmarks))
    let l:at_b[l:work.bookmarks[l:i].id] = l:i
  endfor
  let l:at_f = {}
  for l:i in range(len(l:work.folders))
    let l:at_f[l:work.folders[l:i].id] = l:i
  endfor

  for l:e0 in a:entries
    let l:e = copy(l:e0)
    if l:e.id !=# ''
      let l:exists = has_key(l:e.kind ==# 'folder' ? l:orig_f : l:orig_b, l:e.id)
      if !l:exists
        call add(l:warnings, printf('line %d: %s was removed elsewhere; added again as new', l:e.lnum, l:e.id))
        let l:e.id = ''
      endif
    endif
    let l:parent = get(l:id_of, l:e.parent_lnum, v:null)

    if l:e.kind ==# 'folder'
      if l:e.id ==# ''
        let [l:id, l:work] = webmarks#app#store#next_id(l:work, 'f')
        let l:r = webmarks#domain#folder#new(l:id, l:e.name, l:parent)
        if !l:r.ok
          call s:error(l:errors, l:e.lnum, l:r.code, l:r.error)
          let l:id_of[l:e.lnum] = l:id
          continue
        endif
        let l:at_f[l:id] = len(l:work.folders)
        call add(l:work.folders, l:r.folder)
        let l:counts.added += 1
      else
        let l:id = l:e.id
        let l:before = l:orig_f[l:id]
        let l:f = l:work.folders[l:at_f[l:id]]
        let l:r = webmarks#domain#folder#rename(l:f, l:e.name)
        if !l:r.ok
          call s:error(l:errors, l:e.lnum, l:r.code, l:r.error)
        elseif l:r.folder.name !=# l:before.name
          let l:f = l:r.folder
          let l:counts.renamed += 1
        endif
        if !s:same(l:before.parent_id, l:parent)
          let l:f = webmarks#domain#folder#set_parent(l:f, l:parent).folder
          let l:counts.moved += 1
        endif
        let l:work.folders[l:at_f[l:id]] = l:f
      endif
      let l:id_of[l:e.lnum] = l:id
      let l:entry_of[l:id] = l:e
      continue
    endif

    " bookmark
    if l:e.id ==# ''
      let [l:id, l:work] = webmarks#app#store#next_id(l:work, 'b')
      let l:r = webmarks#domain#bookmark#new(l:id, l:e.url, l:e.name, l:parent, a:now)
      if !l:r.ok
        call s:error(l:errors, l:e.lnum, l:r.code, l:r.error)
        continue
      endif
      let l:b = l:r.bookmark
      if l:e.favorite
        let l:b = webmarks#domain#bookmark#toggle_favorite(l:b).bookmark
      endif
      let l:at_b[l:id] = len(l:work.bookmarks)
      call add(l:work.bookmarks, l:b)
      let l:counts.added += 1
      if l:b.name_source ==# 'url'
        call add(l:fetch, {'id': l:id, 'url': l:b.url})
      endif
      let l:entry_of[l:id] = l:e
      continue
    endif
    let l:id = l:e.id
    let l:before = l:orig_b[l:id]
    let l:b = l:work.bookmarks[l:at_b[l:id]]
    let l:refetch = 0
    if l:e.url !=# l:before.url
      let l:r = webmarks#domain#bookmark#change_url(l:b, l:e.url)
      if !l:r.ok
        call s:error(l:errors, l:e.lnum, l:r.code, l:r.error)
        continue
      endif
      let l:b = l:r.bookmark
      let l:counts.url_changed += 1
      let l:refetch = l:b.name_source ==# 'url'
    endif
    if l:e.name ==# ''
      if l:before.name_source !=# 'url'
        " an emptied name: back to the provisional name and fetch a title
        let l:b = webmarks#domain#bookmark#reset_name(l:b).bookmark
        let l:counts.renamed += 1
        let l:refetch = 1
      endif
    elseif l:e.name !=# l:before.display_name || l:before.name_source ==# 'url'
      let l:r = webmarks#domain#bookmark#rename(l:b, l:e.name)
      if !l:r.ok
        call s:error(l:errors, l:e.lnum, l:r.code, l:r.error)
        continue
      endif
      if l:r.bookmark.display_name !=# l:before.display_name || l:before.name_source ==# 'url'
        let l:b = l:r.bookmark
        let l:counts.renamed += 1
        let l:refetch = 0
      endif
    endif
    if (l:e.favorite ? 1 : 0) != (l:before.is_favorite ? 1 : 0)
      let l:b = webmarks#domain#bookmark#toggle_favorite(l:b).bookmark
      let l:counts.favorite_changed += 1
    endif
    if !s:same(l:before.folder_id, l:parent)
      let l:b = webmarks#domain#bookmark#move_to(l:b, l:parent).bookmark
      let l:counts.moved += 1
    endif
    if l:refetch
      call add(l:fetch, {'id': l:id, 'url': l:b.url})
    endif
    let l:work.bookmarks[l:at_b[l:id]] = l:b
    let l:entry_of[l:id] = l:e
  endfor

  " deletions: bookmarks first, then folders (only what is still there)
  let l:del = {}
  for l:id in a:delete_ids
    let l:del[l:id] = 1
  endfor
  let l:before_count = len(l:work.bookmarks) + len(l:work.folders)
  call filter(l:work.bookmarks, '!has_key(l:del, v:val.id)')
  let l:dying = filter(copy(l:work.folders), 'has_key(l:del, v:val.id)')
  for l:f in l:dying
    let l:blocked = !empty(filter(copy(l:work.folders), '!has_key(l:del, v:val.id) && s:same(v:val.parent_id, l:f.id)'))
          \ || !empty(filter(copy(l:work.bookmarks), 's:same(v:val.folder_id, l:f.id)'))
    if l:blocked
      call s:error(l:errors, 0, 'folder_not_empty',
            \ 'folder is not empty: ' . l:f.name . ' (it has items that are not in this buffer; :e! to see them)')
    endif
  endfor
  call filter(l:work.folders, '!has_key(l:del, v:val.id)')
  let l:counts.deleted = l:before_count - len(l:work.bookmarks) - len(l:work.folders)

  if empty(l:errors)
    let l:v = webmarks#domain#folder#validate_all(l:work.folders, l:work.bookmarks)
    if !l:v.ok
      call s:error(l:errors, s:lnum_in(l:v.error, l:entry_of), 'depth_exceeded', l:v.error)
    endif
    " the find_duplicate rule (exact match), indexed by URL
    let l:owner = {}
    for l:b in l:work.bookmarks
      if has_key(l:owner, l:b.url)
        let l:e = get(l:entry_of, l:b.id, get(l:entry_of, l:owner[l:b.url], {'lnum': 0}))
        call s:error(l:errors, l:e.lnum, 'duplicate_url', 'already registered: ' . l:b.url)
      else
        let l:owner[l:b.url] = l:b.id
      endif
    endfor
  endif

  if !empty(l:errors)
    return s:failed(l:errors)
  endif
  return {'ok': v:true, 'code': '', 'error': '', 'changed': l:work != l:orig,
        \ 'data': l:work, 'fetch_title': l:fetch, 'warnings': l:warnings, 'counts': l:counts}
endfunction

" The line of the item an invariant message names, else 0.
function! s:lnum_in(msg, entry_of) abort
  let l:id = matchstr(a:msg, '\<[bf]\d\+\>')
  return has_key(a:entry_of, l:id) ? a:entry_of[l:id].lnum : 0
endfunction

let &cpoptions = s:save_cpo
unlet s:save_cpo
