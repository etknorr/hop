//go:build unix && !linux

package tty

import "syscall"

func dupTo(old, fd int) { _ = syscall.Dup2(old, fd) }
