scriptencoding utf-8
let s:suite = themis#suite('app_folder')
let s:assert = themis#helper('assert')

function! s:suite.before_each() abort
  let s:dir = WebmarksTestReset()
  call webmarks#app#store#_reset()
endfunction

function! s:suite.after_each() abort
  call delete(s:dir, 'rf')
endfunction

function! s:suite.add_two_levels_then_reject_third() abort
  let l:a = webmarks#app#folder#add('Dev', v:null)
  call s:assert.equals(l:a.id, 'f1')
  let l:b = webmarks#app#folder#add('Docs', 'f1')
  call s:assert.equals(l:b.folder.parent_id, 'f1')
  call s:assert.equals(webmarks#app#folder#add('Deep', l:b.id).code, 'depth_exceeded')
  call s:assert.equals(webmarks#app#folder#add('X', 'f99').code, 'not_found')
  call s:assert.equals(webmarks#app#folder#add('', v:null).code, 'empty_name')
  call s:assert.equals(len(webmarks#app#store#current().folders), 2)
endfunction

function! s:suite.rename_and_move() abort
  call webmarks#app#folder#add('A', v:null)
  call webmarks#app#folder#add('B', v:null)
  call webmarks#app#folder#add('C', 'f1')
  call s:assert.equals(webmarks#app#folder#rename('f2', 'BB').folder.name, 'BB')
  call s:assert.equals(webmarks#app#folder#rename('f9', 'x').code, 'not_found')
  call s:assert.equals(webmarks#app#folder#move('f1', 'f2').code, 'depth_exceeded')
  call s:assert.equals(webmarks#app#folder#move('f1', 'f3').code, 'cyclic_parent')
  call s:assert.equals(webmarks#app#folder#move('f9', v:null).code, 'not_found')
  let l:r = webmarks#app#folder#move('f3', 'f2')
  call s:assert.true(l:r.ok)
  call s:assert.equals(webmarks#app#store#find_folder(webmarks#app#store#current(), 'f3').parent_id, 'f2')
endfunction

function! s:suite.remove_only_empty() abort
  call webmarks#app#folder#add('A', v:null)
  call webmarks#app#folder#add('B', 'f1')
  call s:assert.equals(webmarks#app#folder#remove('f1').code, 'folder_not_empty')
  call webmarks#app#bookmark#add('https://a.example', '', 'f2', 1)
  call s:assert.equals(webmarks#app#folder#remove('f2').code, 'folder_not_empty')
  call webmarks#app#bookmark#remove('b3')
  call s:assert.true(webmarks#app#folder#remove('f2').ok)
  call s:assert.true(webmarks#app#folder#remove('f1').ok)
  call s:assert.equals(webmarks#app#folder#remove('f1').code, 'not_found')
endfunction

function! s:suite.choices_exclude_the_folder_and_its_children() abort
  call webmarks#app#folder#add('Dev', v:null)
  call webmarks#app#folder#add('Docs', 'f1')
  call webmarks#app#folder#add('Art', v:null)
  let l:data = webmarks#app#store#current()
  call s:assert.equals(webmarks#app#folder#choices(l:data, v:null),
        \ [{'id': 'f3', 'path': 'Art'}, {'id': 'f1', 'path': 'Dev'}, {'id': 'f2', 'path': 'Dev/Docs'}])
  call s:assert.equals(webmarks#app#folder#choices(l:data, 'f1'), [{'id': 'f3', 'path': 'Art'}])
endfunction
