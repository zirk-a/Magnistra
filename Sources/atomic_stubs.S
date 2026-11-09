#if defined(__arm__) && !defined(__arm64__)

    .syntax unified
    .text
    .align  2
    .globl  ___atomic_is_lock_free
    .thumb
    .thumb_func
___atomic_is_lock_free:
     
 
    CMP     r0, #4
    BHI     .Lno
    MOV     r0, #1
    BX      lr
.Lno:
    MOV     r0, #0
    BX      lr

#endif   
