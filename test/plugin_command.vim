scriptencoding utf-8
let s:suite = themis#suite('plugin_command')
let s:assert = themis#helper('assert')

function! s:suite.before_each() abort
  let s:dir = WebmarksTestReset()
  call webmarks#app#store#_reset()
  call webmarks#app#title#_reset()
  unlet! g:loaded_webmarks
  runtime plugin/webmarks.vim
  let s:texts = []
  let s:asked = []
  let g:webmarks_test.prompt = {'text': function('s:text')}
  let g:webmarks_test.title_fetcher = function('s:title_of')
endfunction

function! s:suite.after_each() abort
  silent! only!
  let l:buf = webmarks#ui#tree#bufnr()
  if l:buf > 0
    execute 'silent! bwipeout!' l:buf
  endif
  call delete(s:dir, 'rf')
endfunction

function! s:title_of(url, ctx) abort
  return {'ok': v:true, 'title': 'Title of ' . a:url}
endfunction

function! s:text(prompt, default) abort
  call add(s:asked, a:prompt)
  return empty(s:texts) ? {'ok': v:false, 'code': 'cancelled', 'error': ''} : remove(s:texts, 0)
endfunction

function! s:bookmarks() abort
  return map(webmarks#app#store#current().bookmarks, '[v:val.url, v:val.display_name, v:val.name_source, v:val.folder_id]')
endfunction

function! s:suite.defaults_and_commands_exist() abort
  call s:assert.equals([g:webmarks_open, g:webmarks_width, g:webmarks_default_sort,
        \ g:webmarks_favorite_first, g:webmarks_default_view, g:webmarks_fetch_title,
        \ g:webmarks_no_default_mappings], ['vsplit', 40, 'frecency', 1, 'tree', 1, 0])
  for l:c in ['Webmarks', 'WebmarksToggle', 'WebmarksAdd', 'WebmarksSearch', 'WebmarksEdit']
    call s:assert.equals(exists(':' . l:c), 2, l:c)
  endfor
  call s:assert.false(exists('g:webmarks_file') && g:webmarks_file ==# '')
endfunction

function! s:suite.add_url_and_name() abort
  WebmarksAdd https://a.example/?q=1&r=2#x My   Site
  call s:assert.equals(s:bookmarks(), [['https://a.example/?q=1&r=2#x', 'My Site', 'manual', v:null]])
  call s:assert.equals(s:asked, [])
  " no -bar: '|' reaches the command (and is rejected as a URL character)
  WebmarksAdd https://b.example/a|b
  call s:assert.match(execute('messages'), 'invalid URL.*a|b')
endfunction

function! s:suite.add_url_only_fetches_title() abort
  WebmarksAdd https://a.example
  call s:assert.equals(s:bookmarks(), [['https://a.example', 'Title of https://a.example', 'fetched', v:null]])
endfunction

function! s:suite.add_name_only_asks_for_url() abort
  let s:texts = [{'ok': v:true, 'value': 'https://b.example'}]
  WebmarksAdd Just a name
  call s:assert.equals(s:asked, ['URL: '])
  call s:assert.equals(s:bookmarks(), [['https://b.example', 'Just a name', 'manual', v:null]])
endfunction

function! s:suite.add_nothing_asks_for_both() abort
  let s:texts = [{'ok': v:true, 'value': 'https://c.example'}, {'ok': v:true, 'value': ''}]
  WebmarksAdd
  call s:assert.equals(len(s:asked), 2)
  call s:assert.equals(s:bookmarks()[0][2], 'fetched')
  " cancelled
  WebmarksAdd
  call s:assert.equals(len(s:bookmarks()), 1)
endfunction

function! s:suite.add_without_tty_reports_no_tty() abort
  unlet g:webmarks_test.prompt
  let l:r = webmarks#add_command('')
  call s:assert.equals(l:r.code, 'no_tty')
endfunction

function! s:suite.add_invalid_and_duplicate() abort
  WebmarksAdd https://a.example
  WebmarksAdd https://a.example again
  call s:assert.match(execute('messages'), 'already registered')
  call s:assert.equals(len(s:bookmarks()), 1)
  call s:assert.equals(webmarks#add('ftp://x', '', v:null).code, 'invalid_url')
endfunction

function! s:suite.fetch_title_off() abort
  let g:webmarks_fetch_title = 0
  WebmarksAdd https://a.example
  call s:assert.equals(s:bookmarks()[0][2], 'url')
endfunction

function! s:suite.add_redraws_an_open_tree() abort
  Webmarks
  wincmd p
  WebmarksAdd https://d.example Dee
  let l:buf = webmarks#ui#tree#bufnr()
  call s:assert.equals(getbufline(l:buf, 1, '$'), ['  Dee'])
endfunction

function! s:suite.toggle() abort
  WebmarksToggle
  call s:assert.equals(bufname('%'), 'webmarks://webmarks')
  WebmarksToggle
  call s:assert.equals(winnr('$'), 1)
endfunction

function! s:suite.plugin_does_not_load_autoload() abort
  " a fresh Vim: sourcing plugin/ must not define any autoload function
  let l:cmd = has('nvim')
        \ ? ['nvim', '--headless', '-u', 'NONE', '-i', 'NONE', '-n']
        \ : ['vim', '-Nu', 'NONE', '-i', 'NONE', '-n', '-e', '-s']
  let l:out = tempname()
  let l:script = ['set rtp^=' . fnameescape(getcwd()), 'runtime plugin/webmarks.vim',
        \ 'call writefile([string(exists("*webmarks#open")), execute("scriptnames")], ' . string(l:out) . ')',
        \ 'qa!']
  let l:file = tempname() . '.vim'
  call writefile(l:script, l:file)
  call system(join(map(l:cmd + ['-S', l:file], 'shellescape(v:val)')) . ' </dev/null')
  let l:lines = readfile(l:out)
  call s:assert.equals(l:lines[0], '0')
  call s:assert.not_match(join(l:lines, "\n"), 'autoload/webmarks')
endfunction
