scriptencoding utf-8
" domain/text.vim - sanitizing display names and folder names
"
" Pure: no buffers, files, commands, clock or g: variables.

let s:save_cpo = &cpoptions
set cpoptions&vim

let s:max_chars = 200

" Cleaning works on code points (str2list), not on regex characters: the
" two editors disagree on which characters are "composing", and a regex
" skips those, so a regex-based cleaner was neither the same in Vim and
" Neovim nor stable when applied twice (a name accepted once could be
" refused when the file was read back).

" -> space: C0/C1 controls, DEL, Unicode spaces, line/paragraph separator
function! s:is_space(cp) abort
  return a:cp < 0x20 || (a:cp >= 0x7f && a:cp <= 0x9f) || a:cp == 0xa0
        \ || a:cp == 0x1680 || (a:cp >= 0x2000 && a:cp <= 0x200a)
        \ || a:cp == 0x2028 || a:cp == 0x2029 || a:cp == 0x202f
        \ || a:cp == 0x205f || a:cp == 0x3000
endfunction

" -> dropped: zero-width space, bidi marks and controls, BOM, soft hyphen,
" CGJ, Arabic letter mark, Hangul / Braille fillers, Mongolian vowel
" separator, word joiner .. invisible plus, interlinear annotation, tag
" characters, and the edit-mode id markers. ZWJ / ZWNJ (U+200C/D) and
" variation selectors stay: emoji and many scripts need them.
function! s:is_dropped(cp) abort
  return a:cp == 0x200b || a:cp == 0x200e || a:cp == 0x200f
        \ || (a:cp >= 0x202a && a:cp <= 0x202e) || (a:cp >= 0x2066 && a:cp <= 0x2069)
        \ || a:cp == 0xfeff || a:cp == 0xad || a:cp == 0x34f || a:cp == 0x61c
        \ || a:cp == 0x115f || a:cp == 0x1160 || a:cp == 0x180e
        \ || (a:cp >= 0x2060 && a:cp <= 0x2064) || a:cp == 0x2800 || a:cp == 0x3164
        \ || a:cp == 0xffa0 || (a:cp >= 0xfff9 && a:cp <= 0xfffb)
        \ || (a:cp >= 0xe0000 && a:cp <= 0xe007f)
        \ || a:cp == 0x27e8 || a:cp == 0x27e9
endfunction

" zero-width on their own: combining marks, joiners, variation selectors
function! s:is_zero_width(cp) abort
  return (a:cp >= 0x300 && a:cp <= 0x36f) || (a:cp >= 0x1ab0 && a:cp <= 0x1aff)
        \ || (a:cp >= 0x1dc0 && a:cp <= 0x1dff) || (a:cp >= 0x20d0 && a:cp <= 0x20ff)
        \ || (a:cp >= 0xfe00 && a:cp <= 0xfe0f) || (a:cp >= 0xfe20 && a:cp <= 0xfe2f)
        \ || a:cp == 0x200c || a:cp == 0x200d || (a:cp >= 0xe0100 && a:cp <= 0xe01ef)
endfunction

function! s:empty() abort
  return s:err('empty_name', 'name is empty after removing control characters')
endfunction

" sanitize(s) -> Result {value}
"   invalid_text: not valid UTF-8 / not a String
"   empty_name:   nothing visible left after cleaning
" Stable: sanitize(sanitize(s).value) gives the same value, on both editors.
function! webmarks#domain#text#sanitize(s) abort
  if type(a:s) != v:t_string || !webmarks#domain#text#is_utf8(a:s)
    return s:err('invalid_text', 'text contains invalid UTF-8')
  endif
  if a:s !~# '[^\x01-\x7f]' && strlen(a:s) == strchars(a:s)
    " ASCII (most names): controls and DEL become spaces; bytes = chars
    let l:v = trim(substitute(a:s, '[\x01-\x20\x7f]\+', ' ', 'g'), ' ')
    if strlen(l:v) > s:max_chars
      let l:v = trim(strpart(l:v, 0, s:max_chars), ' ')
    endif
    if l:v ==# ''
      return s:empty()
    endif
    return {'ok': v:true, 'code': '', 'error': '', 'changed': v:true, 'value': l:v}
  else
    let l:cps = []
    for l:cp in str2list(a:s)
      if s:is_space(l:cp)
        call add(l:cps, 0x20)
      elseif !s:is_dropped(l:cp)
        call add(l:cps, l:cp)
      endif
    endfor
  endif
  let l:v = trim(substitute(list2str(l:cps), ' \+', ' ', 'g'), ' ')
  let l:cps = str2list(l:v)
  if len(l:cps) > s:max_chars
    let l:cps = l:cps[: s:max_chars - 1]
    let l:v = trim(list2str(l:cps), ' ')
    let l:cps = str2list(l:v)
  endif
  if l:v ==# '' || empty(filter(copy(l:cps), '!s:is_zero_width(v:val)'))
    return s:empty()
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
  " pure ASCII. Both checks: Neovim's regex skips a composing character,
  " and strchars() counts a stray byte as one character.
  if a:s !~# '[^\x01-\x7f]' && strlen(a:s) == strchars(a:s)
    return v:true
  endif
  for l:c in split(a:s, '\zs')
    if strlen(l:c) == 1 && char2nr(l:c) >= 128
      return v:false
    endif
  endfor
  " encoded surrogates and code points above U+10FFFF: Vim reads them as one
  " character, Neovim's json_encode()/json_decode() reject them. Checked on
  " code points, as Neovim may attach a code point to the previous character.
  let l:cps = str2list(a:s)
  if !empty(filter(copy(l:cps), '(v:val >= 0xd800 && v:val <= 0xdfff) || v:val > 0x10ffff'))
    return v:false
  endif
  " over-long encodings (e.g. 0xe0 0x80 0xaf for '/'): encoding the code
  " points again gives the shortest form, so the bytes differ
  return list2str(l:cps) ==# a:s ? v:true : v:false
endfunction

function! s:err(code, msg) abort
  return {'ok': v:false, 'code': a:code, 'error': a:msg, 'changed': v:false}
endfunction

let &cpoptions = s:save_cpo
unlet s:save_cpo
