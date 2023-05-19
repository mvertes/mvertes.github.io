#!/bin/sh


fixhtml() {
	gawk '
	# Skip everything before first <h1>.
	/<h1 / { p = !p }
	p {
		# Make reference links absolute.
		$0 = gensub(/<img src="([^hH][^"]*)"/, "<img src=\"'$1'\\1\"", "g")
		$0 = gensub(/<a href="([^hH][^"]*)"/, "<a href=\"'$1'\\1\"", "g")
		print 
	}
	' "$2"
}

. ./meta.sh
cat <<- EOT
	<?xml version="1.0" encoding="UTF-8"?>
	<rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom">
	<atom:link href="$link/feed.xml" rel="self" type="application/rss+xml" />
	<channel>
	<title>$title</title>
	<link>$link/</link>
	<description>$description</description>
	<managingEditor>$email ($author)</managingEditor>
	<pubDate>$(date -R)</pubDate>
EOT

for d in *; do
	[ -d "$d" ] || continue
	cd $d
	. ./meta.sh
	cat <<- EOT
		<item>
		<guid isPermaLink="true">$link/$d/</guid>
		<title>$title</title>
		<link>$link/$d/</link>
		<description>$description</description>
		<author>$email ($author)</author>
		<pubDate>$date_rfc2822</pubDate>
		<content:encoded>
		<![CDATA[$(fixhtml "$link/$d/" index.html)]]>
		</content:encoded>
		</item>
	EOT
done

cat <<- EOT
	</channel>
	</rss>
EOT
