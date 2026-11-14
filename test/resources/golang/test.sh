go version | assert_contains "go version go1.22.1"

# minimal_image strips Go's own test suite.
ls "$GOROOT/test" 2>&1 | assert_contains "No such file"
# minimal_image also drops apt, which can't run without the dpkg database the cleanup deletes.
ls /usr/bin | assert_not_contains "apt-get"

cd "$(mktemp -d)"
cat > main.go <<'GO'
package main

import "fmt"

func main() { fmt.Println("hello from go") }
GO
go build -o hello main.go
./hello | assert_contains "hello from go"

# In full, pyenv brings gcc anyway.
if [[ "$PYENV_ENABLED" != "true" ]]; then
  (command -v gcc || echo "no gcc") | assert_contains "no gcc"
fi
