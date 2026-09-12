package main

import (
	"fmt"
	"os"

	"careconnect/dev-toolkit/internal/toolkit"
)

func main() {
	app := toolkit.NewApp(os.Stdin, os.Stdout, os.Stderr)
	if err := app.Run(os.Args[1:]); err != nil {
		fmt.Fprintf(os.Stderr, "careconnect-dev: %v\n", err)
		os.Exit(1)
	}
}
