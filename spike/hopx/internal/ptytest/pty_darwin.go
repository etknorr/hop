package ptytest

import (
	"bytes"
	"fmt"
	"os"
	"syscall"
	"unsafe"
)

// openPTY is posix_openpt, grantpt, unlockpt and ptsname, by ioctl as macOS spells them.
func openPTY() (*os.File, string, error) {
	m, err := os.OpenFile("/dev/ptmx", os.O_RDWR|syscall.O_NOCTTY, 0)
	if err != nil {
		return nil, "", err
	}
	for _, req := range []uintptr{syscall.TIOCPTYGRANT, syscall.TIOCPTYUNLK} {
		if _, _, e := syscall.Syscall(syscall.SYS_IOCTL, m.Fd(), req, 0); e != 0 {
			m.Close()
			return nil, "", fmt.Errorf("ioctl %#x: %w", req, e)
		}
	}
	name := make([]byte, 128)
	if _, _, e := syscall.Syscall(syscall.SYS_IOCTL, m.Fd(), syscall.TIOCPTYGNAME, uintptr(unsafe.Pointer(&name[0]))); e != 0 {
		m.Close()
		return nil, "", fmt.Errorf("TIOCPTYGNAME: %w", e)
	}
	return m, string(name[:bytes.IndexByte(name, 0)]), nil
}
