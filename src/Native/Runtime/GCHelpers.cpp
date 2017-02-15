// Licensed to the .NET Foundation under one or more agreements.
// The .NET Foundation licenses this file to you under the MIT license.
// See the LICENSE file in the project root for more information.

//
// Unmanaged helpers exposed by the System.GC managed class.
//

#include "common.h"
#include "gcenv.h"
#include "gcheaputilities.h"
#include "RestrictedCallouts.h"

#include "gcrhinterface.h"

#include "PalRedhawkCommon.h"
#include "slist.h"
#include "varint.h"
#include "regdisplay.h"
#include "StackFrameIterator.h"

#include "thread.h"
#include "RWLock.h"
#include "threadstore.h"
#include "threadstore.inl"
#include "thread.inl"
#include "../gc/objecthandle.h"

EXTERN_C REDHAWK_API void __cdecl RhpCollect(UInt32 uGeneration, UInt32 uMode)
{
    // This must be called via p/invoke rather than RuntimeImport to make the stack crawlable.

    Thread * pCurThread = GetThread();

    pCurThread->SetupHackPInvokeTunnel();
    pCurThread->DisablePreemptiveMode();

    ASSERT(!pCurThread->IsDoNotTriggerGcSet());
    GCHeapUtilities::GetGCHeap()->GarbageCollect(uGeneration, FALSE, uMode);

    pCurThread->EnablePreemptiveMode();
}

EXTERN_C REDHAWK_API Int64 __cdecl RhpGetGcTotalMemory()
{
    // This must be called via p/invoke rather than RuntimeImport to make the stack crawlable.

    Thread * pCurThread = GetThread();

    pCurThread->SetupHackPInvokeTunnel();
    pCurThread->DisablePreemptiveMode();

    Int64 ret = GCHeapUtilities::GetGCHeap()->GetTotalBytesInUse();

    pCurThread->EnablePreemptiveMode();

    return ret;
}

EXTERN_C REDHAWK_API Int32 __cdecl RhpGetGenerationWR(void* refObj)
{
    Thread * pCurThread = GetThread();

    pCurThread->DisablePreemptiveMode();

    int result = 0;

    OBJECTREF wrTarget = ObjectFromHandle((OBJECTHANDLE) refObj);
    if (wrTarget == nullptr)
    {
        // The weak reference is dead, returning -1 indicates to the
        // caller to throw an ArgumentNullException
        result = -1;
    }
    else
    {
        result = GCHeapUtilities::GetGCHeap()->WhichGeneration(OBJECTREFToObject(wrTarget));
    }

    pCurThread->EnablePreemptiveMode();
    return result;
}

COOP_PINVOKE_HELPER(void, RhSuppressFinalize, (OBJECTREF refObj))
{
    if (!refObj->get_EEType()->HasFinalizer())
        return;
    GCHeapUtilities::GetGCHeap()->SetFinalizationRun(refObj);
}

COOP_PINVOKE_HELPER(Boolean, RhReRegisterForFinalize, (OBJECTREF refObj))
{
    if (!refObj->get_EEType()->HasFinalizer())
        return Boolean_true;
    return GCHeapUtilities::GetGCHeap()->RegisterForFinalization(-1, refObj) ? Boolean_true : Boolean_false;
}

COOP_PINVOKE_HELPER(Int32, RhGetMaxGcGeneration, ())
{
    return GCHeapUtilities::GetGCHeap()->GetMaxGeneration();
}

COOP_PINVOKE_HELPER(Int32, RhGetGcCollectionCount, (Int32 generation, Boolean getSpecialGCCount))
{
    return GCHeapUtilities::GetGCHeap()->CollectionCount(generation, getSpecialGCCount);
}

COOP_PINVOKE_HELPER(Int32, RhGetGeneration, (OBJECTREF obj))
{
    return GCHeapUtilities::GetGCHeap()->WhichGeneration(obj);
}

COOP_PINVOKE_HELPER(Int32, RhGetGcLatencyMode, ())
{
    return GCHeapUtilities::GetGCHeap()->GetGcLatencyMode();
}

COOP_PINVOKE_HELPER(void, RhSetGcLatencyMode, (Int32 newLatencyMode))
{
    GCHeapUtilities::GetGCHeap()->SetGcLatencyMode(newLatencyMode);
}

