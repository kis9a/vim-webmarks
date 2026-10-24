scriptencoding utf-8
" vim-webmarks - web bookmarks in Vim: folders, frecency, fzf, a browser
" Maintainer: kis9a
" License: MIT

if exists('g:loaded_webmarks')
  finish
endif
let g:loaded_webmarks = 1

let s:save_cpo = &cpoptions
set cpoptions&vim

if !exists('g:webmarks_open')
  let g:webmarks_open = 'vsplit'
endif
if !exists('g:webmarks_width')
  let g:webmarks_width = 40
endif
if !exists('g:webmarks_default_sort')
  let g:webmarks_default_sort = 'frecency'
endif
if !exists('g:webmarks_favorite_first')
  let g:webmarks_favorite_first = 1
endif
if !exists('g:webmarks_default_view')
  let g:webmarks_default_view = 'tree'
endif
if !exists('g:webmarks_fetch_title')
  let g:webmarks_fetch_title = 1
endif
if !exists('g:webmarks_no_default_mappings')
  let g:webmarks_no_default_mappings = 0
endif

" no -bar: a URL may contain '|'
command! -nargs=? -complete=customlist,webmarks#complete_open Webmarks call webmarks#open(<q-args>)
command! -nargs=? -complete=customlist,webmarks#complete_open WebmarksToggle call webmarks#toggle(<q-args>)
command! -nargs=* WebmarksAdd call webmarks#add_command(<q-args>)
command! WebmarksSearch call webmarks#search()
command! -nargs=? -complete=customlist,webmarks#complete_open WebmarksEdit call webmarks#edit(<q-args>)

let &cpoptions = s:save_cpo
unlet s:save_cpo
