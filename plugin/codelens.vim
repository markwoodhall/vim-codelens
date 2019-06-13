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

function! s:unit_distance(unit) abort
  if a:unit == 'years'
    return 8
  elseif a:unit == 'months'
    return 7
  elseif a:unit == 'weeks'
    return 6
  elseif a:unit == 'days'
    return 5
  elseif a:unit == 'hours'
    return 4
  elseif a:unit == 'minutes'
    return 3
  elseif a:unit == 'seconds'
    return 2
  endif
endfunction

function! s:most_recent(list) abort
  let recent = ''
  let last_score = 999
  for e in a:list
    let date = split(e, 'Date:')[1]
    let date = trim(date)
    let parts = split(date, ',')
    let score = 0

    for p in parts
      let number = split(p, ' ')[0]
      let unit = split(p, ' ')[1]
      let unit_distance = s:unit_distance(unit)
      let score = score + number + unit_distance
    endfor

    if score < last_score
      let last_score = score
      let recent = join(split(date, ' ')[0:-2], ' ') . ' by ' . trim(split(e, 'Date:')[0])
    endif
  endfor
  return recent
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

          let author = s:most_recent(authors)

          let message = author

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
            let message = matchstr(getline(line), '^\s\{1,}') . message
            silent! call nvim_buf_set_virtual_text(nvim_get_current_buf(), g:codelens_namespace, line-2, [[message, 'CodeLensReference']], {})
          else
            silent! call nvim_buf_set_virtual_text(nvim_get_current_buf(), g:codelens_namespace, line-1, [[message, 'CodeLensReference']], {})
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
      let cmd = 'username=$(git config user.name);echo "' . num . '"#$(git blame ' . filename . ' -L ' . num . ',' . num_end_line . ' --date=relative  | cut -d "(" -f2 | cut -d ")" -f1 | sed  "s/^/Author: /" | sed "s/\([0-9]\+ [a-z]\+ ago\)/\nDate: \1/" | sed "s/Not Committed Yet/$username*/")'

      if exists('b:codelens_func')
        let func = trim(matchstr(line, b:codelens_func))

        let clean_line = substitute(line, '[', '\\[', 'g')
        let clean_line = substitute(clean_line, ']', '\\]', 'g')

        let cmd = cmd . '#$(git grep --not -e "'. clean_line .'" --and -e "'.func.'" | wc -l)'
      endif

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
  
  autocmd filetype sql if !exists('b:codelens_scope_end') | let b:codelens_scope_end = '--\s:name' | endif
  autocmd filetype sql if !exists('b:codelens_target') | let b:codelens_target = '--\s:name' | endif
  autocmd filetype sql if !exists('b:codelens_func') | let b:codelens_func = '\s\w\{1,}[-.]\{0,}\w\{1,}' | endif
  
  autocmd filetype python if !exists('b:codelens_scope_end') | let b:codelens_scope_end = '^class\s\|^def\s\|\sdef\s' | endif
  autocmd filetype python if !exists('b:codelens_target') | let b:codelens_target = '^class\s\|^def\s\|\sdef\s' | endif
  autocmd filetype python if !exists('b:codelens_func') | let b:codelens_func = '\(\s\{1}\)\(def\)\@!\(\w\{1,}\)' | endif

  autocmd filetype terraform if !exists('b:codelens_scope_end') | let b:codelens_scope_end = '^module\|^resource' | endif
  autocmd filetype terraform if !exists('b:codelens_target') | let b:codelens_target = '^module\|^resource' | endif

  autocmd BufRead * if g:codelens_auto == 1 && exists('b:codelens_target') && s:should_bind() | silent! call codelens#lens() | endif
  autocmd BufWritePost * if g:codelens_auto == 1 && exists('b:codelens_target') && s:should_bind() | silent! call codelens#lens() | endif

  autocmd filetype * command! -buffer CodelensClear :call nvim_buf_clear_highlight(nvim_get_current_buf(), g:codelens_namespace, 0, -1)
  autocmd filetype * command! -buffer Codelens :call codelens#lens()

  autocmd BufEnter * if exists('b:codelens_target') && s:should_bind() | hi CodeLensReference guifg=#1da374 | endif
augroup END

