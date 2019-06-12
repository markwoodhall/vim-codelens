if exists('g:loaded_codelens') || &cp
  finish
endif

let g:loaded_codelens = 1
let g:codelens_namespace = nvim_create_namespace('codelens')

if !exists('g:codelens_auto')
  let g:codelens_auto = 0
endif

if !exists('g:codelens_show_references')
  let g:codelens_show_references = 1
endif

if !exists('g:codelens_author_strategy')
  let g:codelens_author_strategy = 'prolific'
endif

function! s:most_prolific(list) abort
  let prolific = ''
  let seen = {}
  for e in a:list
    let auth = split(e, 'Date:')[0]
    let auth = trim(auth)
    if !has_key(seen, auth)
      let seen[auth] = 1
    else
      let seen[auth] = seen[auth] + 1
    endif
  endfor
  let last_value = 0
  for [key, value] in items(seen)
    if value > last_value
      let last_value = value
      let prolific = key
    endif
  endfor
  return prolific
endfunction

function! s:unique(list) abort
  let seen = {}
  let uniques = []
  for e in a:list
    let k = string(e)
    if !has_key(seen, k)
      let seen[k] = 1
      call add(uniques, e)
    endif
  endfor
  return uniques
endfunction

function! s:process_git_log(job_id, data, event) dict
  if a:event == 'stdout'
    let data = a:data[0:-2]
    if len(data) >= 1
      let parts = split(data[0], '#')
      if len(parts) > 1
        let authors = split(parts[1], 'Author:')

        let named_authors = []
        for a in authors
          let auth = split(a, 'Date:')[0]
          let named_authors += [trim(auth)]
        endfor

        let author_count = len(s:unique(named_authors)) - 1

        let message = ''
        if len(authors) > 0

          let latest_author_and_date = authors[0]

          let author = split(split(latest_author_and_date, 'Date:')[0], '<')[0]

          if g:codelens_author_strategy == 'prolific'
            let author = s:most_prolific(authors)
          endif

          let date = join(split(split(latest_author_and_date, 'Date:')[1], ' ')[0:-2], ' ')
          let message = trim(date) . ' by ' . trim(author)

          if author_count == 1
            let message = message . ' and 1 other'
          elseif author_count > 1
            let message = message . ' and ' . author_count . ' others'
          endif

          if g:codelens_show_references == 1
            if exists('b:codelens_func')
              let references = parts[2]
              if references > 1
                let message = message . ', ' . references . ' references' 
              elseif references == 1
                let message = message . ', ' . references . ' reference' 
              endif
            endif
          endif
        endif

        let line = parts[0]

        if getline(line) =~ b:codelens_target
          if line > 1 && substitute(getline(line-1), '\s', '', 'g') == ''
            silent! call nvim_buf_set_virtual_text(nvim_get_current_buf(), g:codelens_namespace, line-2, [[message, 'Comment']], {})
          else
            silent! call nvim_buf_set_virtual_text(nvim_get_current_buf(), g:codelens_namespace, line-1, [[message, 'Comment']], {})
          endif
        endif
      endif
    endif
  endif
endfunction

function! codelens#lens()
  let filename = expand('%')
  call nvim_buf_clear_highlight(nvim_get_current_buf(), g:codelens_namespace, 0, -1)
  let num = 1
  for line in getline(1, line('$'))
    if line =~ b:codelens_target
      let s:callbacks = {
      \ 'on_stdout': function('s:process_git_log')
      \ }

      let num_end_line = num + 1
      for end_line in getline(num_end_line, line('$'))
        if end_line =~ b:codelens_scope_end
          let num_end_line = num_end_line - 2
          break
        endif
        let num_end_line = num_end_line + 1
      endfor
      let cmd = 'echo "' . num . '"#$(git blame ' . filename . ' -L ' . num . ',' . num_end_line . ' --date=relative  | cut -d "(" -f2 | cut -d ")" -f1 | sed  "s/^/Author: /" | sed "s/\([0-9]\+ [a-z]\+ ago\)/\nDate: \1/")'

      if exists('b:codelens_func')
        let func = trim(matchstr(line, b:codelens_func))

        let clean_line = substitute(line, '[', '\\[', 'g')
        let clean_line = substitute(clean_line, ']', '\\]', 'g')

        let cmd = cmd . '#$(git grep --not -e "'. clean_line .'" --and -e "'.func.'" | wc -l);'
      endif

      echomsg cmd
      let gitlogjob = jobstart(['bash', '-c', cmd], extend({'shell': 'shell 1'}, s:callbacks))
    endif
    let num = num + 1
  endfor
endfunction

function! s:should_bind()
  let status = system('git status')
  return status !~ 'fatal: not a git repository'
endfunction

augroup codelens
  autocmd!
  autocmd filetype clojure if !exists('b:codelens_target') | let b:codelens_target = '^(def\|^(ns\|^(deftest\|^(\w\{1,}\/def' | endif
  autocmd filetype clojure if !exists('b:codelens_scope_end') | let b:codelens_scope_end = '^(def\|^(ns\|^(deftest\|^(\w\{1,}\/def' | endif
  autocmd filetype clojure if !exists('b:codelens_func') | let b:codelens_func = '\s\w\{1,}[-.]\{0,}\w\{1,}' | endif

  autocmd filetype vim if !exists('b:codelens_scope_end') | let b:codelens_scope_end = '^function!\|^augroup' | endif
  autocmd filetype vim if !exists('b:codelens_target') | let b:codelens_target = '^function!\|\(augroup\s\)\(END\)\@!' | endif
  autocmd filetype vim if !exists('b:codelens_func') | let b:codelens_func = '\s\w\{1,}\W\{0,}\w\{1,}' | endif

  autocmd filetype javascript if !exists('b:codelens_scope_end') | let b:codelens_scope_end = '^function' | endif
  autocmd filetype javascript if !exists('b:codelens_target') | let b:codelens_target = '^function' | endif
  autocmd filetype javascript if !exists('b:codelens_func') | let b:codelens_func = '\s\w\{1,}\w\{1,}' | endif

  autocmd filetype terraform if !exists('b:codelens_scope_end') | let b:codelens_scope_end = '^module\|^resource' | endif
  autocmd filetype terraform if !exists('b:codelens_target') | let b:codelens_target = '^module\|^resource' | endif

  autocmd BufRead * if g:codelens_auto == 1 && exists('b:codelens_target') && s:should_bind() | silent! call codelens#lens() | endif
  autocmd BufWritePost * if g:codelens_auto == 1 && exists('b:codelens_target') && s:should_bind() | silent! call codelens#lens() | endif

  autocmd filetype * command! -buffer CodelensClear :call nvim_buf_clear_highlight(nvim_get_current_buf(), g:codelens_namespace, 0, -1)
  autocmd filetype * command! -buffer Codelens :call codelens#lens()
augroup END
