scriptencoding utf-8
" domain/text.vim - sanitizing display names and folder names
"
" Pure: no buffers, files, commands, clock or g: variables.

let s:save_cpo = &cpoptions
set cpoptions&vim

let s:max_chars = 200

" C0 controls, DEL and C1 controls become a space (so "a\tb" stays two
" words); invisible format characters (zero-width, bidi) are dropped.
let s:control = '[[:cntrl:]\x7f\u0080-\u009f]'
let s:invisible = '[\u200b-\u200f\u202a-\u202e\u2066-\u2069\u2028\u2029\ufeff]'

" sanitize(s) -> Result {value}
"   invalid_text: not valid UTF-8 / not a String
"   empty_name:   nothing left after cleaning
function! webmarks#domain#text#sanitize(s) abort
  if type(a:s) != v:t_string
    return s:err('invalid_text', 'text contains invalid UTF-8')
  endif
  if !webmarks#domain#text#is_utf8(a:s)
    return s:err('invalid_text', 'text contains invalid UTF-8')
  endif
  let l:v = substitute(a:s, s:control, ' ', 'g')
  let l:v = substitute(l:v, s:invisible, '', 'g')
  let l:v = trim(substitute(l:v, '\s\+', ' ', 'g'))
  if strchars(l:v) > s:max_chars
    let l:v = trim(strcharpart(l:v, 0, s:max_chars))
  endif
  if l:v ==# ''
    return s:err('empty_name', 'name is empty after removing control characters')
  endif
  return {'ok': v:true, 'code': '', 'error': '', 'changed': v:true, 'value': l:v}
endfunction

" is_utf8(s) -> Bool: true when s has no invalid byte sequences.
" This runs before any substitute(): the regex engine reads a stray byte
" such as 0x82 as U+0082, so a C1 pattern would silently "fix" it. Both
" editors split an invalid sequence into 1-byte items >= 0x80, which a
" valid character never is.
function! webmarks#domain#text#is_utf8(s) abort
  if type(a:s) != v:t_string
    return v:false
  endif
  if a:s !~# '[^\x01-\x7f]'
    return v:true
  endif
  for l:c in split(a:s, '\zs')
    if strlen(l:c) == 1 && char2nr(l:c) >= 128
      return v:false
    endif
  endfor
  return v:true
endfunction

function! s:err(code, msg) abort
  return {'ok': v:false, 'code': a:code, 'error': a:msg, 'changed': v:false}
endfunction

let &cpoptions = s:save_cpo
unlet s:save_cpo
