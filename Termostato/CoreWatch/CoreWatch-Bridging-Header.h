#ifndef CoreWatch_Bridging_Header_h
#define CoreWatch_Bridging_Header_h

#import <Foundation/Foundation.h>
#import <mach/mach.h>

// IOKit — used by Phase 1 IOKit probe only.
// This header will remain after Phase 1; the probe code in ViewModel is removed.
// io_object_t and related types come from the Darwin device_types layer via mach/mach.h.
// IOOptionBits is not available on iOS SDK; OptionBits (UInt32) is the equivalent.
typedef mach_port_t io_object_t;

extern io_object_t IOServiceGetMatchingService(mach_port_t mainPort, CFDictionaryRef matching);
extern CFMutableDictionaryRef IOServiceMatching(const char *name);
extern kern_return_t IORegistryEntryCreateCFProperties(
    io_object_t entry,
    CFMutableDictionaryRef *properties,
    CFAllocatorRef allocator,
    UInt32 options
);
extern kern_return_t IOObjectRelease(io_object_t obj);

#endif /* CoreWatch_Bridging_Header_h */
