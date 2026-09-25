#!/usr/bin/env sh
cd "$(dirname "$0")"
rm -rf out
javac -encoding UTF-8 -d out -cp "lib/*" src/prontuario/*.java src/prontuario/dao/*.java || exit 1
java -Dfile.encoding=UTF-8 -cp "out:lib/*" prontuario.App "$@"
