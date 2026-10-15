package ptytest

import (
	"fmt"
	"os"
	"syscall"
	"unsafe"
)

// openPTY is posix_openpt, unlockpt and ptsname, by ioctl as Linux spells them.
func openPTY() (*os.File, string, error) {
	m, err := os.OpenFile("/dev/ptmx", os.O_RDWR|syscall.O_NOCTTY, 0)
	if err != nil {
		return nil, "", err
	}
	var unlock int32
	if _, _, e := syscall.Syscall(syscall.SYS_IOCTL, m.Fd(), syscall.TIOCSPTLCK, uintptr(unsafe.Pointer(&unlock))); e != 0 {
		m.Close()
		return nil, "", fmt.Errorf("TIOCSPTLCK: %w", e)
	}
	var n uint32
	if _, _, e := syscall.Syscall(syscall.SYS_IOCTL, m.Fd(), syscall.TIOCGPTN, uintptr(unsafe.Pointer(&n))); e != 0 {
		m.Close()
		return nil, "", fmt.Errorf("TIOCGPTN: %w", e)
	}
	return m, fmt.Sprintf("/dev/pts/%d", n), nil
}
