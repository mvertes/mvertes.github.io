# Generate the static web site from markdown files.
build:
	./build.sh

# Launch a local web server.
server:
	yaegi -e 'http.ListenAndServe(":8080", http.FileServer(http.Dir(".")))'

# Publish on github pages.
publish:
	git push
