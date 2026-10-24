scriptencoding utf-8
let s:suite = themis#suite('domain_folder')
let s:assert = themis#helper('assert')

" f1 Dev / f2 Docs (under f1) / f3 Misc / f4 Deep (under f2)
function! s:folders() abort
  return [
        \ {'id': 'f1', 'name': 'Dev', 'parent_id': v:null},
        \ {'id': 'f2', 'name': 'Docs', 'parent_id': 'f1'},
        \ {'id': 'f3', 'name': 'misc', 'parent_id': v:null},
        \ {'id': 'f5', 'name': 'Api', 'parent_id': 'f1'},
        \ ]
endfunction

function! s:bm(id, folder) abort
  return {'id': a:id, 'url': 'https://' . a:id . '.example', 'folder_id': a:folder}
endfunction

function! s:suite.new_and_rename() abort
  let l:r = webmarks#domain#folder#new('f9', " A\tB ", v:null)
  call s:assert.equals(l:r.folder, {'id': 'f9', 'name': 'A B', 'parent_id': v:null})
  call s:assert.equals(webmarks#domain#folder#new('f9', '', v:null).code, 'empty_name')
  call s:assert.equals(webmarks#domain#folder#rename(l:r.folder, 'C').folder.name, 'C')
  call s:assert.equals(webmarks#domain#folder#rename(l:r.folder, "\xff").code, 'invalid_text')
endfunction

function! s:suite.depth() abort
  let l:f = s:folders()
  call s:assert.equals(webmarks#domain#folder#depth(l:f, v:null), 0)
  call s:assert.equals(webmarks#domain#folder#depth(l:f, 'f1'), 1)
  call s:assert.equals(webmarks#domain#folder#depth(l:f, 'f2'), 2)
  call s:assert.equals(webmarks#domain#folder#depth(l:f, 'f99'), -1)
  let l:cyc = [{'id': 'f1', 'name': 'a', 'parent_id': 'f2'}, {'id': 'f2', 'name': 'b', 'parent_id': 'f1'}]
  call s:assert.equals(webmarks#domain#folder#depth(l:cyc, 'f1'), -1)
endfunction

function! s:suite.path() abort
  call s:assert.equals(webmarks#domain#folder#path(s:folders(), 'f2'), 'Dev/Docs')
  call s:assert.equals(webmarks#domain#folder#path(s:folders(), v:null), '')
endfunction

function! s:suite.children_sorted_by_name_then_id() abort
  let l:f = s:folders() + [{'id': 'f4', 'name': 'api', 'parent_id': 'f1'}]
  call s:assert.equals(map(webmarks#domain#folder#children(l:f, 'f1'), 'v:val.id'), ['f4', 'f5', 'f2'])
  call s:assert.equals(map(webmarks#domain#folder#children(l:f, v:null), 'v:val.id'), ['f1', 'f3'])
endfunction

function! s:suite.validate_parent_all_branches() abort
  let l:f = s:folders()
  call s:assert.true(webmarks#domain#folder#validate_parent(l:f, v:null, v:null).ok)
  call s:assert.true(webmarks#domain#folder#validate_parent(l:f, v:null, 'f1').ok)
  call s:assert.equals(webmarks#domain#folder#validate_parent(l:f, v:null, 'f9').code, 'not_found')
  call s:assert.equals(webmarks#domain#folder#validate_parent(l:f, v:null, 'f2').code, 'depth_exceeded')
  call s:assert.equals(webmarks#domain#folder#validate_parent(l:f, 'f1', 'f1').code, 'cyclic_parent')
  call s:assert.equals(webmarks#domain#folder#validate_parent(l:f, 'f1', 'f2').code, 'cyclic_parent')
  " f1 has children: moving it under f3 would make depth 3
  call s:assert.equals(webmarks#domain#folder#validate_parent(l:f, 'f1', 'f3').code, 'depth_exceeded')
  " a leaf can move under a top-level folder
  call s:assert.true(webmarks#domain#folder#validate_parent(l:f, 'f2', 'f3').ok)
  call s:assert.true(webmarks#domain#folder#validate_parent(l:f, 'f2', v:null).ok)
endfunction

function! s:suite.can_delete() abort
  let l:f = s:folders()
  call s:assert.equals(webmarks#domain#folder#can_delete(l:f, [], 'f1').code, 'folder_not_empty')
  call s:assert.equals(webmarks#domain#folder#can_delete(l:f, [s:bm('b1', 'f3')], 'f3').code, 'folder_not_empty')
  call s:assert.true(webmarks#domain#folder#can_delete(l:f, [s:bm('b1', v:null)], 'f3').ok)
  call s:assert.equals(webmarks#domain#folder#can_delete(l:f, [], 'f9').code, 'not_found')
endfunction

function! s:suite.descendants() abort
  call s:assert.equals(sort(map(webmarks#domain#folder#descendants(s:folders(), 'f1'), 'v:val.id')), ['f2', 'f5'])
endfunction

function! s:suite.validate_all_h1_to_h5() abort
  call s:assert.true(webmarks#domain#folder#validate_all(s:folders(), [s:bm('b1', 'f2')]).ok)
  " H1
  let l:deep = s:folders() + [{'id': 'f6', 'name': 'x', 'parent_id': 'f2'}]
  call s:assert.equals(webmarks#domain#folder#validate_all(l:deep, []).code, 'invalid_data')
  " H2
  let l:selfp = [{'id': 'f1', 'name': 'x', 'parent_id': 'f1'}]
  call s:assert.equals(webmarks#domain#folder#validate_all(l:selfp, []).code, 'invalid_data')
  " H3
  let l:cyc = [{'id': 'f1', 'name': 'a', 'parent_id': 'f2'}, {'id': 'f2', 'name': 'b', 'parent_id': 'f1'}]
  let l:r = webmarks#domain#folder#validate_all(l:cyc, [])
  call s:assert.equals(l:r.code, 'invalid_data')
  call s:assert.match(l:r.error, 'f1')
  " H4
  let l:orphan = [{'id': 'f1', 'name': 'a', 'parent_id': 'f7'}]
  call s:assert.equals(webmarks#domain#folder#validate_all(l:orphan, []).code, 'invalid_data')
  " H5
  let l:r5 = webmarks#domain#folder#validate_all(s:folders(), [s:bm('b1', 'f9')])
  call s:assert.equals(l:r5.code, 'invalid_data')
  call s:assert.match(l:r5.error, 'b1')
  " duplicate ids
  call s:assert.equals(webmarks#domain#folder#validate_all(s:folders() + [s:folders()[0]], []).code, 'invalid_data')
  call s:assert.equals(webmarks#domain#folder#validate_all([], [s:bm('b1', v:null), s:bm('b1', v:null)]).code, 'invalid_data')
endfunction

function! s:suite.validate_single() abort
  call s:assert.true(webmarks#domain#folder#validate({'id': 'f1', 'name': 'a', 'parent_id': v:null}).ok)
  call s:assert.equals(webmarks#domain#folder#validate({'id': 'b1', 'name': 'a', 'parent_id': v:null}).code, 'invalid_data')
  call s:assert.equals(webmarks#domain#folder#validate({'id': 'f1', 'name': '', 'parent_id': v:null}).code, 'invalid_data')
  call s:assert.equals(webmarks#domain#folder#validate({'id': 'f1', 'name': 'a', 'parent_id': 1}).code, 'invalid_data')
  call s:assert.equals(webmarks#domain#folder#validate({'id': 'f1', 'name': 'a'}).code, 'invalid_data')
endfunction
