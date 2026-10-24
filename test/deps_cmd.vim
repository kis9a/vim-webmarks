scriptencoding utf-8
let s:suite = themis#suite('deps_cmd')
let s:assert = themis#helper('assert')

function! s:suite.before_each() abort
  let s:dir = WebmarksTestReset()
  let s:seen = []
endfunction

function! s:suite.after_each() abort
  call webmarks#deps#cmd#_set_list_argv(-1)
  call delete(s:dir, 'rf')
endfunction

function! s:stub(argv, opts) abort
  call add(s:seen, a:argv)
  return {'exit_code': 7, 'stdout': 'stubbed'}
endfunction

function! s:suite.stub_wins_even_for_missing_command() abort
  let g:webmarks_test.cmd_runner = function('s:stub')
  let l:r = webmarks#deps#cmd#run(['webmarks-no-such-command', 'x'], {})
  call s:assert.equals(s:seen, [['webmarks-no-such-command', 'x']])
  call s:assert.equals([l:r.ok, l:r.exit_code, l:r.stdout], [v:false, 7, 'stubbed'])
endfunction

function! s:suite.not_executable() abort
  let l:r = webmarks#deps#cmd#run(['webmarks-no-such-command'], {})
  call s:assert.equals(l:r.code, 'not_executable')
  call s:assert.equals(l:r.exit_code, -1)
  call s:assert.equals(webmarks#deps#cmd#run([], {}).code, 'not_executable')
  call s:assert.equals(webmarks#deps#cmd#run('ls', {}).code, 'not_executable')
endfunction

function! s:check_literal() abort
  let l:marker = s:dir . '/pwned'
  let l:arg = 'a > ' . l:marker . '; touch ' . l:marker . ' $(touch ' . l:marker . ') `x` "q" ''s'''
  let l:r = webmarks#deps#cmd#run(['printf', '%s', l:arg], {})
  call s:assert.true(l:r.ok, string(l:r))
  call s:assert.equals(l:r.stdout, l:arg)
  call s:assert.false(filereadable(l:marker))
endfunction

function! s:suite.metacharacters_pass_literally_list_path() abort
  call s:check_literal()
endfunction

function! s:suite.metacharacters_pass_literally_shell_path() abort
  " the Vim 8.2 .. 9.1 path: shellescape()d and run through the shell
  call webmarks#deps#cmd#_set_list_argv(0)
  call s:check_literal()
endfunction

function! s:suite.exit_code() abort
  let l:r = webmarks#deps#cmd#run(['sh', '-c', 'exit 4'], {})
  call s:assert.equals([l:r.ok, l:r.exit_code], [v:false, 4])
endfunction
