#!/bin/sh

. ./meta.sh
cat <<- EOT
	<?xml version="1.0" encoding="UTF-8"?>
	<rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/">
	<channel>
	<title>$title</title>
	<link>$link/</link>
	<description>$description</description>
	<managingEditor>mvertes@free.fr</managingEditor>
	<pubDate>$(date -R)</pubDate>
EOT

for d in *; do
	[ -d "$d" ] || continue
	cd $d
	. ./meta.sh
	cat <<- EOT
		<item>
		<title>$title</title>
		<link>$link/$d/</link>
		<description>$description</description>
		<author>$author</author>
		<pubDate>$date_rfc2822</pubDate>
		<content:encoded><![CDATA[$(awk '/<h1 / {p=!p} p' index.html)]]>
		</item>
	EOT
done

cat <<- EOT
	</channel>
	</rss>
EOT
