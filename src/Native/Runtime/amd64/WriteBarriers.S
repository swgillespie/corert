//
// Copyright (c) Microsoft. All rights reserved.
// Licensed under the MIT license. See LICENSE file in the project root for full license information. 
//

.intel_syntax noprefix
#include <unixasmmacros.inc>

#ifdef WRITE_BARRIER_CHECK

.macro UPDATE_GC_SHADOW BASENAME, REFREG, DESTREG

	.ifc \REFREG, RAX
	.error "REFREG cannot be RAX since this macro uses RAX as a helper register!"
	.endif

    // If g_GCShadow is 0, don't perform the check.
    cmp     qword ptr [C_VAR(g_GCShadow)], 0
    je      \BASENAME\()_UpdateShadowHeap_Done_\REFREG

    // Save DESTREG since we're about to modify it (and we need the original value both within the macro and
    // once we exit the macro). Note that this is naughty since we're altering the stack pointer outside of
    // the prolog inside a method without a frame. But given that this is only debug code and generally we
    // shouldn't be walking the stack at this point it seems preferable to recoding the all the barrier
    // variants to set up frames. Unlike RhpBulkWriteBarrier below which is treated as a helper call using the
    // usual calling convention, the compiler knows exactly which registers are trashed in the simple write
    // barrier case, so we don't have any more scratch registers to play with (and doing so would only make
    // things harder if at a later stage we want to allow multiple barrier versions based on the input
    // registers).
    push    \DESTREG

    // Transform DESTREG into the equivalent address in the shadow heap.
    sub     \DESTREG, [C_VAR(g_lowest_address)]
    jb      \BASENAME\()_UpdateShadowHeap_PopThenDone_\REFREG
    add     \DESTREG, [C_VAR(g_GCShadow)]
    cmp     \DESTREG, [C_VAR(g_GCShadowEnd)]
    ja      \BASENAME\()_UpdateShadowHeap_PopThenDone_\REFREG

    // Update the shadow heap.
    mov     [\DESTREG], \REFREG

    // Now check that the real heap location still contains the value we just wrote into the shadow heap. This
    // read must be strongly ordered wrt to the previous write to prevent race conditions. We also need to
    // recover the old value of DESTREG for the comparison so use an xchg instruction (which has an implicit lock
    // prefix).
    xchg    [rsp], \DESTREG
    cmp     [\DESTREG], \REFREG
    jne     \BASENAME\()_UpdateShadowHeap_Invalidate_\REFREG

    // The original DESTREG value is now restored but the stack has a value (the shadow version of the
    // location) pushed. Need to discard this push before we are done.
    add     rsp, 8
    jmp     \BASENAME\()_UpdateShadowHeap_Done_\REFREG

\BASENAME\()_UpdateShadowHeap_Invalidate_\REFREG:
    // Someone went and updated the real heap. We need to invalidate the shadow location since we can't
    // guarantee whose shadow update won.

    // Retrieve shadow location from the stack and restore original DESTREG to the stack. This is an
    // additional memory barrier we don't require but it's on the rare path and x86 doesn't have an xchg
    // variant that doesn't implicitly specify the lock prefix.
    xchg    [rsp], \DESTREG
    mov     qword ptr [\DESTREG], INVALIDGCVALUE

\BASENAME\()_UpdateShadowHeap_PopThenDone_\REFREG:
    // Restore original DESTREG value from the stack.
    pop     \DESTREG

\BASENAME\()_UpdateShadowHeap_Done_\REFREG:
.endm

#else // WRITE_BARRIER_CHECK

.macro UPDATE_GC_SHADOW BASENAME, REFREG, DESTREG
.endm

#endif // WRITE_BARRIER_CHECK

// There are several different helpers used depending on which register holds the object reference. Since all
// the helpers have identical structure we use a macro to define this structure. Two arguments are taken, the
// name of the register that points to the location to be updated and the name of the register that holds the
// object reference (this should be in upper case as it's used in the definition of the name of the helper).
.macro DEFINE_UNCHECKED_WRITE_BARRIER_CORE BASENAME, REFREG

	.ifc \REFREG, RAX
	.error "REFREG cannot be RAX since this macro uses RAX as a helper register!"
	.endif
    // Update the shadow copy of the heap with the same value just written to the same heap. (A no-op unless
    // we're in a debug build and write barrier checking has been enabled).
    UPDATE_GC_SHADOW \BASENAME, \REFREG, rdi

    // If the reference is to an object that's not in an ephemeral generation we have no need to track it
    // (since the object won't be collected or moved by an ephemeral collection).
    cmp     \REFREG, [C_VAR(g_ephemeral_low)]
    jb      \BASENAME\()_NoBarrierRequired_\REFREG
    cmp     \REFREG, [C_VAR(g_ephemeral_high)]
    jae     \BASENAME\()_NoBarrierRequired_\REFREG

    // We have a location on the GC heap being updated with a reference to an ephemeral object so we must
    // track this write. The location address is translated into an offset in the card table bitmap. We set
    // an entire byte in the card table since it's quicker than messing around with bitmasks and we only write
    // the byte if it hasn't already been done since writes are expensive and impact scaling.
    shr     rdi, 11
    add     rdi, [C_VAR(g_card_table)]
    cmp     byte ptr [rdi], 0FFh
    jne     \BASENAME\()_UpdateCardTable_\REFREG

