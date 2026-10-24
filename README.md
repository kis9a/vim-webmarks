# vim-webmarks

Web bookmarks in Vim and Neovim: add a URL, organise it in two levels of
folders, find it in a tree or with fzf, and open it in your browser with
one key. The order follows frecency (rupa/z), favorites first.

```
★ Vim help
  Neovim docs
Dev/
  Docs/
      MDN
    GitHub
```

- Add with `:WebmarksAdd <url>`; the page title is fetched in the
  background (never blocking Vim) and becomes the name.
- `<CR>` opens the bookmark and records the launch; the list is ordered by
  frecency, recency or name.
- Edit the whole tree as text (`i`) and apply it with `:w`.
- One JSON file, one line per bookmark, safe to share between several Vims.
- Legacy Vimscript only. Vim 8.2+ / Neovim 0.8+.

## Installation

With [vim-plug](https://github.com/junegunn/vim-plug):

```vim
Plug 'kis9a/vim-webmarks'
```

Optional:

- `curl` and job support (`+job` in Vim) for page titles
- [fzf](https://github.com/junegunn/fzf) with its Vim plugin for
  `:WebmarksSearch`

## Features

### Commands

| Command | Description |
|---|---|
| `:Webmarks` | Open the tree (or go to its window) |
| `:WebmarksToggle` | Open or close the tree |
| `:WebmarksAdd [url] [name...]` | Add a bookmark; no name = fetch the title, no URL = ask |
| `:WebmarksSearch` | Pick a bookmark with fzf and open it |
| `:WebmarksEdit` | Open the tree in edit mode |

### Keys in the tree

| Key | Action | Key | Action |
|---|---|---|---|
| `<CR>` | open / toggle fold | `S` | sort by recent |
| `a` | add bookmark | `~` | sort by name |
| `A` | add folder | `F` | sort by frecency |
| `r` | rename | `P` | toggle favorites first |
| `e` | change URL | `T` | toggle tree / flat |
| `m` | move to folder | `s` | fzf search |
| `d` | delete | `R` | reload the file |
| `*` | toggle favorite | `i` | edit mode |
| `t` | fetch title again | `q` | close |
| `y` | yank URL | `g?` | list keys |

Every key is a `<Plug>(webmarks-…)` mapping; see `:help webmarks-mappings`.

### Edit mode

`i` shows each bookmark with its URL. Rename, re-indent, move lines, delete
lines, add `  name  https://…` or `Folder/` lines, toggle `★ ` — then `:w`.
All changes are applied at once; on any error nothing is saved and the
cursor goes to the line. `:e!` discards. See `:help webmarks-edit`.

### Functions

| Function | Description |
|---|---|
| `webmarks#open()` | `:Webmarks` |
| `webmarks#toggle()` | `:WebmarksToggle` |
| `webmarks#add(url, name, folder_id)` | Add a bookmark (`folder_id`: `'f3'` or `v:null`) |
| `webmarks#search()` | `:WebmarksSearch` |
| `webmarks#edit()` | `:WebmarksEdit` |
| `webmarks#reload()` | Read the file again |

### Options

| Option | Default | Description |
|---|---|---|
| `g:webmarks_file` | `$XDG_DATA_HOME/webmarks/bookmarks.json` | Data file (`~/.local/share/…` without XDG) |
| `g:webmarks_open` | `'vsplit'` | `'vsplit'`, `'split'`, `'edit'` or `'tab'` |
| `g:webmarks_width` | `40` | Width of the vsplit window |
| `g:webmarks_default_sort` | `'frecency'` | `'frecency'`, `'recent'` or `'name'` |
| `g:webmarks_favorite_first` | `1` | Favorites before the others |
| `g:webmarks_default_view` | `'tree'` | `'tree'` or `'flat'` |
| `g:webmarks_browser_cmd` | detected | List `['firefox', '--new-tab']` or an executable name |
| `g:webmarks_fetch_title` | `1` | `0` = never fetch titles automatically |
| `g:webmarks_no_default_mappings` | `0` | `1` = map no keys in the tree |

## Configuration

### Key Mappings (Example)

Map to the commands (they work even while the plugin is lazily loaded):

```vim
nnoremap <silent> <Leader>bb :<C-u>WebmarksToggle<CR>
nnoremap <silent> <Leader>bs :<C-u>WebmarksSearch<CR>
nnoremap <silent> <Leader>ba :<C-u>WebmarksAdd<CR>

augroup my_webmarks
  autocmd!
  " your own key in the tree
  autocmd FileType webmarks nmap <buffer> o <Plug>(webmarks-open)
augroup END
```

### Privacy

Adding a bookmark without a name sends one HTTP(S) GET to that URL to read
its `<title>` (user agent `vim-webmarks/1.0`, http/https only, at most
1 MiB). This is on by default; turn it off with
`let g:webmarks_fetch_title = 0`. See `:help webmarks-privacy`.

### Limitations

Two Vims writing within the same second can lose one change; Windows is
best effort; titles of non-UTF-8 pages are not converted; URLs must be
ASCII (percent-encode the rest). See `:help webmarks-limitations`.

## Development

```sh
make deps    # themis, vimlparser, vimlint (pinned)
make test    # Vim and Neovim
make lint
```

## LICENSE

MIT. See [LICENSE](LICENSE).
