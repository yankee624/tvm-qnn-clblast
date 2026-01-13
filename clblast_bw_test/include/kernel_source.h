#ifndef KERNEL_SOURCE_H
#define KERNEL_SOURCE_H

// Kernel source embedded from kernel.cl
// The kernel.cl file contains the source wrapped in R"( ... )"
// We define it as a string constant here
const char* kernel_source = 
#include "kernel.cl"
;

#endif // KERNEL_SOURCE_H