COOP_PINVOKE_HELPER(Boolean, RhIsServerGc, ())
{
    return GCHeapUtilities::IsServerHeap();
}

COOP_PINVOKE_HELPER(Boolean, RhRegisterGcCallout, (GcRestrictedCalloutKind eKind, void * pCallout))
{
    return RestrictedCallouts::RegisterGcCallout(eKind, pCallout);
}

COOP_PINVOKE_HELPER(void, RhUnregisterGcCallout, (GcRestrictedCalloutKind eKind, void * pCallout))
{
    RestrictedCallouts::UnregisterGcCallout(eKind, pCallout);
}

COOP_PINVOKE_HELPER(Boolean, RhIsPromoted, (OBJECTREF obj))
{
    return GCHeapUtilities::GetGCHeap()->IsPromoted(obj) ? Boolean_true : Boolean_false;
}

COOP_PINVOKE_HELPER(Int32, RhGetLohCompactionMode, ())
{
    return GCHeapUtilities::GetGCHeap()->GetLOHCompactionMode();
}

COOP_PINVOKE_HELPER(void, RhSetLohCompactionMode, (Int32 newLohCompactionMode))
{
    GCHeapUtilities::GetGCHeap()->SetLOHCompactionMode(newLohCompactionMode);
}

COOP_PINVOKE_HELPER(Int64, RhGetCurrentObjSize, ())
{
    return GCHeapUtilities::GetGCHeap()->GetCurrentObjSize();
}

COOP_PINVOKE_HELPER(Int64, RhGetGCNow, ())
{
    return GCHeapUtilities::GetGCHeap()->GetNow();
}

COOP_PINVOKE_HELPER(Int64, RhGetLastGCStartTime, (Int32 generation))
{
    return GCHeapUtilities::GetGCHeap()->GetLastGCStartTime(generation);
}

COOP_PINVOKE_HELPER(Int64, RhGetLastGCDuration, (Int32 generation))
{
    return GCHeapUtilities::GetGCHeap()->GetLastGCDuration(generation);
}

COOP_PINVOKE_HELPER(void, RhRegisterForFullGCNotification, (Int32 maxGenerationThreshold, Int32 largeObjectHeapThreshold))
{
    ASSERT(maxGenerationThreshold >= 1 && maxGenerationThreshold <= 99);
    ASSERT(largeObjectHeapThreshold >= 1 && largeObjectHeapThreshold <= 99);
    GCHeapUtilities::GetGCHeap()->RegisterForFullGCNotification(maxGenerationThreshold, largeObjectHeapThreshold);
}

COOP_PINVOKE_HELPER(int, RhWaitForFullGCApproach, (Int32 millisecondsTimeout))
{
    ASSERT(millisecondsTimeout >= -1);

    DWORD timeout = millisecondsTimeout == -1 ? INFINITE : millisecondsTimeout;
    return GCHeapUtilities::GetGCHeap()->WaitForFullGCApproach(millisecondsTimeout);
}

COOP_PINVOKE_HELPER(int, RhWaitForFullGCComplete, (Int32 millisecondsTimeout))
{
    ASSERT(millisecondsTimeout >= -1);

    DWORD timeout = millisecondsTimeout == -1 ? INFINITE : millisecondsTimeout;
    return GCHeapUtilities::GetGCHeap()->WaitForFullGCComplete(millisecondsTimeout);
}

COOP_PINVOKE_HELPER(Boolean, RhCancelFullGCNotification, ())
{
    return GCHeapUtilities::GetGCHeap()->CancelFullGCNotification();
}

COOP_PINVOKE_HELPER(int, RhStartNoGCRegion, (Int64 totalSize, BOOL hasLohSize, Int64 lohSize, BOOL disallowFullBlockingGC))
{
    return GCHeapUtilities::GetGCHeap()->StartNoGCRegion(totalSize, hasLohSize, lohSize, disallowFullBlockingGC);
}

COOP_PINVOKE_HELPER(int, RhEndNoGCRegion, ())
{
    return GCHeapUtilities::GetGCHeap()->EndNoGCRegion();
}