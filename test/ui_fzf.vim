scriptencoding utf-8
let s:suite = themis#suite('ui_fzf')
let s:assert = themis#helper('assert')

function! s:suite.before_each() abort
  let s:dir = WebmarksTestReset()
  call webmarks#app#store#_reset()
  unlet! g:loaded_webmarks
  runtime plugin/webmarks.vim
  let s:opened = []
  let s:done = []
  let g:webmarks_browser_cmd = ['fake-browser']
  let g:webmarks_test.cmd_runner = function('s:runner')
  call webmarks#app#bookmark#add('https://a.example', 'Alpha', v:null, 1)
  call webmarks#app#bookmark#add('https://b.example', 'Beta', v:null, 1)
  call webmarks#app#bookmark#toggle_favorite('b2')
  let g:WebmarksTestFzfSpec = v:null
endfunction

function! s:suite.after_each() abort
  if exists('s:fake')
    execute 'set runtimepath-=' . fnameescape(s:fake)
    unlet s:fake
  endif
  silent! delfunction fzf#run
  silent! delfunction fzf#wrap
  unlet! g:WebmarksTestFzfSpec
  call delete(s:dir, 'rf')
endfunction

function! s:runner(argv, opts) abort
  call add(s:opened, a:argv[-1])
  return {'exit_code': 0}
endfunction

function! s:on_done(r) abort
  call add(s:done, a:r)
endfunction

function! s:policy() abort
  return {'criterion': 'name', 'favorite_first': v:true}
endfunction

function! s:suite.spec_candidates_and_options() abort
  let l:spec = webmarks#ui#fzf#spec(s:policy(), function('s:on_done'))
  call s:assert.equals(l:spec.source, ["b2\t★ Beta\t\thttps://b.example", "b1\t  Alpha\t\thttps://a.example"])
  call s:assert.equals(l:spec.options, ['--prompt', 'Webmarks> ', '--delimiter', "\t", '--with-nth', '2..',
        \ '--no-sort', '--tiebreak', 'index'])
endfunction

function! s:suite.sink_launches_by_hidden_id() abort
  let l:spec = webmarks#ui#fzf#spec(s:policy(), function('s:on_done'))
  call l:spec.sink(l:spec.source[1])
  call s:assert.equals(s:opened, ['https://a.example'])
  call s:assert.true(s:done[0].ok)
  call s:assert.equals(webmarks#app#store#find_bookmark(webmarks#app#store#current(), 'b1').usage.open_count, 1)
  " junk lines do nothing
  call l:spec.sink('not an id')
  call s:assert.equals(len(s:opened), 1)
endfunction

function! s:suite.missing_fzf() abort
  let l:r = webmarks#ui#fzf#run(s:policy(), function('s:on_done'))
  call s:assert.equals(l:r.code, 'fzf_missing')
endfunction

" A fake fzf on 'runtimepath' (fzf#run cannot be defined in this file).
function! s:install_fake_fzf() abort
  let s:fake = s:dir . '/fakefzf'
  call mkdir(s:fake . '/autoload', 'p')
  call writefile([
        \ 'function! fzf#wrap(spec) abort',
        \ '  return extend(copy(a:spec), {"wrapped": 1})',
        \ 'endfunction',
        \ 'function! fzf#run(spec) abort',
        \ '  let g:WebmarksTestFzfSpec = a:spec',
        \ 'endfunction'], s:fake . '/autoload/fzf.vim')
  execute 'set runtimepath+=' . fnameescape(s:fake)
  runtime autoload/fzf.vim
endfunction

function! s:suite.search_command_uses_tree_policy() abort
  call s:install_fake_fzf()
  WebmarksSearch
  call s:assert.equals(g:WebmarksTestFzfSpec.wrapped, 1)
  " default policy: frecency, favorites first -> Beta first
  call s:assert.equals(g:WebmarksTestFzfSpec.source[0][:1], 'b2')
  call g:WebmarksTestFzfSpec.sink(g:WebmarksTestFzfSpec.source[0])
  call s:assert.equals(s:opened, ['https://b.example'])
  " a tree with its own policy
  Webmarks
  normal ~P
  WebmarksSearch
  call s:assert.equals(g:WebmarksTestFzfSpec.source[0][:1], 'b1')
  silent! only!
  let l:buf = webmarks#ui#tree#bufnr()
  execute 'silent! bwipeout!' l:buf
endfunction
