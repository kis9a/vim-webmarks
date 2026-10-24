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

let s:upper = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
let s:lower = 'abcdefghijklmnopqrstuvwxyz'

" The end of a '<title' / '<head' opening tag that starts at {start} in
" {low}: the index just after its '>', or -1 when it is not such a tag
" (e.g. '<titles' or no closing '>').
function! s:tag_end(low, start, name) abort
  let l:after = a:start + strlen(a:name) + 1
  let l:c = a:low[l:after]
  if l:c ==# '>'
    return l:after + 1
  endif
  if l:c !~# '\s'
    return -1
  endif
  let l:gt = stridx(a:low, '>', l:after)
  return l:gt < 0 ? -1 : l:gt + 1
endfunction

" extract_title(html) -> String or v:null
"   <head> first (to skip SVG titles), the last non-empty <title>, tags
"   removed, entities decoded, whitespace squeezed, trimmed.
"   Linear: positions are found with stridx() on a copy whose ASCII letters
"   are lower-cased by tr() (byte offsets stay the same), and titles are
"   tried from the last '</title>' backwards, so broken markup such as
"   thousands of unclosed '<title' costs one pass, not one per candidate
"   (the regex version took 29 s on 150 KB).
function! webmarks#domain#html#extract_title(html) abort
  if type(a:html) != v:t_string || a:html ==# ''
    return v:null
  endif
  let l:text = a:html
  let l:low = tr(l:text, s:upper, s:lower)
  " prefer <head> .. </head>
  let l:h = stridx(l:low, '<head')
  while l:h >= 0
    let l:body = s:tag_end(l:low, l:h, 'head')
    if l:body > 0
      let l:he = stridx(l:low, '</head>', l:body)
      if l:he >= 0
        let l:text = strpart(l:text, l:h, l:he + 7 - l:h)
        let l:low = strpart(l:low, l:h, l:he + 7 - l:h)
      endif
      break
    endif
    let l:h = stridx(l:low, '<head', l:h + 1)
  endwhile
  let l:close = strridx(l:low, '</title>')
  while l:close >= 0
    " the opening tag closest before this close
    let l:open = strridx(l:low, '<title', l:close)
    while l:open >= 0 && s:tag_end(l:low, l:open, 'title') < 0
      let l:open = l:open > 0 ? strridx(l:low, '<title', l:open - 1) : -1
    endwhile
    if l:open < 0
      return v:null
    endif
    let l:from = s:tag_end(l:low, l:open, 'title')
    if l:from <= l:close
      let l:content = strpart(l:text, l:from, l:close - l:from)
      let l:content = substitute(l:content, '<[^>]*>', '', 'g')
      " a title is a line of text; do not decode megabytes of it
      let l:content = strcharpart(l:content, 0, 4096)
      let l:content = webmarks#domain#html#decode_entities(l:content)
      let l:content = trim(substitute(l:content, '\_s\+', ' ', 'g'))
      if l:content !=# ''
        return l:content
      endif
    endif
    let l:close = l:open > 0 ? strridx(l:low, '</title>', l:open - 1) : -1
  endwhile
  return v:null
endfunction

let &cpoptions = s:save_cpo
unlet s:save_cpo
