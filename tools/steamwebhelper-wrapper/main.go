// steamwebhelper wrapper
//
// Steam's embedded Chromium (steamwebhelper.exe) renders a black window and
// fails TLS for sign-in when it runs under Wine on macOS. Replacing it with
// this tiny launcher, which starts the real binary (renamed to
// steamwebhelper.orig.exe) with --disable-gpu --single-process, makes the
// Steam UI usable. Steam must be started with -noverifyfiles, otherwise it
// restores its own binary; Blottle re-deploys the wrapper before each launch.
package main

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

const originalName = "steamwebhelper.orig.exe"

var injectedFlags = []string{"--disable-gpu", "--single-process"}

func main() {
	self, err := os.Executable()
	if err != nil {
		self = os.Args[0]
	}
	original := filepath.Join(filepath.Dir(self), originalName)
	if _, err := os.Stat(original); err != nil {
		fmt.Fprintf(os.Stderr, "steamwebhelper wrapper: %s not found: %v\n", originalName, err)
		os.Exit(2)
	}

	args := append([]string{}, os.Args[1:]...)
	for _, flag := range injectedFlags {
		if !hasFlag(args, flag) {
			args = append(args, flag)
		}
	}

	cmd := exec.Command(original, args...)
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	cmd.Env = os.Environ()
	if err := cmd.Run(); err != nil {
		if exitErr, ok := err.(*exec.ExitError); ok {
			os.Exit(exitErr.ExitCode())
		}
		fmt.Fprintf(os.Stderr, "steamwebhelper wrapper: %v\n", err)
		os.Exit(1)
	}
}

func hasFlag(args []string, flag string) bool {
	for _, arg := range args {
		if arg == flag || strings.HasPrefix(arg, flag+"=") {
			return true
		}
	}
	return false
}
