package main

import "testing"

func TestHasFlag(t *testing.T) {
	args := []string{"--type=renderer", "--disable-gpu", "--lang=pt-BR"}
	if !hasFlag(args, "--disable-gpu") {
		t.Fatal("expected --disable-gpu to be detected")
	}
	if !hasFlag(args, "--type") {
		t.Fatal("expected --type=renderer to match --type")
	}
	if hasFlag(args, "--single-process") {
		t.Fatal("did not expect --single-process")
	}
}
