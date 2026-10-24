scriptencoding utf-8
let s:suite = themis#suite('deps_browser')
let s:assert = themis#helper('assert')

function! s:suite.before_each() abort
  let s:dir = WebmarksTestReset()
  let s:seen = []
  let s:exit = 0
  let g:webmarks_test.cmd_runner = function('s:stub')
endfunction

function! s:suite.after_each() abort
  call delete(s:dir, 'rf')
endfunction

function! s:stub(argv, opts) abort
  call add(s:seen, a:argv)
  return {'exit_code': s:exit, 'stdout': ''}
endfunction

function! s:suite.list_setting_is_used_as_is() abort
  let g:webmarks_browser_cmd = ['firefox', '--new-tab']
  call s:assert.true(webmarks#deps#browser#open('https://a.example/?x=1&y=2').ok)
  call s:assert.equals(s:seen, [['firefox', '--new-tab', 'https://a.example/?x=1&y=2']])
endfunction

function! s:suite.string_setting_is_an_executable_name() abort
  let g:webmarks_browser_cmd = 'my browser'
  call webmarks#deps#browser#open('https://a.example')
  call s:assert.equals(s:seen, [['my browser', 'https://a.example']])
endfunction

function! s:suite.missing_executable() abort
  unlet g:webmarks_test.cmd_runner
  let g:webmarks_browser_cmd = ['webmarks-no-such-browser']
  call s:assert.equals(webmarks#deps#browser#command().code, 'not_executable')
  let g:webmarks_browser_cmd = []
  call s:assert.equals(webmarks#deps#browser#command().code, 'no_browser')
endfunction

function! s:suite.detects_default() abort
  let l:r = webmarks#deps#browser#command()
  call s:assert.true(l:r.ok)
  if has('mac') || has('macunix')
    call s:assert.equals(l:r.argv, ['open'])
  endif
endfunction

function! s:suite.invalid_url_is_never_run() abort
  let g:webmarks_browser_cmd = ['b']
  for l:u in ['-x', 'file:///etc/passwd', 'https://a.b/"x', "https://a.b/\nx", 'javascript:alert(1)']
    call s:assert.equals(webmarks#deps#browser#open(l:u).code, 'invalid_url', l:u)
  endfor
  call s:assert.equals(s:seen, [])
endfunction

function! s:suite.failure_exit() abort
  let g:webmarks_browser_cmd = ['b']
  let s:exit = 3
  let l:r = webmarks#deps#browser#open('https://a.example')
  call s:assert.equals(l:r.code, 'browser_failed')
  call s:assert.match(l:r.error, 'exit 3')
endfunction

function! s:suite.real_command_echo() abort
  " a harmless real command through the real system() path
  unlet g:webmarks_test.cmd_runner
  let g:webmarks_browser_cmd = ['true']
  call s:assert.true(webmarks#deps#browser#open('https://a.example').ok)
  let g:webmarks_browser_cmd = ['false']
  call s:assert.equals(webmarks#deps#browser#open('https://a.example').code, 'browser_failed')
endfunction

function! s:suite.a_command_that_leaves_a_child_running_returns_at_once() abort
  " like xdg-open starting a browser: the child keeps running
  unlet g:webmarks_test.cmd_runner
  let g:webmarks_browser_cmd = ['sh', '-c', 'sleep 3 & exit 0', 'sh']
  let l:start = reltime()
  call s:assert.true(webmarks#deps#browser#open('https://a.example').ok)
  call s:assert.true(reltimefloat(reltime(l:start)) < 1.5)
  let g:webmarks_browser_cmd = ['sh', '-c', 'exit 5', 'sh']
  call s:assert.equals(webmarks#deps#browser#open('https://a.example').code, 'browser_failed')
endfunction
