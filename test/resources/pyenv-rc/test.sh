cd "$(mktemp -d)"
echo "3.12.2" > .python-version
pyenv install --skip-existing
pyenv local
python --version | assert_contains "Python 3.12.2"
