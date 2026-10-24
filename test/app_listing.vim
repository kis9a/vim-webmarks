scriptencoding utf-8
let s:suite = themis#suite('app_listing')
let s:assert = themis#helper('assert')

let s:policy = {'criterion': 'name', 'favorite_first': v:true}

function! s:bm(id, name, folder, ...) abort
  return {'id': a:id, 'url': 'https://' . a:id . '.example', 'display_name': a:name,
        \ 'name_source': get(a:000, 1, 'manual'), 'folder_id': a:folder,
        \ 'is_favorite': get(a:000, 0, v:false), 'created_at': 0,
        \ 'usage': {'rank': 0.0, 'open_count': 0, 'last_launch_at': v:null}}
endfunction

function! s:data() abort
  return {'schema_version': 1, 'next_id': 20,
        \ 'folders': [
        \   {'id': 'f1', 'name': 'Dev', 'parent_id': v:null},
        \   {'id': 'f2', 'name': 'Docs', 'parent_id': 'f1'},
        \   {'id': 'f3', 'name': 'Art', 'parent_id': v:null},
        \ ],
        \ 'bookmarks': [
        \   s:bm('b4', 'zeta', v:null),
        \   s:bm('b5', "tab\tname", v:null, v:true),
        \   s:bm('b6', 'in dev', 'f1'),
        \   s:bm('b7', 'in docs', 'f2'),
        \   s:bm('b8', 'https://b8.example', 'f3', v:false, 'url'),
        \ ]}
endfunction

function! s:suite.tree_order_and_depth() abort
  let l:rows = webmarks#app#listing#rows(s:data(), s:policy, 'tree', 0, [])
  call s:assert.equals(map(copy(l:rows), '[v:val.kind, v:val.id, v:val.depth]'), [
        \ ['bookmark', 'b5', 0], ['bookmark', 'b4', 0],
        \ ['folder', 'f3', 1], ['bookmark', 'b8', 1],
        \ ['folder', 'f1', 1], ['folder', 'f2', 2], ['bookmark', 'b7', 2], ['bookmark', 'b6', 1]])
  call s:assert.equals(map(copy(l:rows), 'v:val.text'), [
        \ '★ tab name', '  zeta', 'Art/', '    https://b8.example',
        \ 'Dev/', '  Docs/', '      in docs', '    in dev'])
endfunction

function! s:suite.highlight_columns() abort
  let l:rows = webmarks#app#listing#rows(s:data(), s:policy, 'tree', 0, ['b7'])
  call s:assert.equals(l:rows[0].hl, [['WebmarksFavorite', 1, strlen('★ ')]])
  call s:assert.equals(l:rows[2].hl, [['WebmarksFolder', 1, 4]])
  call s:assert.equals(l:rows[3].hl, [['WebmarksPending', 1, strlen(l:rows[3].text)]])
  " pending marker
  call s:assert.equals(l:rows[6].text, '      in docs …')
  call s:assert.equals(l:rows[6].hl, [['WebmarksPending', 1, strlen(l:rows[6].text)]])
  let l:d = s:data()
  let l:d.bookmarks[3].is_favorite = v:true
  let l:fav = webmarks#app#listing#rows(l:d, s:policy, 'tree', 0, [])[6]
  call s:assert.equals(l:fav.text, '    ★ in docs')
  call s:assert.equals(l:fav.hl, [['WebmarksFavorite', 5, strlen('★ ')]])
endfunction

function! s:suite.flat() abort
  let l:rows = webmarks#app#listing#rows(s:data(), s:policy, 'flat', 0, [])
  call s:assert.equals(map(copy(l:rows), 'v:val.text'), [
        \ '★ tab name', '  https://b8.example  (Art)', '  in dev  (Dev)', '  in docs  (Dev/Docs)', '  zeta'])
  call s:assert.equals(map(copy(l:rows), 'v:val.depth'), [0, 0, 0, 0, 0])
  let l:r = l:rows[3]
  let l:path_hl = filter(copy(l:r.hl), 'v:val[0] ==# "WebmarksPath"')[0]
  call s:assert.equals(strpart(l:r.text, l:path_hl[1] - 1, l:path_hl[2]), '(Dev/Docs)')
endfunction

function! s:suite.empty() abort
  let l:d = {'schema_version': 1, 'next_id': 1, 'folders': [], 'bookmarks': []}
  let l:rows = webmarks#app#listing#rows(l:d, s:policy, 'tree', 0, [])
  call s:assert.equals(len(l:rows), 1)
  call s:assert.equals(l:rows[0].kind, 'empty')
  call s:assert.equals(l:rows[0].text, '[no bookmarks — press a to add]')
  call s:assert.equals(webmarks#app#listing#rows(l:d, s:policy, 'flat', 0, [])[0].kind, 'empty')
endfunction

function! s:suite.candidates() abort
  let l:c = webmarks#app#listing#candidates(s:data(), s:policy, 0)
  call s:assert.equals(l:c[0], "b5\t★ tab name\t\thttps://b5.example")
  call s:assert.equals(l:c[3], "b7\t  in docs\tDev/Docs\thttps://b7.example")
  for l:line in l:c
    call s:assert.equals(len(split(l:line, "\t", 1)), 4)
  endfor
endfunction

function! s:suite.sort_policy_applies_inside_folders() abort
  let l:d = s:data()
  let l:d.bookmarks += [s:bm('b9', 'alpha', 'f1')]
  let l:d.bookmarks[2].usage = {'rank': 1.0, 'open_count': 1, 'last_launch_at': 100}
  let l:rows = webmarks#app#listing#rows(l:d, {'criterion': 'recent', 'favorite_first': v:false}, 'tree', 200, [])
  let l:ids = map(filter(copy(l:rows), 'get(v:val, "bookmark", {"folder_id": 0}).folder_id is# "f1"'), 'v:val.id')
  call s:assert.equals(l:ids, ['b6', 'b9'])
endfunction
