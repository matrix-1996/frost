/'
 ' FROST x86 microkernel
 ' Copyright (C) 2010-2015  Stefan Schmidt
 ' 
 ' This program is free software: you can redistribute it and/or modify
 ' it under the terms of the GNU General Public License as published by
 ' the Free Software Foundation, either version 3 of the License, or
 ' (at your option) any later version.
 ' 
 ' This program is distributed in the hope that it will be useful,
 ' but WITHOUT ANY WARRANTY; without even the implied warranty of
 ' MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 ' GNU General Public License for more details.
 ' 
 ' You should have received a copy of the GNU General Public License
 ' along with this program.  If not, see <http://www.gnu.org/licenses/>.
 '/

#include "elf.bi"
#include "elf32.bi"
#include "process.bi"
#include "thread.bi"
#include "pmm.bi"
#include "mem.bi"
#include "panic.bi"

function elf_header_check (header as Elf32_Ehdr ptr) as integer
	'' check for the magic value (&h7F, 'E', 'L', 'F')
	if ((header->e_ident.EI_MAGIC(0) <> &h7F) or _
		(header->e_ident.EI_MAGIC(1) <> &h45) or _
		(header->e_ident.EI_MAGIC(2) <> &h4C) or _
		(header->e_ident.EI_MAGIC(3) <> &h46)) then return 1
			
	if (header->e_type <> ELF_ET_EXEC) then return 2
	if (header->e_machine <> ELF_EM_386) then return 3
	if (header->e_ident.EI_CLASS <> ELF_CLASS_32) then return 4
	if (header->e_ident.EI_DATA <> ELF_DATA_2LSB) then return 5
	if (header->e_version <> ELF_EV_CURRENT) then return 6
	return 0
end function


function elf_load_image (process as process_type ptr, thread as thread_type ptr ptr,  image as uinteger, size as uinteger) as boolean
	dim header as Elf32_Ehdr ptr = cast(Elf32_Ehdr ptr, image)
	
	if (size < sizeof(Elf32_Ehdr)) then return false
	
	if (elf_header_check(header) > 0) then return false

	'' pointer to the first program header
	dim program_header as Elf32_Phdr ptr = cast(Elf32_Phdr ptr, cuint(header) + header->e_phoff)
	
	'' iterate over all segments
	for counter as uinteger = 0 to header->e_phnum-1
		'' skip segments that are not loadable
		if (program_header[counter].p_type <> ELF_PT_LOAD) then continue for
		
		'' align the start on page-boundaries
		dim start as uinteger = program_header[counter].p_vaddr and VMM_PAGE_MASK
		dim real_size as uinteger = program_header[counter].p_filesz + (program_header[counter].p_vaddr - start)
		dim real_mem_size as uinteger = program_header[counter].p_memsz + (program_header[counter].p_vaddr - start)
		
		'' start and end of the segment
		dim addr as uinteger = start
		dim end_addr as uinteger = start + real_size
		dim end_addr_mem as uinteger = start + real_mem_size
		
		dim area as address_space_area ptr = new address_space_area(cast(any ptr, start), num_pages(real_mem_size))
		process->a_s.insert_area(area)
		
		
		while (addr < end_addr_mem)
			dim phys_mem as any ptr = pmm_alloc()
			dim mem as any ptr = vmm_kernel_automap(phys_mem, PAGE_SIZE)
		
			if (addr < end_addr) then
				dim remaining_copy as uinteger = end_addr - addr
				dim chunk_size as uinteger = iif(remaining_copy > PAGE_SIZE, PAGE_SIZE, remaining_copy)
				
				memcpy(mem,_
					   cast(any ptr, image + program_header[counter].p_offset + (addr-start)), _
					   chunk_size)
				
				if (PAGE_SIZE - chunk_size > 0) then memset(mem+chunk_size, 0, PAGE_SIZE-chunk_size)
			else
				memset(mem, 0, PAGE_SIZE)
			end if
			
			vmm_kernel_unmap(mem, PAGE_SIZE)
			
			vmm_map_page(@process->context, cast(any ptr, addr), cast(any ptr, phys_mem), VMM_PTE_FLAGS.WRITABLE or VMM_PTE_FLAGS.PRESENT or VMM_PTE_FLAGS.USERSPACE)
			
			addr += PAGE_SIZE
		wend
	next
	
	'' create the thread
	*thread = new thread_type(process, cast(any ptr, header->e_entry), 1)
	
	return true
end function
