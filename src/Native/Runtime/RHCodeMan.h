//
// Copyright (c) Microsoft Corporation.  All rights reserved.
// Licensed under the MIT license. See LICENSE file in the project root for full license information.
//
struct REGDISPLAY;
struct GCInfoHeader;
struct GCEnumContext;
class MethodInfo;
enum GCRefKind : unsigned char;

class EEMethodInfo
{
    PTR_VOID        m_pvCode;
    PTR_UInt8       m_pbRawGCInfo;
    PTR_UInt8       m_pbGCInfo;
    PTR_UInt8       m_pbEpilogTable;
    PTR_VOID        m_pvEHInfo;
    UInt32          m_cbCodeSize;
    GCInfoHeader    m_infoHdr;

public:
    void Init(PTR_VOID pvCode, UInt32 cbCodeSize, PTR_UInt8 pbRawGCInfo, PTR_VOID pvEHInfo);

    void DecodeGCInfoHeader(UInt32 methodOffset, PTR_UInt8 pbUnwindInfoBlob);

    GCInfoHeader *  GetGCInfoHeader();
    PTR_VOID        GetCode()           { return m_pvCode; }
    PTR_UInt8       GetRawGCInfo()      { return m_pbRawGCInfo; }
    PTR_UInt8       GetGCInfo();
    PTR_UInt8       GetEpilogTable();
    PTR_VOID        GetEHInfo()         { return m_pvEHInfo; }
    UInt32          GetCodeSize()       { return m_cbCodeSize; }

};

EEMethodInfo * GetEEMethodInfo(MethodInfo * pMethodInfo);

class EECodeManager
{
public:
    /*
        Enumerate all live object references in that function using
        the virtual register set. Same reference location cannot be enumerated
        multiple times (but all differenct references pointing to the same
        object have to be individually enumerated).
    */
    static void EnumGcRefs(EEMethodInfo *   pMethodInfo,
                           UInt32           codeOffset,
                           REGDISPLAY *     pContext,
                           GCEnumContext *  hCallback,        
                           PTR_UInt8        pbCallsiteStringBlob,
                           PTR_UInt8        pbDeltaShortcutTable);

    /*
    Unwind the current stack frame, i.e. update the virtual register
    set in pContext. This will be similar to the state after the function
    returns back to caller (IP points to after the call, Frame and Stack
    pointer has been reset, callee-saved registers restored, callee-UNsaved 
    registers are trashed)
    Returns success of operation.
    */
    static bool UnwindStackFrame(EEMethodInfo * pMethodInfo,
                                 UInt32         codeOffset,
                                 REGDISPLAY *   pContext);

    static PTR_VOID GetReversePInvokeSaveFrame(EEMethodInfo *   pMethodInfo, 
                                               REGDISPLAY *     pContext);

    static PTR_VOID GetFramePointer(EEMethodInfo *  pMethodInfo, 
                                    REGDISPLAY *    pContext);

    static PTR_PTR_VOID GetReturnAddressLocationForHijack(EEMethodInfo *    pMethodInfo,
                                                          UInt32            codeOffset,
                                                          REGDISPLAY *      pContext);

    static GCRefKind GetReturnValueKind(EEMethodInfo * pMethodInfo);

    static bool GetEpilogOffset(EEMethodInfo * pMethodInfo, UInt32 codeOffset, UInt32 * epilogOffsetOut, UInt32 * epilogSizeOut);

    static void ** GetReturnAddressLocationFromEpilog(GCInfoHeader * pInfoHeader, REGDISPLAY * pContext, 
                                                      UInt32 epilogOffset, UInt32 epilogSize);

#ifdef _DEBUG
public:
    static void DumpGCInfo(EEMethodInfo * pMethodInfo, 
                           UInt8 * pbDeltaShortcutTable, 
                           UInt8 * pbUnwindInfoBlob, 
                           UInt8 * pbCallsiteInfoBlob);

    static void VerifyProlog(EEMethodInfo * pMethodInfo);
    static void VerifyEpilog(EEMethodInfo * pMethodInfo);

private:
    // This will find the first epilog after the code offset passed in via pEpilogStartOffsetInOut.
    // If found, it returns true, false otherwise
    static bool FindNextEpilog(GCInfoHeader * pInfoHeader, UInt32 methodSize, PTR_UInt8 pbEpilogTable, 
                               Int32 * pEpilogStartOffsetInOut, UInt32 * pEpilogSizeOut);

    static bool VerifyEpilogBytes(GCInfoHeader * pInfoHeader, Code * pEpilogStart, UInt32 epilogSize);
#endif // _DEBUG
};
