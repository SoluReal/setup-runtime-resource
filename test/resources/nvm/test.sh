bash -c "nvm --version" | assert_contains "0.40.3"
which node | assert_contains "nvm"
node --version | assert_contains "$(nvm current)"

cd "$PROJECTS/nodejs"
npm install
npm test
rm -rf node_modules
