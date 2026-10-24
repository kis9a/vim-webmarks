scriptencoding utf-8
" domain/html.vim - page title extraction
"
" Ported from mdlink (mdlink#core#extractTitleFromHtml / decodeHtmlEntity,
" same author, MIT). The behaviour is kept identical, including the
" double decode of "&amp;lt;" (-> "<"); test/domain_html.vim carries the
" original tests. Pure: no buffers, files, commands, clock or g:.

let s:save_cpo = &cpoptions
set cpoptions&vim

" decode_entities(text) -> String
"   The named entities are replaced first, in the original order (so
"   "&amp;lt;" still becomes "<"), then numeric references in one pass.
"   Changes from the original: one substitute() per kind instead of one per
"   reference (the original was quadratic and looped forever on "&#38;",
"   whose decoded "&" means "the match" in a replacement), and code points
"   that are not characters (0, surrogates, > U+10FFFF) are dropped.
function! webmarks#domain#html#decode_entities(text) abort
  let l:result = a:text
  let l:result = substitute(l:result, '&amp;', '\&', 'g')
  let l:result = substitute(l:result, '&lt;', '<', 'g')
  let l:result = substitute(l:result, '&gt;', '>', 'g')
  let l:result = substitute(l:result, '&quot;', '"', 'g')
  let l:result = substitute(l:result, '&#39;', "'", 'g')
  let l:result = substitute(l:result, '&nbsp;', ' ', 'g')
  let l:result = substitute(l:result, '&#\(\d\+\);', '\=s:char(submatch(1), 10)', 'g')
  let l:result = substitute(l:result, '\c&#x\(\x\+\);', '\=s:char(submatch(1), 16)', 'g')
  return l:result
endfunction

function! s:char(digits, base) abort
  " more than 7 digits cannot be a code point (and would overflow)
  if strlen(substitute(a:digits, '^0\+', '', '')) > 7
    return ''
  endif
  let l:n = str2nr(a:digits, a:base)
  if l:n <= 0 || (l:n >= 0xd800 && l:n <= 0xdfff) || l:n > 0x10ffff
    return ''
  endif
  return nr2char(l:n, 1)
endfunction

" extract_title(html) -> String or v:null
"   <head> first (to skip SVG titles), the last non-empty <title>, tags
"   removed, entities decoded, whitespace squeezed, trimmed.
function! webmarks#domain#html#extract_title(html) abort
  if type(a:html) != v:t_string || a:html ==# ''
    return v:null
  endif

  let l:target = a:html
  let l:head = matchstr(a:html, '\c<head\%(\s\+[^>]*\)\?>\_.\{-}</head>')
  if l:head !=# ''
    let l:target = l:head
  endif

  let l:pattern = '\c<title\%(\s\+[^>]*\)\?>\s*\(\_.\{-}\)\s*</title>'
  let l:last = v:null
  let l:pos = 0
  while 1
    let [l:matched, l:start, l:end] = matchstrpos(l:target, l:pattern, l:pos)
    if l:start == -1
      break
    endif
    let l:content = matchstr(l:matched, '\c<title\%(\s\+[^>]*\)\?>\s*\zs\_.\{-}\ze\s*</title>')
    let l:content = substitute(l:content, '<[^>]*>', '', 'g')
    " a title is a line of text; do not decode megabytes of it
    let l:content = strcharpart(l:content, 0, 4096)
    let l:content = webmarks#domain#html#decode_entities(l:content)
    let l:content = substitute(l:content, '\_s\+', ' ', 'g')
    let l:content = trim(l:content)
    if l:content !=# ''
      let l:last = l:content
    endif
    let l:pos = l:end
  endwhile

  return l:last
endfunction

let &cpoptions = s:save_cpo
unlet s:save_cpo
