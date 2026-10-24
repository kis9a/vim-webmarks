scriptencoding utf-8
" ui/prompt.vim - interactive input
"
" Never calls input()/inputlist() without a terminal: headless Vim ends
" the script and headless Neovim blocks forever. Tests inject answers via
" g:webmarks_test.prompt = {text, choose_folder, confirm}.

let s:save_cpo = &cpoptions
set cpoptions&vim

" What Neovim's input() returns for <Esc> / CTRL-C when asked to.
let s:cancel = "\x1b"

function! s:ok(value) abort
  return {'ok': v:true, 'code': '', 'error': '', 'changed': v:false, 'value': a:value}
endfunction

function! s:err(code, msg) abort
  return {'ok': v:false, 'code': a:code, 'error': a:msg, 'changed': v:false}
endfunction

function! s:cancelled() abort
  return s:err('cancelled', '')
endfunction

function! s:no_tty() abort
  return s:err('no_tty', 'interactive input is not available')
endfunction

function! s:injected(name) abort
  let l:test = get(g:, 'webmarks_test', {})
  let l:p = type(l:test) == v:t_dict ? get(l:test, 'prompt', v:null) : v:null
  if type(l:p) == v:t_dict && has_key(l:p, a:name)
    return l:p[a:name]
  endif
  return v:null
endfunction

" An injected answer: a Result dict, or a plain value.
function! s:answer(raw) abort
  if type(a:raw) == v:t_dict && has_key(a:raw, 'ok')
    return a:raw
  endif
  return s:ok(a:raw)
endfunction

function! webmarks#ui#prompt#has_tty() abort
  return has('ttyin') || has('gui_running')
        \ || (has('nvim') && exists('*nvim_list_uis') && !empty(nvim_list_uis()))
endfunction

" text(prompt, default) -> Result {value}
"   An empty answer is a value (''), not a cancel: <Esc> in Vim's input()
"   returns '' too. CTRL-C cancels (and <Esc> as well on Neovim).
function! webmarks#ui#prompt#text(prompt, default) abort
  let l:F = s:injected('text')
  if l:F isnot v:null
    return s:answer(call(l:F, [a:prompt, a:default]))
  endif
  if !webmarks#ui#prompt#has_tty()
    return s:no_tty()
  endif
  redraw
  try
    if has('nvim')
      let l:v = input({'prompt': a:prompt, 'default': a:default, 'cancelreturn': s:cancel})
      if l:v ==# s:cancel
        return s:cancelled()
      endif
    else
      let l:v = input(a:prompt, a:default)
    endif
  catch /^Vim:Interrupt$/
    return s:cancelled()
  endtry
  return s:ok(l:v)
endfunction

" choose_folder(data, exclude_id) -> Result {value: folder id or v:null}
"   exclude_id and its descendants are not offered (moving a folder).
function! webmarks#ui#prompt#choose_folder(data, exclude_id) abort
  let l:F = s:injected('choose_folder')
  if l:F isnot v:null
    return s:answer(call(l:F, [a:data, a:exclude_id]))
  endif
  if !webmarks#ui#prompt#has_tty()
    return s:no_tty()
  endif
  let l:skip = {}
  if a:exclude_id isnot v:null
    let l:skip[a:exclude_id] = 1
    for l:f in webmarks#domain#folder#descendants(a:data.folders, a:exclude_id)
      let l:skip[l:f.id] = 1
    endfor
  endif
  let l:choices = [v:null]
  let l:lines = ['Move to:', '1. / (root)']
  for l:top in webmarks#domain#folder#children(a:data.folders, v:null)
    for l:f in [l:top] + webmarks#domain#folder#children(a:data.folders, l:top.id)
      if !has_key(l:skip, l:f.id)
        call add(l:choices, l:f.id)
        call add(l:lines, printf('%d. %s/', len(l:choices),
              \ webmarks#domain#folder#path(a:data.folders, l:f.id)))
      endif
    endfor
  endfor
  redraw
  try
    let l:n = inputlist(l:lines)
  catch /^Vim:Interrupt$/
    return s:cancelled()
  endtry
  " 0 = nothing chosen (<Esc>, <CR> on an empty line)
  if l:n < 1 || l:n > len(l:choices)
    return s:cancelled()
  endif
  return s:ok(l:choices[l:n - 1])
endfunction

" confirm(msg) -> Bool. False without a terminal.
function! webmarks#ui#prompt#confirm(msg) abort
  let l:F = s:injected('confirm')
  if l:F isnot v:null
    return call(l:F, [a:msg]) ? v:true : v:false
  endif
  if !webmarks#ui#prompt#has_tty()
    return v:false
  endif
  redraw
  try
    return confirm(a:msg, "&Yes\n&No", 2) == 1
  catch /^Vim:Interrupt$/
    return v:false
  endtry
endfunction

let &cpoptions = s:save_cpo
unlet s:save_cpo
