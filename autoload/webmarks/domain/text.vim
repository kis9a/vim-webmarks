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

" code point -> 32 (becomes a space) or -1 (dropped); others are kept.
" Spaces: C0/C1 controls, DEL, Unicode spaces, line/paragraph separators.
" Dropped: zero-width space, bidi marks and controls, BOM, soft hyphen,
" CGJ, Arabic letter mark, Hangul / Braille fillers, Mongolian vowel
" separator, word joiner .. invisible plus, interlinear annotation, tag
" characters and the edit-mode id markers. ZWJ / ZWNJ (U+200C/D) and
" variation selectors stay: emoji and many scripts need them.
let s:map = {}
for s:cp in range(0x00, 0x1f) + range(0x7f, 0xa0) + [0x1680] + range(0x2000, 0x200a)
      \ + [0x2028, 0x2029, 0x202f, 0x205f, 0x3000]
  let s:map[s:cp] = 32
endfor
for s:cp in [0x200b, 0x200e, 0x200f, 0xfeff, 0xad, 0x34f, 0x61c, 0x115f, 0x1160, 0x180e,
      \ 0x2800, 0x3164, 0xffa0, 0x27e8, 0x27e9]
      \ + range(0x202a, 0x202e) + range(0x2066, 0x2069) + range(0x2060, 0x2064)
      \ + range(0xfff9, 0xfffb) + range(0xe0000, 0xe007f)
  let s:map[s:cp] = -1
endfor
unlet s:cp

" zero-width on their own: combining marks, joiners, variation selectors
function! s:is_zero_width(cp) abort
  return (a:cp >= 0x300 && a:cp <= 0x36f) || (a:cp >= 0x1ab0 && a:cp <= 0x1aff)
        \ || (a:cp >= 0x1dc0 && a:cp <= 0x1dff) || (a:cp >= 0x20d0 && a:cp <= 0x20ff)
        \ || (a:cp >= 0xfe00 && a:cp <= 0xfe0f) || (a:cp >= 0xfe20 && a:cp <= 0xfe2f)
        \ || a:cp == 0x200c || a:cp == 0x200d || (a:cp >= 0xe0100 && a:cp <= 0xe01ef)
endfunction

" the code points of s:is_zero_width(), as a table: filter() with a short
" has_key() is much cheaper than the range test per code point
let s:zw = {}
for s:cp in range(0x300, 0x36f) + range(0x1ab0, 0x1aff) + range(0x1dc0, 0x1dff)
      \ + range(0x20d0, 0x20ff) + range(0xfe00, 0xfe0f) + range(0xfe20, 0xfe2f)
      \ + [0x200c, 0x200d] + range(0xe0100, 0xe01ef)
  let s:zw[s:cp] = 1
endfor
unlet s:cp

function! s:cap_zero_width(cps) abort
  let l:out = []
  let l:run = 0
  for l:cp in a:cps
    if s:is_zero_width(l:cp)
      let l:run += 1
      if l:run > 4
        continue
      endif
    else
      let l:run = 0
    endif
    call add(l:out, l:cp)
  endfor
  return l:out
endfunction

function! s:empty() abort
  return s:err('empty_name', 'name is empty after removing control characters')
endfunction

" sanitize(s) -> Result {value}
"   invalid_text: not valid UTF-8 / not a String
"   empty_name:   nothing visible left after cleaning
" Non-ASCII text is cleaned as a list of code points: the editors disagree
" on which characters are "composing" (and regex, trim() and substitute()
" treat a base character and its composing marks as one), so text-level
" cleaning was neither the same in Vim and Neovim nor stable when applied
" twice. On code points, sanitize(sanitize(s).value) == sanitize(s).value
" in both editors.
function! webmarks#domain#text#sanitize(s) abort
  if type(a:s) != v:t_string
    return s:err('invalid_text', 'name must be text')
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
  endif
  let l:cps = s:code_points(a:s)
  if l:cps is v:null
    return s:err('invalid_text', 'text contains invalid UTF-8')
  endif
  call filter(map(l:cps, 'get(s:map, v:val, v:val)'), 'v:val >= 0')
  " collapse and trim spaces on the decimal text (plain ASCII, so the regex
  " sees exactly one item per code point)
  let l:text = substitute(',' . join(l:cps, ',') . ',', ',32\%(,32\)\+,', ',32,', 'g')
  let l:text = substitute(l:text, '^,32,', ',', '')
  let l:text = substitute(l:text, ',32,$', ',', '')
  let l:cps = map(split(l:text, ','), 'str2nr(v:val)')
  " at most 4 zero-width code points after one base character ("zalgo"
  " names would otherwise pile up in one cell)
  if len(filter(copy(l:cps), 'has_key(s:zw, v:val)')) > 4
    let l:cps = s:cap_zero_width(l:cps)
  endif
  if len(l:cps) > s:max_chars
    let l:cps = l:cps[: s:max_chars - 1]
    while !empty(l:cps) && l:cps[-1] == 32
      call remove(l:cps, -1)
    endwhile
  endif
  " nothing visible: only zero-width code points (checked lazily: almost
  " every name starts with a visible one)
  if empty(l:cps) || (s:is_zero_width(l:cps[0])
        \ && empty(filter(copy(l:cps), '!s:is_zero_width(v:val)')))
    return s:empty()
  endif
  return {'ok': v:true, 'code': '', 'error': '', 'changed': v:true, 'value': list2str(l:cps)}
endfunction

" is_utf8(s) -> Bool: valid UTF-8 that both editors read back the same.
function! webmarks#domain#text#is_utf8(s) abort
  return type(a:s) == v:t_string && s:code_points(a:s) isnot v:null
endfunction

" The code points of {s}, or v:null when {s} is not valid UTF-8:
" - a stray byte (str2list() gives its value, e.g. 0x82) and an over-long
"   form (0xe0 0x80 0xaf for '/') do not encode back to the same bytes;
" - an encoded surrogate or a value above U+10FFFF encodes back unchanged
"   in Vim, but Neovim's json_encode()/json_decode() reject it.
" (Not regex-based: the regex engine reads a stray 0x82 as U+0082.)
function! s:code_points(s) abort
  let l:cps = str2list(a:s)
  if list2str(l:cps) !=# a:s
    return v:null
  endif
  if !empty(filter(copy(l:cps), '(v:val >= 0xd800 && v:val <= 0xdfff) || v:val > 0x10ffff'))
    return v:null
  endif
  return l:cps
endfunction

function! s:err(code, msg) abort
  return {'ok': v:false, 'code': a:code, 'error': a:msg, 'changed': v:false}
endfunction

let &cpoptions = s:save_cpo
unlet s:save_cpo
