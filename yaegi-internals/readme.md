# Yaegi internals

[Yaegi] is an interpreter of the Go language written in Go. This project
was started in Traefik-Labs initially to provide a simple and practical
embedded plugin engine for the traefik reverse proxy.  Now, more than
200 plugins contributed by the community are listed on the public
catalog at [plugins.traefik.io]. The use of yaegi extends also to other
domains, for example [databases], [observability], [container security]
and many
[others](https://github.com/traefik/yaegi/network/dependents?package_id=UGFja2FnZS0yMjc1NTQ3MjIy).

Yaegi is lean and mean, as it delivers in a single package, with no
external dependency, a complete Go interpreter, compliant with the [Go
specification]. Lean, but also mean: its code is dense, complex, not
always idiomatic, and sometimes maybe hard to understand.

This document is here to address that. In the following, after getting
an overview, we look under the hood, explore the internals and discuss
the design. Our aim is to provide the essential insights, clarify the
architecture and the code organization. But first, the overview.

## Overview of architecture

Let's see what happens inside yaegi when one executes the following
line:

```go
interp.Eval(`print("hello", 2+3)`)
```

The following figure 1 displays the main steps of evaluation:

![figure 1: steps of evaluation](yaegi_internals_fig1.drawio.svg)

1. The *scanner* (provided by the [go/scanner] package) transforms a
   stream of characters (the source code) into a stream of tokens,
   through a [lexical analysis] step.

2. The *parser* (provided by the [go/parser] package) transforms the
   stream of tokens into an [abstract syntax tree] or AST, through a
   [syntax analysis] step.

3. The *analyser* (implemented in the [yaegi/interp] package) performs
   the checks and creation of type, constant, variable and function
   symbols. It also computes the [control-flow graphs] and memory
   allocations for symbols, through [semantic analysis] steps. All those
   metadata are obtained from and stored to the nodes of the AST, making
   it annotated.

4. The *generator* (implemented in the [yaegi/interp] package) reads the
   annotated AST and produces code intructions to be executed, through a
   [code generation] step.

5. The *executor* (implemented in the [yaegi/interp] package) runs the
   code instructions in the context of the interpreter.

The interpreter is designed as a simple compiler, except that the code
is generated into memory instead of object files, and with an executor
module to run the specific instruction format.

We won't spend more details on the scanner and the parser, both provided
by the standard library, and instead examine directly the analyser.

## Semantic analysis

The analyser performs the semantic analysis of the program to interpret.
This is done in several steps, all consisting of reading from and
writing to the AST, so we first examine the details and dynamics of our
AST representation.

### AST dynamics

Hereafter stands the most important data structure of any compiler,
interpreter or other language tool, and the function to use it
(extracted from
[here](https://github.com/traefik/yaegi/blob/8de3add6faf471a807182c7b8198fe863debc9d8/interp/interp.go#L284-L296)).

```go
// node defines a node of a (abstract syntax) tree.
type node struct {
    // Node children
    child []*node
    // Node metadata
    ...
}

// walk traverses AST n in depth first order, invoking in function
// at node entry and out function at node exit.
func (n *node) walk(in func(n *node) bool, out func(n *node)) {
    if in != nil && !in(n) {
        return
    }
    for _, child := range n.child {
        child.Walk(in, out)
    }
    if out != nil {
        out(n)
    }
}
```

The above code is deceptively simple. As in many complex systems, an
important part of the signification is carried by the relationships
between the elements and the patterns they form.  It's easier to
understand it by displaying the corresponding graph and consider the
system as a whole. We can do that using a simple example:

```go
a := 3
if a > 2 {
    print("ok")
}
print("bye")
```

The corresponding AST is:

![figure 2: a raw AST](ex1_raw_ast.drawio.svg)

This is the raw AST, with no annotations, as obtained from the parser.
Each node contains an index number (for labelling purpose only), and the
node type, computed by the parser from the set of Go grammar rules (i.e.
"stmt" for "list of [statements]", "call" for "call [expression]", ...).
We also recognize the source tokens as literal values in leaf locations.

Walking the tree consists in visiting the nodes starting from the root
(node 1), in their numbering order (here from 1 to 15): depth first (the
children before the siblings) and from left to right. At each node, a
callback `in` is invoked at entry (pre-processing) and a callback `out`
at exit (post-processing).

When the `in` callback executes, only the information computed in the
sub-trees in the left of the node is available, in addition to the
pre-processing information computed in the node ancestors. The `in`
callback returns a boolean. If the result is false, the node sub-tree is
skipped, allowing to short-cut processing, for example to avoid to dive
in function bodies and process only function signatures.

When the `out` callback executes, the results computed on the whole
descendant sub-trees are available, which is useful for example to
compute the size of a composite object defined accross nested
structures. In the absence of post-processing, multiple tree walks are
necessary to achieve the same result.

A semantic analysis step is therefore simply a tree walk with the right
callbacks. In the case of our interpreter, we have two tree walks to
perform: the globals and types analysis in [interp/gta.go] and the
control-flow graphs analysis in [interp/cfg.go]. In both files, notice
the call to `root.Walk`.

Note: we have chosen to represent the AST as a uniform node structure
as opposed to the [ast.Node] interface in the Go standard library,
implemented by specialized types for all the node kinds. The main
reason is that the tree walk method [ast.Inspect] only permits a
pre-processing callback, not a post-processing one, required for
several compiling steps. It also seemed simpler at the time to start
with this uniform structure, and we ended up sticking with it.

### Globals and types analysis

Our first operation on the AST is to check and register all the
components of the program declared at global level. This is a partial
analysis, concerned only about declarations and not function
implementations.

This step is necessary because in Go, at global level, symbols can be
used before being declared (as opposed to Go function bodies, or in C in
general, where use before declaration is simply forbidden in strict
mode).

Allowing out of order symbols is what permits the code to be scattered
arbitrarily amongst several files in packages without more constraints.
It is indeed an important feature to let the programer organize her code
as she wants.

This step, implemented in [interp/gta.go], consists in performing a tree
walk with only a pre-processing callback (no `out` function is passed).
There are two particularities:

The first is the multiple-pass iterative walk. Indeed, in a first global
pass, instead of failing with an error whenever an incomplete definition
is met, the reference to the failing sub-tree is kept in a list of nodes
to be retried, and the walk finishes going over the whole tree. Then,
all the problematic sub-trees are iteratively retried until all the
nodes have been defined, or as long as there is progress. That is, if
two subsequent iterations lead to the exact same state, it is a hint
that progress is not being made and it would result in an infinite loop,
at which point yaegi just stops with an error.

The second particularity is that despite being in a partial analysis
step, a full interpretation can still be necessary on an expression
sub-tree if this one serves to implement a global type definition. For
example if an array size is computed by an expression as in the
following valid Go declarations:

```go
const (
    prefix = "/usr"
    path   = prefix + "/local/bin"
)
var a [len(prefix+path) + 2]int
```

A paradox is that the compiler needs an interpreter to perform the type
analysis! Indeed, in the example above, `[16]int` (because
`len(prefix+path) + 2 = 16`) is a specific type in itself, distinct from
e.g. `[14]int`. Which means that even though we are only at the types
analysis phase we already must be able to compute the `len(prefix+path)
+ 2` expression. In the C language it is one of the roles of the
[pre-processor], which means the compiler itself does not need to be
able to achieve that.  Here in Go, the specification forces the compiler
implementor to provide and use early-on the mechanics involved above,
which is usually called constant folding optimisation. It is therefore
implemented both within the standard gc, and whithin yaegi.  The same
kind of approach is pushed to its paroxysm in the [Zig language] with
its [comptime] keyword.

### Control-flow graphs

After GTA, all the global symbols are properly defined no matter
their declaration order. We can now proceed with the full code
analysis, which will be performed by a single tree walk in
[interp/cfg.go].

Both pre-processing and post-processing callbacks are provided to the
walk function. Despite being activated in a single pass, multiple kinds
of data processing are executed:

- Types checking and creation. Started in GTA, it is now completed also
  in all function bodies.

- Analysis of variable scoping: scope levels are opened in
  pre-processing and closed in post-processing, as the nesting of scope
  reflects the AST structure.

- Precise computing of object sizes and locations.

- Identification and ordering of actions.

The last point is critical for code generation. It consists in the
production of control-flow graphs. CFGs are usually represented in the
form of an intermediate representation (IR), which really is a
simplified machine independent instruction set, as in the [GCC GIMPLE],
the [LLVM IR] or the [SSA] form in the Go compiler. In yaegi, no IR is
produced, only AST annotations are used.

Let's use our previous example to explain:

![figure 3: CFG is in AST](ex1_ast_cfg.drawio.svg)

In the AST, the nodes relevant to the CFG are the *action* nodes (in
blue), that is the nodes referring to an arithmetic or a logic
operation, a function call or a memory operation (assigning a variable,
accessing an array entry, ...).

Building the CFG consists in identifying action nodes and then find
their successor (to be stored in node fields `tnext` and `fnext`). An
action node has one successor in the general case (shown with a green
arrow), or two if the action is associated to a conditional branch
(green arrow if the test is true, red arrow otherwise).

The rules to determine the successor of an action node are inherent to
the properties of its neighbours (ancestors, siblings and descendants).
For example, in the `if` sub-tree (nodes 5 to 12), the first action to
execute is the condition test, that is, the first action in the
condition sub-tree, here the node 6.  This action will have two
alternative successors: one to execute if the test is true, the other
if not. The *true* successor will be the first action in the second
child sub-tree of the `if` node, describing the *true* branch (this
sub-tree root is node 9, and first action 10). As there is no `if`
*false* branch in our example, the next action of the whole `if`
sub-tree is the first action in the `if` sibling sub-tree, here the node
13. This node will be therefore the *false* successor, the first action
to execute when the `if` condition fails. Finally the node 13 is also
the successor of the *true* branch, the node 10. The corresponding
implementation is located in a [block of 16 lines] in the
post-processing CFG callback. Note that the same code also performs dead
branch elimination and condition validity checking.  At this stage, in
terms of Control Flow, our AST example can now be seen as a simpler
representation, such as the following.

![figure 4: the same CFG isolated](ex1_cfg.drawio.svg)

In our example, the action nodes composing the CFG can do the following
kind of operations:
- defining variables in memory and assigning values to them
- performing arithmetic or logical operations
- conditional branching
- function calling

Adding the capacity to jump to a *backward* location (where destination
node index is inferior to source's one, an arrow from right to
left), thus allowing *loops*, makes the action set to become
[Turing complete], implementing a universal computing machine.

![figure 5: a CFG with a loop](ex1_cfg_loop.drawio.svg)

The character of universality here lies in the cyclic nature of the
control-flow graph (remark that `if` statement graphs, although
appearing cyclic, are not, because the conditional branches are
mutually exclusives).

This is not just theoretical. For example, forbidding backward jumps was
crucial in the design of the Linux [eBPF verifier], in order to let user
provided (therefore untrusted) snippets execute in a kernel system
privileged environment and guarantee no infinite loops.

## Code generation and execution

The compiler implemented in yaegi targets the Go runtime itself, not a
particular hardware architecture. For each action node in the CFG a
corresponding closure is generated. The main benefits are:

- Portability: the generated code runs on any platform where Go is
  supported.
- Interoperability: the objects produced by the interpreter are directly
  usable by the host program in the form of reflect values.
- The memory management in particular the garbage collector, is provided
  by the runtime, and applies also to the values created by the
  interpreter.
- The support of runtime type safety, slices, maps, channels, goroutines
  is also provided by the runtime.

The action templates are located in [interp/run.go] and [interp/op.go].
Generating closures allows to optimize all the cases where a constant is
used (an operation involving a constant and a variable is cheaper and
faster than the same operation involving two variables). It also permits
to hard-code the control-flow graph, that is to pre-define the next
instruction to execute and avoid useless branch tests.

The pseudo architecture targeted by the interpreter is in effect a
virtual [stack machine] where the memory is represented as slices of Go
reflect values, as shown in the following figure, and where the
instructions are represented directly by the set of action nodes (the
CFG) in the AST.  Those atomic instructions, also called *builtins*, are
sligthly higher level than a real hardware instruction set, because they
operate directly on Go interfaces (more precisely their reflect
representation), hiding a lot of low level processing and subtleties
provided by the Go runtime.

![figure 6: frame organization](frame1.drawio.svg)

The memory management performed by the interpreter consists to create a
global frame at a new session (the top of the stack), populated with all
global values (constants, types, variables and functions). At each new
interpreted function call, a new frame is pushed on the stack,
containing the values for all the return value, input parameters and
local variables of the function.

## Conclusion

We have described the general architecture of a Go interpreter, reusing
the existing Go scanner and parser. We have focused on the semantic
analysis, which is based on AST annotations, up to the control-flow
graph and code generation.  This design leads to a consistent and
concise compiler suitable for an embedded interpreter.  We have also
provided a succint overview of the virtual stack machine on top of the
Go runtime, leveraging on the reflection layer provided by the Go
standard library.

We can now evolve this design to address different target architectures,
for example a more efficient virtual machine, already in the works.

Some parts of yaegi have not been detailed yet and will be addressed in
a next article:

- Integration with pre-compiled packages
- Go Generics
- Recursive types
- Interfaces and methods
- Virtualization and sandboxing
- REPL and interactive use

P.S. Thanks to [@lejatorn](https://twitter.com/@lejatorn) for his feedback
and suggestions on this post.

[Yaegi]: https://github.com/traefik/yaegi
[plugins.traefik.io]: https://plugins.traefik.io
[databases]: https://github.com/xo/xo
[observability]: https://github.com/slok/sloth
[container security]: https://github.com/cyberark/kubesploit
[Go specification]: https://go.dev/ref/spec
[go/scanner]: https://pkg.go.dev/go/scanner
[go/parser]: https://pkg.go.dev/go/parser
[abstract syntax tree]: https://en.wikipedia.org/wiki/Abstract_syntax_tree
[lexical analysis]: https://en.wikipedia.org/wiki/Lexical_analysis
[syntax analysis]: https://en.wikipedia.org/wiki/Syntax_analysis
[semantic analysis]: https://en.wikipedia.org/wiki/Semantic_analysis_(compilers)
[control-flow graphs]: https://en.wikipedia.org/wiki/Control-flow_graph
[yaegi/interp]: https://pkg.go.dev/github.com/traefik/yaegi/interp
[code generation]: https://en.wikipedia.org/wiki/Code_generation_%28compiler%29
[ast.Node]: https://pkg.go.dev/go/ast#Node
[ast.Inspect]: https://pkg.go.dev/go/ast#Inspect
[statements]: https://go.dev/ref/spec#Statements
[expression]: https://go.dev/ref/spec#Expressions
[Turing complete]: https://en.wikipedia.org/wiki/Turing_completeness
[eBPF verifier]: https://www.kernel.org/doc/html/latest/bpf/verifier.html
[interp/gta.go]: https://github.com/traefik/yaegi/blob/master/interp/gta.go
[interp/cfg.go]: https://github.com/traefik/yaegi/blob/master/interp/cfg.go
[interp/run.go]: https://github.com/traefik/yaegi/blob/master/interp/run.go
[interp/op.go]: https://github.com/traefik/yaegi/blob/master/interp/op.go
[pre-processor]: https://gcc.gnu.org/onlinedocs/cpp/
[GCC GIMPLE]: https://gcc.gnu.org/onlinedocs/gccint/GIMPLE.html
[LLVM IR]: https://llvm.org/docs/LangRef.html
[SSA]: https://github.com/golang/go/blob/bf48163e8f2b604f3b9e83951e331cd11edd8495/src/cmd/compile/internal/ssa/README.md
[block of 16 lines]: https://github.com/traefik/yaegi/blob/8de3add6faf471a807182c7b8198fe863debc9d8/interp/cfg.go#L1608-L1624
[Zig language]: https://ziglang.org
[comptime]: https://ziglang.org/documentation/master/#comptime
[stack machine]: https://en.wikipedia.org/wiki/Stack_machine
