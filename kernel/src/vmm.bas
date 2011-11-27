#include once "vmm.bi"
#include once "pmm.bi"
#include once "kernel.bi"
#include once "video.bi"

namespace vmm
    dim shared kernel_context as context
    
    '' init () sets up the required structures and activates paging
    sub init ()
        '' create a kernel context (only used before the first task is started)
        kernel_context = create_context()
        
        #if 0
        '' map the kernel
        map_range(kernel_context, cuint(kernel_start), cuint(kernel_start), cuint(kernel_end), (FLAG_PRESENT or FLAG_WRITE))
        
        '' map the video memory
        map_page(kernel_context, &hB8000, &hB8000, (FLAG_PRESENT or FLAG_WRITE))
        #endif
        
        '' map the whole first GB
        map_range(kernel_context, 0, 0, &h40000000, (FLAG_PRESENT or FLAG_WRITE))
        
        '' activate the context
        activate_context(kernel_context)
        '' activate paging
        activate()
    end sub
    
    '' create_context () creates and clears space for a page-directory
    function create_context () as context
        dim tcontext as context = pmm.alloc()
        pmm.memset(cuint(tcontext),0,4096)
        return tcontext
    end function
    
    '' map_page maps a single page into a given context
    function map_page (page_directory as context, virtual as uinteger, physical as uinteger, flags as uinteger) as integer
        dim pd_index as uinteger = (virtual shr 22)
        dim pt_index as uinteger = (virtual shr 12) and &h3FF
        dim page_table as context
        
        '' is one of the addresses not 4k-aligned?
        'if (((virtual mod 4096)>0) or ((physical mod 4096)>0)) then
        if ((virtual and &hFFF) or (physical and &hFFF)) then
            return 0
        end if
        
        '' does the page table not exist?
        if (page_directory[pd_index] = 0) then
            '' reserve memory
            page_directory[pd_index] = cuint(pmm.alloc())
            '' clear it
            pmm.memset(page_directory[pd_index], 0, 4096)
            '' set the flags
            page_directory[pd_index] or= (FLAG_PRESENT or FLAG_WRITE or FLAG_USERSPACE)
        end if
        
        '' fetch page-table address from page directory
        page_table = cast(uinteger ptr, (page_directory[pd_index] and &hFFFFF000))
        
        '' set address and flags
        page_table[pt_index] = (physical or flags)
        
        '' invalidate virtual address
        asm
            invlpg [virtual]
        end asm
        
        return -1
    end function
    
    function map_range (page_directory as context, v_addr as uinteger, p_start as uinteger, p_end as uinteger, flags as uinteger) as integer
        dim v_dest as uinteger = v_addr-(v_addr mod 4096)
        dim p_src as uinteger = p_start-(p_start mod 4096)
        while (p_src < p_end)
            if ((map_page(page_directory, v_dest, p_src, flags)=0)) then
                return 0
            end if
            p_src += 4096
            v_dest += 4096
        wend
        
        video.cout("successfully mapped from ")
        video.cout(p_start)
        video.cout(" to ")
        video.cout(p_end)
        
        return -1
    end function
    
    function get_p_addr (page_directory as context, v_addr as uinteger, reserve_if_na as ubyte) as uinteger
        dim pd_index as uinteger = (v_addr shr 22)
        dim pt_index as uinteger = (v_addr shr 12) and &h3FF
        dim page_table as context
        
        if (page_directory[pd_index] = 0) then
            if (reserve_if_na = 1) then
                page_directory[pd_index] = cuint(pmm.alloc())
                pmm.memset(page_directory[pd_index], 0, 4096)
                page_directory[pd_index] or= (FLAG_PRESENT or FLAG_WRITE or FLAG_USERSPACE)
            else
                return 0
            end if
        end if
        
        page_table = cast(uinteger ptr, (page_directory[pd_index] and &hFFFFF000))
        
        if (page_table[pt_index] = 0) then
            if (reserve_if_na = 1) then
                page_table[pt_index] = cuint(pmm.alloc())
                pmm.memset(page_table[pt_index], 0, 4096)
                page_table[pt_index] or= (FLAG_PRESENT or FLAG_WRITE or FLAG_USERSPACE)
            else
                return 0
            end if
        end if
        
        return ((page_table[pt_index] and &hFFFFF000) or (v_addr and &hFFF))
    end function
    
    sub copy_to_context (page_directory as context, p_start as uinteger, v_dest as uinteger, size as uinteger)
        dim bytes_left as uinteger = size
        dim size_for_this_page as uinteger
        dim p_addr as uinteger = p_start
        dim p_v_addr as uinteger
        dim v_addr as uinteger = v_dest
        
        while (bytes_left > 0)
            p_v_addr = get_p_addr(page_directory, v_addr, 1)
            size_for_this_page = ((v_addr+4096) and &hFFF) - v_addr
            pmm.memcpy(p_v_addr, p_addr, size_for_this_page)
            bytes_left -= size_for_this_page
            p_addr += size_for_this_page
            v_addr += size_for_this_page
        wend
    end sub
    
    sub activate_context (page_directory as context)
        asm
            mov eax, [page_directory]
            mov cr3, eax
        end asm
    end sub
    
    '' activate () sets the paging-bit (31) in cr0
    sub activate ()
        asm
            mov eax, cr0
            or eax, &h80000000
            mov cr0, eax
        end asm
    end sub
end namespace