\BASENAME\()_NoBarrierRequired_\REFREG:
    ret

// We get here if it's necessary to update the card table.
\BASENAME\()_UpdateCardTable_\REFREG:
    mov     byte ptr [rdi], 0FFh
    ret

.endm

// There are several different helpers used depending on which register holds the object reference. Since all
// the helpers have identical structure we use a macro to define this structure. One argument is taken, the
// name of the register that will hold the object reference (this should be in upper case as it's used in the
// definition of the name of the helper).
.macro DEFINE_UNCHECKED_WRITE_BARRIER REFREG, EXPORT_REG_NAME

// Define a helper with a name of the form RhpAssignRefEAX etc. (along with suitable calling standard
// decoration). The location to be updated is in DESTREG. The object reference that will be assigned into that
// location is in one of the other general registers determined by the value of REFREG.

// WARNING: Code in EHHelpers.cpp makes assumptions about write barrier code, in particular:
// - Function "InWriteBarrierHelper" assumes an AV due to passed in null pointer will happen on the first instruction
// - Function "UnwindWriteBarrierToCaller" assumes the stack contains just the pushed return address
LEAF_ENTRY RhpAssignRef\EXPORT_REG_NAME, _TEXT

    // Export the canonical write barrier under unqualified name as well
    .ifc \REFREG, RSI
    ALTERNATE_ENTRY RhpAssignRef
    ALTERNATE_ENTRY RhpAssignRefAVLocation
    .endif

    // Write the reference into the location. Note that we rely on the fact that no GC can occur between here
    // and the card table update we may perform below.
    mov     qword ptr [rdi], \REFREG

    DEFINE_UNCHECKED_WRITE_BARRIER_CORE RhpAssignRef, \REFREG

LEAF_END RhpAssignRef\EXPORT_REG_NAME, _TEXT
.endm

// One day we might have write barriers for all the possible argument registers but for now we have
// just one write barrier that assumes the input register is RSI.
DEFINE_UNCHECKED_WRITE_BARRIER RSI, ESI

//
// Define the helpers used to implement the write barrier required when writing an object reference into a
// location residing on the GC heap. Such write barriers allow the GC to optimize which objects in
// non-ephemeral generations need to be scanned for references to ephemeral objects during an ephemeral
// collection.
//

.macro DEFINE_CHECKED_WRITE_BARRIER_CORE BASENAME, REFREG

    // The location being updated might not even lie in the GC heap (a handle or stack location for instance),
    // in which case no write barrier is required.
    cmp     rdi, [C_VAR(g_lowest_address)]
    jb      \BASENAME\()_NoBarrierRequired_\REFREG
    cmp     rdi, [C_VAR(g_highest_address)]
    jae     \BASENAME\()_NoBarrierRequired_\REFREG

    DEFINE_UNCHECKED_WRITE_BARRIER_CORE \BASENAME, \REFREG

.endm

// There are several different helpers used depending on which register holds the object reference. Since all
// the helpers have identical structure we use a macro to define this structure. One argument is taken, the
// name of the register that will hold the object reference (this should be in upper case as it's used in the
// definition of the name of the helper).
.macro DEFINE_CHECKED_WRITE_BARRIER REFREG, EXPORT_REG_NAME

// Define a helper with a name of the form RhpCheckedAssignRefEAX etc. (along with suitable calling standard
// decoration). The location to be updated is always in RDI. The object reference that will be assigned into
// that location is in one of the other general registers determined by the value of REFREG.

