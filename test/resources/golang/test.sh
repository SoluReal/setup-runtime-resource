go version | assert_contains "go version go1.22.1"

# minimal_image strips Go's own test suite.
ls "$GOROOT/test" 2>&1 | assert_contains "No such file"

cd "$(mktemp -d)"
cat > main.go <<'GO'
package main

import "fmt"

func main() { fmt.Println("hello from go") }
GO
go build -o hello main.go
./hello | assert_contains "hello from go"
