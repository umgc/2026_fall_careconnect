package toolkit

import (
	"context"
	"fmt"
	"io"
	"os"
	"os/exec"
	"runtime"
	"strings"
)

func runProcess(ctx context.Context, workDir string, argv []string, stdout, stderr io.Writer) error {
	if len(argv) == 0 {
		return fmt.Errorf("empty command")
	}
	cmd := exec.CommandContext(ctx, argv[0], argv[1:]...)
	cmd.Dir = workDir
	cmd.Stdout = stdout
	cmd.Stderr = stderr
	cmd.Stdin = os.Stdin
	cmd.Env = os.Environ()
	if err := cmd.Run(); err != nil {
		return err
	}
	return nil
}

func shellQuote(argv []string) string {
	parts := make([]string, 0, len(argv))
	for _, arg := range argv {
		parts = append(parts, quoteArg(arg))
	}
	return strings.Join(parts, " ")
}

func quoteArg(arg string) string {
	if arg == "" {
		return `""`
	}
	if !strings.ContainsAny(arg, " \t\n\"'\\$&|;<>*?()[]{}!") {
		return arg
	}
	if runtime.GOOS == "windows" {
		return `"` + strings.ReplaceAll(arg, `"`, `\"`) + `"`
	}
	return "'" + strings.ReplaceAll(arg, "'", "'\\''") + "'"
}
