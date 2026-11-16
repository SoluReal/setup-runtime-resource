# lts and latest resolve when the rootfs is built; LTS lines have even majors.
node --version | grep -E "^v[0-9]*[02468]\." | assert_contains "v"
pnpm --version | assert_contains "9.15.0"
bun --version | grep -E "^[0-9]+\.[0-9]+\.[0-9]+$" | assert_contains "."
yarn --version | assert_contains "4.10.2"

cd "$PROJECTS/nodejs"

echo "--- Testing npm ---"
npm install
npm test
rm -rf node_modules

echo "--- Testing pnpm ---"
pnpm install
pnpm test
rm -rf node_modules

echo "--- Testing bun ---"
bun install
bun run test
rm -rf node_modules

echo "--- Testing yarn ---"
rm package.json
mv package.json.yarn package.json
mv yarn.lock.bak yarn.lock

yarn
yarn test
