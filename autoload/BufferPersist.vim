" BufferPersist.vim: Save certain buffers somewhere when quitting them.
"
" DEPENDENCIES:
"   - escapings.vim autoload script
"   - ingointegration.vim autoload script
"
" Copyright: (C) 2012 Ingo Karkat
"   The VIM LICENSE applies to this script; see ':help copyright'.
"
" Maintainer:	Ingo Karkat <ingo@karkat.de>
"
" REVISION	DATE		REMARKS
"   1.00.006	20-Jun-2012	BUG: s:IsBufferEmpty() can throw E486, move the
"				code into the try block so that only the error
"				is printed.
"				Add a:options.whenRangeNoMatch to customize the
"				behavior.
"   1.00.005	18-Jun-2012	Pass bufNr to a:BufferStoreFuncref; on
"				VimLeavePre, the current buffer number does not
"				correspond to the persisted buffer, and the
"				Funcref may want to evaluate the buffer name.
"	004	14-Jun-2012	Do not persist empty buffer contents.
"	003	13-Jun-2012	Replace a:range argument with a more flexible
"				options dictionary, as this and other potential
"				new options are not mandatory.
"	002	12-Jun-2012	Split off BufferPersist functionality from
"				the original MessageRecall plugin.
"	001	09-Jun-2012	file creation

function! s:ErrorMsg( text )
    echohl ErrorMsg
    let v:errmsg = a:text
    echomsg v:errmsg
    echohl None
endfunction

