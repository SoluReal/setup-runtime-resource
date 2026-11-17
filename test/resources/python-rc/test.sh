cd "$(mktemp -d)"
echo "3.12.2" > .python-version
uv python install
uv run python --version | assert_contains "Python 3.12.2"
