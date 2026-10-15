package tty

import "syscall"

// linux/arm64 has no dup2 syscall, only dup3.
func dupTo(old, fd int) { _ = syscall.Dup3(old, fd, 0) }