function! s:IsBufferEmpty( range )
    if empty(a:range) || a:range ==# '%'
	return (line('$') == 1 && empty(getline(1)))
    else
	return (ingointegration#GetRange(a:range) =~# '^\n*$')
    endif
endfunction

function! BufferPersist#RecordBuffer( range, whenRangeNoMatch, pendingBufferFilespec )
    let l:range = a:range
    try
	let l:isBufferEmpty = s:IsBufferEmpty(l:range)
    catch /^Vim\%((\a\+)\)\=:E/
	if a:whenRangeNoMatch ==# 'error'
	    call s:ErrorMsg('BufferPersist: Failed to capture buffer: ' . substitute(v:exception, '^Vim\%((\a\+)\)\=:', '', ''))
	    return
	elseif a:whenRangeNoMatch ==# 'ignore'
	    " This will remove any existing a:pendingBufferFilespec below and
	    " not persist the current buffer.
	    let l:isBufferEmpty = 1
	elseif a:whenRangeNoMatch ==# 'all'
	    " Persist the entire buffer instead.
	    let l:range = ''
	    " Unless the entire buffer is empty, too.
	    let l:isBufferEmpty = s:IsBufferEmpty(l:range)
	else
	    throw 'ASSERT: Invalid value for a:whenRangeNoMatch: ' . string(a:whenRangeNoMatch)
	endif
    endtry

    try
	if l:isBufferEmpty
	    " Do not record effectively empty buffer contents; this would just
	    " clutter the store and provides no value on recalls.
	    if filereadable(a:pendingBufferFilespec)
		if delete(a:pendingBufferFilespec) != 0
		    call s:ErrorMsg('BufferPersist: Failed to delete temporary recorded buffer')
		endif
	    endif
	else
	    execute 'silent keepalt' l:range . 'write!' escapings#fnameescape(a:pendingBufferFilespec)
	endif
    catch /^Vim\%((\a\+)\)\=:E/
	call s:ErrorMsg('BufferPersist: Failed to record buffer: ' . substitute(v:exception, '^Vim\%((\a\+)\)\=:', '', ''))
    endtry
endfunction

function! BufferPersist#OnUnload( range, whenRangeNoMatch, pendingBufferFilespec )
    " The BufLeave event isn't invoked when :quitting Vim from the current
    " buffer. We catch this from the BufUnload event. Since it is not allowed to
    " switch buffer in there, we cannot in general use this for persisting. But
    " in this special case, we only need to persist when inside the
    " to-be-unloaded buffer.
    if expand('<abuf>') == bufnr('')
	call BufferPersist#RecordBuffer(a:range, a:whenRangeNoMatch, a:pendingBufferFilespec)
    endif
endfunction

function! BufferPersist#PersistBuffer( pendingBufferFilespec, BufferStoreFuncref, bufNr )
    if ! filereadable(a:pendingBufferFilespec)
	return
    endif

    let l:bufferFilespec = call(a:BufferStoreFuncref, [a:bufNr])
"****D echomsg '**** rename' string(a:pendingBufferFilespec) string(l:bufferFilespec)
    if rename(a:pendingBufferFilespec, l:bufferFilespec) == 0
	unlet! s:pendingBufferFilespecs[a:pendingBufferFilespec]
    else
	call s:ErrorMsg('BufferPersist: Failed to persist buffer to ' . l:bufferFilespec)
    endif
endfunction

function! BufferPersist#OnLeave( BufferStoreFuncref )
    for [l:filespec, l:bufNr] in items(s:pendingBufferFilespecs)
	call BufferPersist#PersistBuffer(l:filespec, a:BufferStoreFuncref, l:bufNr)
    endfor
endfunction

let s:pendingBufferFilespecs = {}
function! BufferPersist#Setup( BufferStoreFuncref, ... )
"******************************************************************************
"* PURPOSE:
"   Set up autocmds for the current buffer to automatically persist the buffer
"   contents when Vim is done editing the buffer (both when is was saved to a
"   file and also when it was discarded, e.g. via :bdelete!)
"* ASSUMPTIONS / PRECONDITIONS:
"   None.
"* EFFECTS / POSTCONDITIONS:
"   Writes buffer contents to the file returned by a:BufferStoreFuncref.
"* INPUTS:
"   a:BufferStoreFuncref    A Funcref that takes the buffer number as an
"			    argument and returns the filespec where the buffer
"			    contents should be persisted to.
"   a:options               Optional Dictionary with configuration:
"   a:options.range         A |:range| expression limiting the lines of the
"			    buffer that should be persisted. This can be used to
"			    filter away some content. Default is "", which
"			    includes the entire buffer.
"   a:options.whenRangeNoMatch  Specifies the behavior when a:options.range
"				doesn't match. One of:
"				"error": an error message is printed and the
"				buffer contents are not persisted
"				"ignore": the buffer contents silently are not
"				persisted
"				"all": the entire buffer is persisted instead
"				Default is "error"
"* RETURN VALUES:
"   None.
"******************************************************************************
    let l:options = (a:0 ? a:1 : {})
    let l:range = get(l:options, 'range', '')
    let l:whenRangeNoMatch = get(l:options, 'whenRangeNoMatch', 'error')

    let l:pendingBufferFilespec = tempname()
    let s:pendingBufferFilespecs[l:pendingBufferFilespec] = bufnr('')

    augroup BufferPersist
	autocmd! * <buffer>
	execute printf('autocmd BufLeave  <buffer> call BufferPersist#RecordBuffer(%s, %s, %s)', string(l:range), string(l:whenRangeNoMatch), string(l:pendingBufferFilespec))
	execute printf('autocmd BufUnload <buffer> call BufferPersist#OnUnload(%s, %s, %s)', string(l:range), string(l:whenRangeNoMatch), string(l:pendingBufferFilespec))
	execute printf('autocmd BufDelete <buffer> call BufferPersist#PersistBuffer(%s, %s, %d)', string(l:pendingBufferFilespec), string(a:BufferStoreFuncref), bufnr(''))

	" This should be added only once per a:BufferStoreFuncref(). However,
	" since subsequent invocations will no-op on an empty
	" s:pendingBufferFilespecs, this does no harm, just adds a minimal
	" linear performance impact, and we don't expect many persisted buffers
	" in a single Vim session, anyway.
	execute printf('autocmd VimLeavePre * call BufferPersist#OnLeave(%s)', string(a:BufferStoreFuncref))
    augroup END
endfunction

" vim: set ts=8 sts=4 sw=4 noexpandtab ff=unix fdm=syntax :
