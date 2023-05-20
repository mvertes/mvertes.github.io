#!/bin/sh

header='<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
  body {
	  max-width: 45rem;
	  margin: auto;
	  padding: 0.5em;
	  text-align: justify;
  }
  h1 { text-align: center }
  pre {
	padding: 1ch;
	background-color: #f5f5f5;
	overflow: auto;
  }
  .footer {
    text-align: center;
    font-size: 0.8em;
  }
</style>
'

genhtml() (
	cd "$1"

    . ./meta.sh

	exec 1>index.html

	# Header
	echo "<!DOCTYPE html>"
	echo "<!-- generated by build.sh. DO NOT EDIT. -->"
	echo "<html lang=\"${lang:-en}\">"
	echo "<title>$title</title>"
	[ "$description" ] && echo "<meta name=\"description\" content=\"$description\">"
	echo "$header"
	[ "$1" != . ] && echo "<a href=\"..\">$blog_title</a><hr>"

	# Body
	pandoc *.md

	# Footer
	[ "$1" != . ] && echo "<hr>From: $author, $date"
)

for d in *; do
	[ -d "$d" ] && genhtml "$d"
done
genhtml .

# Fix for mastodon.
sed '/mstdn/s/href=/rel="me" href=/' index.html >xx && mv xx index.html
# Put a license in index footer.
echo '<hr><div class="footer">
<a href="feed.xml">RSS feed</a>. &emsp; &emsp; Licensed under
<a href="http://creativecommons.org/licenses/by/4.0/">CC BY 4.0</a>.
</div>' >>index.html
