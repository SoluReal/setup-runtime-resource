gomplate --version | assert_contains "gomplate version 4.3.3"
curl --help | assert_contains "Usage: curl [options...]"
wget --help | assert_contains "Usage: wget [OPTION]"
git --version | assert_contains "git version 2"
dpkg --print-architecture | assert_contains "64"

# Only with the proxy option (build-and-test.sh sets it): curl through a TLS-bumping proxy fails unless its CA is trusted.
if [[ -n "${SETUP_RUNTIME_PROXY_HOST:-}" ]]; then
  env | assert_contains "https_proxy=http://$SETUP_RUNTIME_PROXY_HOST:$SETUP_RUNTIME_PROXY_PORT"
  curl -fsSI https://repo1.maven.org/maven2/ | assert_contains "HTTP/"
fi
