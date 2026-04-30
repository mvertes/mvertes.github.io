# Announcing mvm

A few years ago, I wrote my first Go program. I was not exactly a beginner,
having years of deep C programming experience in domains like air traffic
control systems, telecoms, and operating systems.

That first Go program was [yaegi](https://github.com/traefik/yaegi), a Go
interpreter — a way to really understand the philosophy of this marvelous
language from within, by applying it to itself. It went well: yaegi became
widely adopted and, with the help of many, improved quite a lot.

But not everything I learned along the way could be folded back into that
first program without breaking it. On many levels, the time had come to
start over from scratch — and here it is: mvm.

I won't go into deep technical discussions in this post. Today is about
the rebirth of my first Go program. Still a Go interpreter, but much more
than that.

The function is the same, but the inner architecture is completely
different.

Yaegi is monolithic (a single package); mvm is modular (4 main packages).

Yaegi is a pure interpreter; mvm is a compiler and a VM disguised as an
interpreter.

Yaegi offloads parsing to the standard library; mvm takes full control of
it, and will eventually become multi-language.

Yaegi has no VM. Mvm is a VM - and that is a profound game changer. More
on that soon.

And if it goes well, with your help, it will be my second and last first
Go program.

--
Marc

[http://mvm.sh](https://mvm.sh)
