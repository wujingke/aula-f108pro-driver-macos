#!/bin/sh
cd "$(dirname "$0")" || exit 1
./f108-time --sync
sync_result=$?
printf '\n按回车关闭窗口…'
IFS= read -r close_answer
exit "$sync_result"
