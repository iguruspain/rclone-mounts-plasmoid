#!/bin/sh

DIR=`cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd`
plasmoidName="org.kde.plasma.rclone-mounts"
website=""
bugAddress="$website"
packageRoot=".."
projectName="plasma_applet_${plasmoidName}"

if [ -z "$plasmoidName" ]; then
    echo "[build] Error: Couldn't read plasmoidName."
    exit 1
fi

echo "[build] Compiling messages"

catalogs=`find . -name '*.po' | sort`
for cat in $catalogs; do
    echo "$cat"
    catLocale=`basename ${cat%.*}`
    msgfmt -o "${catLocale}.mo" "$cat"

    installPath="$DIR/../contents/locale/${catLocale}/LC_MESSAGES/${projectName}.mo"

    echo "[build] Install to ${installPath}"
    mkdir -p "$(dirname "$installPath")"
    mv "${catLocale}.mo" "${installPath}"
done

echo "[build] Done building messages"
