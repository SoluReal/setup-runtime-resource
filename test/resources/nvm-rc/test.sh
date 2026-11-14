bash -c "nvm --version" | assert_contains "0.40.3"

cd "$(mktemp -d)"
echo "v25.2.1" > .nvmrc
nvm install
node --version | assert_contains "25.2.1"

mkdir subdir
echo "v25.2.0" > subdir/.nvmrc
cd subdir
nvm install
node --version | assert_contains "25.2.0"

cd ..
nvm use
node --version | assert_contains "25.2.1"