// WARNING: Code in EHHelpers.cpp makes assumptions about write barrier code, in particular:
// - Function "InWriteBarrierHelper" assumes an AV due to passed in null pointer will happen on the first instruction
// - Function "UnwindWriteBarrierToCaller" assumes the stack contains just the pushed return address
LEAF_ENTRY RhpCheckedAssignRef\EXPORT_REG_NAME, _TEXT

    // Export the canonical write barrier under unqualified name as well
    .ifc \REFREG, RSI
    ALTERNATE_ENTRY RhpCheckedAssignRef
    ALTERNATE_ENTRY RhpCheckedAssignRefAVLocation
    .endif

    // Write the reference into the location. Note that we rely on the fact that no GC can occur between here
    // and the card table update we may perform below.
    mov     qword ptr [rdi], \REFREG

    DEFINE_CHECKED_WRITE_BARRIER_CORE RhpCheckedAssignRef, \REFREG

LEAF_END RhpCheckedAssignRef\EXPORT_REG_NAME, _TEXT
.endm

// One day we might have write barriers for all the possible argument registers but for now we have
// just one write barrier that assumes the input register is RSI.
DEFINE_CHECKED_WRITE_BARRIER RSI, ESI

// WARNING: Code in EHHelpers.cpp makes assumptions about write barrier code, in particular:
// - Function "InWriteBarrierHelper" assumes an AV due to passed in null pointer will happen at RhpCheckedLockCmpXchgAVLocation
// - Function "UnwindWriteBarrierToCaller" assumes the stack contains just the pushed return address
LEAF_ENTRY RhpCheckedLockCmpXchg, _TEXT
    mov             rax, rdx
ALTERNATE_ENTRY RhpCheckedLockCmpXchgAVLocation
    lock cmpxchg    [rdi], rsi
    jne             RhpCheckedLockCmpXchg_NoBarrierRequired_RSI

    DEFINE_CHECKED_WRITE_BARRIER_CORE RhpCheckedLockCmpXchg, RSI

LEAF_END RhpCheckedLockCmpXchg, _TEXT

// WARNING: Code in EHHelpers.cpp makes assumptions about write barrier code, in particular:
// - Function "InWriteBarrierHelper" assumes an AV due to passed in null pointer will happen at RhpCheckedXchgAVLocation
// - Function "UnwindWriteBarrierToCaller" assumes the stack contains just the pushed return address
LEAF_ENTRY RhpCheckedXchg, _TEXT
    
    // Setup rax with the new object for the exchange, that way it will automatically hold the correct result
    // afterwards and we can leave rdx unaltered ready for the GC write barrier below.
    mov             rax, rsi
ALTERNATE_ENTRY RhpCheckedXchgAVLocation
    xchg            [rdi], rax

    DEFINE_CHECKED_WRITE_BARRIER_CORE RhpCheckedXchg, RSI

LEAF_END RhpCheckedXchg, _TEXT

//
// RhpByRefAssignRef simulates movs instruction for object references.
//
// On entry:
//      rdi: address of ref-field (assigned to)
//      rsi: address of the data (source)
//      rcx: be trashed
//
// On exit:
//      rdi, rsi are incremented by 8, 
//      rcx: trashed
//
LEAF_ENTRY RhpByRefAssignRef, _TEXT
    mov     rcx, [rsi]
    mov     [rdi], rcx

    // Update the shadow copy of the heap with the same value just written to the same heap. (A no-op unless
    // we're in a debug build and write barrier checking has been enabled).
    UPDATE_GC_SHADOW BASENAME, rcx, rdi

    // If the reference is to an object that's not in an ephemeral generation we have no need to track it
    // (since the object won't be collected or moved by an ephemeral collection).
    cmp     rcx, [C_VAR(g_ephemeral_low)]
    jb      RhpByRefAssignRef_NotInHeap
    cmp     rcx, [C_VAR(g_ephemeral_high)]
    jae     RhpByRefAssignRef_NotInHeap

    // move current rdi value into rcx and then increment the pointers
    mov     rcx, rdi
    add     rsi, 8h
    add     rdi, 8h

    // We have a location on the GC heap being updated with a reference to an ephemeral object so we must
    // track this write. The location address is translated into an offset in the card table bitmap. We set
    // an entire byte in the card table since it's quicker than messing around with bitmasks and we only write
    // the byte if it hasn't already been done since writes are expensive and impact scaling.
    shr     rcx, 11
    add     rcx, [C_VAR(g_card_table)]
    cmp     byte ptr [rcx], 0FFh
    jne     RhpByRefAssignRef_UpdateCardTable
    ret

// We get here if it's necessary to update the card table.
RhpByRefAssignRef_UpdateCardTable:
    mov     byte ptr [rcx], 0FFh
    ret

RhpByRefAssignRef_NotInHeap:
    // Increment the pointers before leaving
    add     rdi, 8h
    add     rsi, 8h
    ret
LEAF_END RhpByRefAssignRef, _TEXT
