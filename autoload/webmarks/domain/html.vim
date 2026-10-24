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
function! webmarks#domain#html#decode_entities(text) abort
  let l:result = a:text
  let l:result = substitute(l:result, '&amp;', '\&', 'g')
  let l:result = substitute(l:result, '&lt;', '<', 'g')
  let l:result = substitute(l:result, '&gt;', '>', 'g')
  let l:result = substitute(l:result, '&quot;', '"', 'g')
  let l:result = substitute(l:result, '&#39;', "'", 'g')
  let l:result = substitute(l:result, '&nbsp;', ' ', 'g')

  while 1
    let l:match = matchlist(l:result, '&#\(\d\+\);')
    if empty(l:match)
      break
    endif
    let l:char = nr2char(str2nr(l:match[1]))
    let l:result = substitute(l:result, '&#' . l:match[1] . ';', escape(l:char, '\&~'), '')
  endwhile

  while 1
    let l:match = matchlist(l:result, '\c&#x\(\x\+\);')
    if empty(l:match)
      break
    endif
    let l:char = nr2char(str2nr(l:match[1], 16))
    let l:result = substitute(l:result, '\c&#x' . l:match[1] . ';', escape(l:char, '\&~'), '')
  endwhile

  return l:result
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
