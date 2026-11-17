gomplate --version | assert_contains "gomplate version 4.3.3"
curl --help | assert_contains "Usage: curl [options...]"
wget --help | assert_contains "Usage: wget [OPTION]"
git --version | assert_contains "git version 2"
uname -m | assert_contains "64"
# Extracting the base tar into the rootfs must keep root ownership and the writable /tmp.
stat -c %U /usr/bin/bash | assert_contains "root"
stat -c %a /tmp | assert_contains "1777"
