gomplate --version | assert_contains "gomplate version 4.3.3"
curl --help | assert_contains "Usage: curl [options...]"
wget --help | assert_contains "Usage: wget [OPTION]"
git --version | assert_contains "git version 2"
# apt can't run without the dpkg database the cleanup deletes, so it is removed; dpkg stays for --print-architecture.
ls /usr/bin | assert_not_contains "apt-get"
dpkg --print-architecture | assert_contains "64"
